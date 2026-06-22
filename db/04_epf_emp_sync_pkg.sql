-- ============================================================
--  EPF_EMP_SYNC_PKG  –  DFN API daily employee sync
-- ============================================================

CREATE OR REPLACE PACKAGE EPF_EMP_SYNC_PKG AS

PROCEDURE FETCH_FROM_DFN_API (
    p_company_id    IN  NUMBER,
    p_out_count     OUT NUMBER
);

PROCEDURE PROCESS_STAGING_BATCH (
    p_company_id    IN  NUMBER,
    p_batch_date    IN  DATE DEFAULT TRUNC(SYSDATE)
);

PROCEDURE SYNC_COMPANY_EMPLOYEES (
    p_company_id    IN  NUMBER
);

PROCEDURE RUN_DAILY_SYNC;

END EPF_EMP_SYNC_PKG;
/

CREATE OR REPLACE PACKAGE BODY EPF_EMP_SYNC_PKG AS

-- ── Private: hash a password ──────────────────────────────────
FUNCTION HASH_PASSWORD (p_pwd IN VARCHAR2, p_salt OUT RAW) RETURN RAW IS
BEGIN
    p_salt := UC_CRYPTO.RANDOMBYTES(32);
    RETURN UC_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(p_pwd) || p_salt, UC_CRYPTO.HASH_SH512);
END HASH_PASSWORD;

-- ============================================================
--  FETCH_FROM_DFN_API
-- ============================================================
PROCEDURE FETCH_FROM_DFN_API (
    p_company_id    IN  NUMBER,
    p_out_count     OUT NUMBER
) IS
    v_base_url     VARCHAR2(500);
    v_api_key      VARCHAR2(200);
    v_acct_code    VARCHAR2(100);
    v_response     CLOB;
    v_folio_cnt    NUMBER := 0;
BEGIN
    -- Get API config
    SELECT CONFIG_VALUE INTO v_base_url  FROM EPF_API_CONFIG WHERE CONFIG_KEY = 'DFN_BASE_URL';
    SELECT CONFIG_VALUE INTO v_api_key   FROM EPF_API_CONFIG WHERE CONFIG_KEY = 'DFN_API_KEY';
    SELECT DFN_ACCOUNT_CODE INTO v_acct_code FROM EPF_COMPANIES WHERE COMPANY_ID = p_company_id;

    IF v_acct_code IS NULL THEN
        RAISE_APPLICATION_ERROR(-20010,'DFN_ACCOUNT_CODE not set for company '||p_company_id);
    END IF;

    -- Call DFN API
    APEX_WEB_SERVICE.SET_REQUEST_HEADERS('X-API-KEY', v_api_key, p_reset => TRUE);
    v_response := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
        p_url         => v_base_url || '/accounts/' || v_acct_code || '/folios',
        p_http_method => 'GET'
    );

    IF APEX_WEB_SERVICE.G_STATUS_CODE NOT IN (200, 201) THEN
        RAISE_APPLICATION_ERROR(-20011,'DFN API returned HTTP '||APEX_WEB_SERVICE.G_STATUS_CODE);
    END IF;

    -- Parse JSON array
    APEX_JSON.PARSE(v_response);
    DECLARE
        v_idx  NUMBER := 1;
    BEGIN
        LOOP
            DECLARE
                v_folio_no   VARCHAR2(50)  := APEX_JSON.GET_VARCHAR2('[%d].folio_number',  v_idx);
            BEGIN
                EXIT WHEN v_folio_no IS NULL;

                MERGE INTO EPF_EMP_API_STAGING s
                USING (SELECT p_company_id AS CID, v_folio_no AS FNO, TRUNC(SYSDATE) AS BD FROM DUAL) d
                ON (s.COMPANY_ID = d.CID AND s.FOLIO_NUMBER = d.FNO AND s.BATCH_DATE = d.BD)
                WHEN NOT MATCHED THEN INSERT (
                    COMPANY_ID, FOLIO_NUMBER, CNIC, FULL_NAME, EMAIL, MOBILE_NO,
                    EMPLOYEE_CODE, FUND_CODES, DFN_FOLIO_ID, DFN_INVESTOR_ID,
                    PROCESS_STATUS, BATCH_DATE, FETCHED_DATE
                ) VALUES (
                    p_company_id,
                    v_folio_no,
                    APEX_JSON.GET_VARCHAR2('[%d].cnic',           v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].full_name',      v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].email',          v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].mobile_no',      v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].employee_code',  v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].fund_codes',     v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].folio_id',       v_idx),
                    APEX_JSON.GET_VARCHAR2('[%d].investor_id',    v_idx),
                    'PENDING', TRUNC(SYSDATE), SYSDATE
                );

                v_folio_cnt := v_folio_cnt + 1;
                v_idx := v_idx + 1;
            EXCEPTION WHEN OTHERS THEN EXIT;
            END;
        END LOOP;
    END;

    COMMIT;
    p_out_count := v_folio_cnt;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    INSERT INTO EPF_ACTIVITY_LOG (ENTITY_TYPE, ENTITY_ID, ACTION_CODE, REMARKS, PERFORMED_BY, PERFORMED_DATE)
    VALUES ('SYNC', p_company_id, 'DFN_FETCH_ERROR', SQLERRM, 0, SYSDATE);
    COMMIT;
    RAISE;
END FETCH_FROM_DFN_API;

-- ============================================================
--  PROCESS_STAGING_BATCH
-- ============================================================
PROCEDURE PROCESS_STAGING_BATCH (
    p_company_id    IN  NUMBER,
    p_batch_date    IN  DATE DEFAULT TRUNC(SYSDATE)
) IS
    v_user_id      NUMBER;
    v_folio_id     NUMBER;
    v_cnt          NUMBER;
    v_salt         RAW(32);
    v_hash         RAW(64);
    v_status_pend  NUMBER;
    v_status_act   NUMBER;
    v_role_emp     CONSTANT NUMBER := 9;
    v_processed    NUMBER := 0;
    v_pwd          CONSTANT VARCHAR2(20) := 'EPF@2024!';
    v_folio_status NUMBER;
BEGIN
    SELECT STATUS_ID INTO v_status_pend FROM EPF_STATUSES
    WHERE  CATEGORY_CODE = 'USER_STATUS' AND STATUS_CODE = 'PENDING' AND ROWNUM = 1;
    SELECT STATUS_ID INTO v_status_act  FROM EPF_STATUSES
    WHERE  CATEGORY_CODE = 'USER_STATUS' AND STATUS_CODE = 'ACTIVE'  AND ROWNUM = 1;
    SELECT STATUS_ID INTO v_folio_status FROM EPF_STATUSES
    WHERE  CATEGORY_CODE = 'CLIENT_STATUS' AND STATUS_CODE = 'PENDING_CHECKER' AND ROWNUM = 1;

    FOR stg IN (
        SELECT * FROM EPF_EMP_API_STAGING
        WHERE  COMPANY_ID    = p_company_id
        AND    BATCH_DATE    = p_batch_date
        AND    PROCESS_STATUS = 'PENDING'
        FOR UPDATE
    ) LOOP
        SAVEPOINT sp_emp;
        BEGIN
            -- ── STEP 1: FOLIO ──────────────────────────────────────
            BEGIN
                SELECT FOLIO_ID INTO v_folio_id
                FROM   EPF_FOLIOS
                WHERE  COMPANY_ID   = p_company_id
                AND    FOLIO_NUMBER = stg.FOLIO_NUMBER;
            EXCEPTION WHEN NO_DATA_FOUND THEN
                INSERT INTO EPF_FOLIOS (COMPANY_ID, FOLIO_NUMBER, DFN_FOLIO_ID, STATUS_ID, CREATED_BY, CREATED_DATE)
                VALUES (p_company_id, stg.FOLIO_NUMBER, stg.DFN_FOLIO_ID, v_folio_status, 0, SYSDATE)
                RETURNING FOLIO_ID INTO v_folio_id;
            END;

            -- ── STEP 2: FOLIO_FUND_MAPPING ─────────────────────────
            IF stg.FUND_CODES IS NOT NULL THEN
                FOR fc IN (SELECT TRIM(COLUMN_VALUE) AS FCODE
                           FROM TABLE(APEX_STRING.SPLIT(stg.FUND_CODES,','))
                           WHERE TRIM(COLUMN_VALUE) IS NOT NULL)
                LOOP
                    MERGE INTO EPF_FOLIO_FUND_MAPPING m
                    USING (SELECT v_folio_id AS FID,
                                  (SELECT FUND_ID FROM EPF_FUNDS WHERE FUND_CODE = fc.FCODE AND ROWNUM=1) AS FUNID
                           FROM DUAL) d
                    ON (m.FOLIO_ID = d.FID AND m.FUND_ID = d.FUNID)
                    WHEN NOT MATCHED THEN INSERT (FOLIO_ID, FUND_ID, CREATED_BY, CREATED_DATE)
                    VALUES (d.FID, d.FUNID, 0, SYSDATE);
                END LOOP;
            END IF;

            -- ── STEP 3: USER ───────────────────────────────────────
            IF stg.EMAIL IS NOT NULL THEN
                BEGIN
                    SELECT USER_ID INTO v_user_id FROM EPF_USERS
                    WHERE  LOWER(EMAIL) = LOWER(stg.EMAIL) AND ROWNUM=1;
                    -- Enrich missing fields
                    UPDATE EPF_USERS SET
                        FULL_NAME     = NVL2(FULL_NAME,     FULL_NAME,     stg.FULL_NAME),
                        CNIC          = NVL2(CNIC,           CNIC,          stg.CNIC),
                        MOBILE_NO     = NVL2(MOBILE_NO,      MOBILE_NO,     stg.MOBILE_NO),
                        EMPLOYEE_CODE = NVL2(EMPLOYEE_CODE,  EMPLOYEE_CODE, stg.EMPLOYEE_CODE),
                        UPDATED_DATE  = SYSDATE
                    WHERE USER_ID = v_user_id;
                EXCEPTION WHEN NO_DATA_FOUND THEN
                    v_hash := HASH_PASSWORD(v_pwd, v_salt);
                    INSERT INTO EPF_USERS
                        (FULL_NAME, EMAIL, CNIC, MOBILE_NO, EMPLOYEE_CODE,
                         PASSWORD_HASH, PASSWORD_SALT, STATUS_ID, FORCE_PWD_CHANGE,
                         CREATED_BY, CREATED_DATE)
                    VALUES
                        (stg.FULL_NAME, LOWER(stg.EMAIL), stg.CNIC, stg.MOBILE_NO, stg.EMPLOYEE_CODE,
                         RAWTOHEX(v_hash), RAWTOHEX(v_salt), v_status_pend, 'Y',
                         0, SYSDATE)
                    RETURNING USER_ID INTO v_user_id;
                END;

                -- ── STEP 4: USER_COMPANIES ─────────────────────────
                MERGE INTO EPF_USER_COMPANIES uc
                USING (SELECT v_user_id AS UID, p_company_id AS CID FROM DUAL) d
                ON (uc.USER_ID = d.UID AND uc.COMPANY_ID = d.CID)
                WHEN MATCHED THEN UPDATE SET
                    FOLIO_ID     = NVL(uc.FOLIO_ID, v_folio_id),
                    UPDATED_DATE = SYSDATE
                WHEN NOT MATCHED THEN INSERT
                    (USER_ID, COMPANY_ID, FOLIO_ID, STATUS_ID, CREATED_BY, CREATED_DATE)
                VALUES
                    (v_user_id, p_company_id, v_folio_id, v_status_pend, 0, SYSDATE);

                -- ── STEP 5: USER_COMP_ROLES (EMPLOYEE) ────────────
                SELECT COUNT(*) INTO v_cnt
                FROM   EPF_USER_COMP_ROLES
                WHERE  USER_ID = v_user_id AND COMPANY_ID = p_company_id AND ROLE_ID = v_role_emp;

                IF v_cnt = 0 THEN
                    INSERT INTO EPF_USER_COMP_ROLES (USER_ID, COMPANY_ID, ROLE_ID, CREATED_BY, CREATED_DATE)
                    VALUES (v_user_id, p_company_id, v_role_emp, 0, SYSDATE);
                END IF;
            END IF;

            -- Mark processed
            UPDATE EPF_EMP_API_STAGING SET
                PROCESS_STATUS  = 'PROCESSED',
                PROCESSED_DATE  = SYSDATE,
                PROCESS_MESSAGE = 'OK'
            WHERE STAGING_ID = stg.STAGING_ID;

            v_processed := v_processed + 1;

        EXCEPTION WHEN OTHERS THEN
            ROLLBACK TO sp_emp;
            UPDATE EPF_EMP_API_STAGING SET
                PROCESS_STATUS  = 'ERROR',
                PROCESS_MESSAGE = SUBSTR(SQLERRM,1,3000)
            WHERE STAGING_ID = stg.STAGING_ID;
        END;
    END LOOP;

    -- Mark Tab4 complete if any rows were processed
    IF v_processed > 0 THEN
        UPDATE EPF_ONBOARDING_SUBMISSIONS
        SET    TAB4_COMPLETE = 'Y', UPDATED_DATE = SYSDATE
        WHERE  COMPANY_ID = p_company_id;
    END IF;

    COMMIT;
END PROCESS_STAGING_BATCH;

-- ============================================================
--  SYNC_COMPANY_EMPLOYEES
-- ============================================================
PROCEDURE SYNC_COMPANY_EMPLOYEES (p_company_id IN NUMBER) IS
    v_cnt NUMBER;
BEGIN
    FETCH_FROM_DFN_API(p_company_id, v_cnt);
    PROCESS_STAGING_BATCH(p_company_id, TRUNC(SYSDATE));
END SYNC_COMPANY_EMPLOYEES;

-- ============================================================
--  RUN_DAILY_SYNC
-- ============================================================
PROCEDURE RUN_DAILY_SYNC IS
BEGIN
    FOR c IN (
        SELECT c.COMPANY_ID
        FROM   EPF_COMPANIES c
        JOIN   EPF_STATUSES  s ON s.STATUS_ID = c.STATUS_ID
        WHERE  s.STATUS_CODE IN ('ACTIVE','PENDING_CHECKER')
        AND    c.DFN_ACCOUNT_CODE IS NOT NULL
    ) LOOP
        BEGIN
            SYNC_COMPANY_EMPLOYEES(c.COMPANY_ID);
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO EPF_ACTIVITY_LOG
                (ENTITY_TYPE, ENTITY_ID, ACTION_CODE, REMARKS, PERFORMED_BY, PERFORMED_DATE)
            VALUES ('SYNC', c.COMPANY_ID, 'SYNC_ERROR', SQLERRM, 0, SYSDATE);
            COMMIT;
        END;
    END LOOP;
END RUN_DAILY_SYNC;

END EPF_EMP_SYNC_PKG;
/

-- ── Scheduler Job ─────────────────────────────────────────────
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'EPF_EMP_DAILY_SYNC',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN EPF_EMP_SYNC_PKG.RUN_DAILY_SYNC; END;',
        start_date      => TRUNC(SYSDATE+1) + 2/24,   -- next 2 AM
        repeat_interval => 'FREQ=DAILY;BYHOUR=2;BYMINUTE=0;BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Daily DFN API employee data sync'
    );
END;
/
