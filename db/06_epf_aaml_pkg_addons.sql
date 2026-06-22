-- ============================================================
--  EPF_AAML_PKG  –  Additions to match existing APEX processes
--  These procedures/functions use the exact signatures confirmed
--  in the Application Dependencies review.
-- ============================================================

CREATE OR REPLACE PACKAGE EPF_AAML_PKG AS

-- ── Already-used by existing APEX processes (confirmed sigs) ─

FUNCTION SAVE_CLIENT (
    p_company_id        IN  NUMBER,
    p_company_name      IN  VARCHAR2,
    p_group_id          IN  NUMBER,
    p_new_group_name    IN  VARCHAR2,
    p_is_primary        IN  VARCHAR2,
    p_fund1_id          IN  NUMBER,
    p_fund2_id          IN  NUMBER,
    p_loan_enabled      IN  VARCHAR2,
    p_interest_type_id  IN  NUMBER,
    p_float_tenure      IN  NUMBER,
    p_interest_rate     IN  NUMBER,
    p_loan_limit_pct    IN  NUMBER,
    p_max_instalment_mo IN  NUMBER,
    p_realloc_enabled   IN  VARCHAR2,
    p_mm_limit          IN  NUMBER,
    p_debt_limit        IN  NUMBER,
    p_equity_limit      IN  NUMBER,
    p_admin_user_id     IN  NUMBER,
    p_created_by        IN  NUMBER
) RETURN NUMBER;

PROCEDURE SUBMIT_TO_CHECKER (
    p_company_id        IN  NUMBER,
    p_submitted_by      IN  NUMBER
);

PROCEDURE CHECKER_APPROVE (
    p_company_id        IN  NUMBER,
    p_remarks           IN  VARCHAR2,
    p_approved_by       IN  NUMBER
);

PROCEDURE CHECKER_REJECT (
    p_company_id        IN  NUMBER,
    p_remarks           IN  VARCHAR2,
    p_rejected_by       IN  NUMBER
);

PROCEDURE CHECKER_REVERT (
    p_company_id        IN  NUMBER,
    p_remarks           IN  VARCHAR2,
    p_reverted_by       IN  NUMBER
);

-- ── New procedures (added for onboarding wizard) ─────────────

PROCEDURE INIT_ONBOARDING (
    p_company_id        IN  NUMBER,
    p_user_id           IN  NUMBER,
    p_out_submission_id OUT NUMBER,
    p_out_ref_no        OUT VARCHAR2
);

PROCEDURE SAVE_COMPANY_USER (
    p_company_id         IN  NUMBER,
    p_user_company_id    IN  NUMBER,
    p_folio_id           IN  NUMBER,
    p_role_id            IN  NUMBER,
    p_full_name          IN  VARCHAR2,
    p_email              IN  VARCHAR2,
    p_cnic               IN  VARCHAR2,
    p_mobile_no          IN  VARCHAR2,
    p_employee_code      IN  VARCHAR2,
    p_performed_by       IN  NUMBER,
    p_out_user_id        OUT NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE SAVE_AUTHORIZER_GROUP (
    p_group_id           IN  NUMBER,
    p_company_id         IN  NUMBER,
    p_group_name         IN  VARCHAR2,
    p_min_approvals      IN  NUMBER,
    p_member_user_ids    IN  VARCHAR2,
    p_performed_by       IN  NUMBER,
    p_out_group_id       OUT NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE BEGIN_CHANGE_REQUEST (
    p_company_id         IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_change_req_id  OUT NUMBER,
    p_out_ref_no         OUT VARCHAR2
);

PROCEDURE SAVE_CR_SECTION (
    p_change_req_id      IN  NUMBER,
    p_section_code       IN  VARCHAR2,
    p_new_values_json    IN  CLOB,
    p_change_summary     IN  VARCHAR2,
    p_user_id            IN  NUMBER
);

PROCEDURE SUBMIT_CR_TO_CHECKER (
    p_change_req_id      IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE CR_CHECKER_APPROVE (
    p_change_req_id      IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_remarks            IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE CR_CHECKER_REVERT (
    p_change_req_id      IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_revert_remarks     IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

END EPF_AAML_PKG;
/

-- ─────────────────────────────────────────────────────────────
-- PACKAGE BODY  (only the NEW/FIXED procedures shown;
-- rest from 03_epf_aaml_pkg_body.sql apply unchanged)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_AAML_PKG AS

-- ── Private helper: status ID lookup via EPF_STATUS_PKG  ─────
FUNCTION GET_SID (p_cat IN VARCHAR2, p_code IN VARCHAR2) RETURN NUMBER IS
BEGIN
    RETURN EPF_STATUS_PKG.GET_ID(p_cat, p_code);
END GET_SID;

-- ── Private: ref number generator  ───────────────────────────
FUNCTION GEN_REF_NO (p_prefix IN VARCHAR2) RETURN VARCHAR2 IS
    v_seq NUMBER;
    v_ym  VARCHAR2(6) := TO_CHAR(SYSDATE,'YYYYMM');
BEGIN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(REF_NO,-6))),0)+1
    INTO   v_seq
    FROM (
        SELECT SUBMISSION_REF_NO AS REF_NO FROM EPF_ONBOARDING_SUBMISSIONS
        WHERE  SUBMISSION_REF_NO LIKE p_prefix||'-'||v_ym||'-%'
        UNION ALL
        SELECT CHANGE_REQ_REF_NO FROM EPF_CLIENT_CHANGE_REQUESTS
        WHERE  CHANGE_REQ_REF_NO LIKE p_prefix||'-'||v_ym||'-%'
    );
    RETURN p_prefix||'-'||v_ym||'-'||LPAD(v_seq,6,'0');
END GEN_REF_NO;

-- ── Private: activity logger  ─────────────────────────────────
PROCEDURE LOG_ACTIVITY (p_entity_type IN VARCHAR2, p_entity_id IN NUMBER,
                         p_action_code IN VARCHAR2, p_remarks IN VARCHAR2,
                         p_user_id     IN NUMBER) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO EPF_ACTIVITY_LOG (ENTITY_TYPE,ENTITY_ID,ACTION_CODE,REMARKS,PERFORMED_BY,PERFORMED_DATE)
    VALUES (p_entity_type,p_entity_id,p_action_code,p_remarks,p_user_id,SYSDATE);
    COMMIT;
END LOG_ACTIVITY;

-- ── Private: validation helpers  ─────────────────────────────
FUNCTION VALIDATE_EMAIL (p_email IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
    IF p_email IS NULL THEN RETURN 'Email is required.'; END IF;
    IF NOT REGEXP_LIKE(p_email,'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')
    THEN RETURN 'Invalid email format: '||p_email; END IF;
    RETURN NULL;
END;

FUNCTION VALIDATE_CNIC (p_cnic IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
    IF p_cnic IS NULL THEN RETURN NULL; END IF;
    IF NOT REGEXP_LIKE(p_cnic,'^\d{13}$') AND NOT REGEXP_LIKE(p_cnic,'^\d{5}-\d{7}-\d{1}$')
    THEN RETURN 'CNIC must be 13 digits.'; END IF;
    RETURN NULL;
END;

FUNCTION VALIDATE_MOBILE (p_mobile IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
    IF p_mobile IS NULL THEN RETURN NULL; END IF;
    IF NOT REGEXP_LIKE(p_mobile,'^(\+92|0)?3[0-9]{9}$')
    THEN RETURN 'Mobile must be a valid Pakistani number.'; END IF;
    RETURN NULL;
END;

-- ══════════════════════════════════════════════════════════════
--  SAVE_CLIENT  (function – returns company_id)
--  This is the signature called by the existing APEX process
--  EPF_SAVE_CLIENT on Page 4.
-- ══════════════════════════════════════════════════════════════
FUNCTION SAVE_CLIENT (
    p_company_id        IN  NUMBER,
    p_company_name      IN  VARCHAR2,
    p_group_id          IN  NUMBER,
    p_new_group_name    IN  VARCHAR2,
    p_is_primary        IN  VARCHAR2,
    p_fund1_id          IN  NUMBER,
    p_fund2_id          IN  NUMBER,
    p_loan_enabled      IN  VARCHAR2,
    p_interest_type_id  IN  NUMBER,
    p_float_tenure      IN  NUMBER,
    p_interest_rate     IN  NUMBER,
    p_loan_limit_pct    IN  NUMBER,
    p_max_instalment_mo IN  NUMBER,
    p_realloc_enabled   IN  VARCHAR2,
    p_mm_limit          IN  NUMBER,
    p_debt_limit        IN  NUMBER,
    p_equity_limit      IN  NUMBER,
    p_admin_user_id     IN  NUMBER,
    p_created_by        IN  NUMBER
) RETURN NUMBER IS
    v_group_id    NUMBER := p_group_id;
    v_company_id  NUMBER := p_company_id;
    v_draft       NUMBER := GET_SID('CLIENT_STATUS','DRAFT');
BEGIN
    -- Create inline group if requested
    IF v_group_id IS NULL AND p_new_group_name IS NOT NULL THEN
        INSERT INTO EPF_COMPANY_GROUPS (GROUP_NAME, CREATED_BY, CREATED_DATE)
        VALUES (p_new_group_name, p_created_by, SYSDATE)
        RETURNING GROUP_ID INTO v_group_id;
    END IF;

    IF v_company_id IS NULL THEN
        -- New company
        SELECT EPF_COMPANY_SEQ.NEXTVAL INTO v_company_id FROM DUAL;
        INSERT INTO EPF_COMPANIES (
            COMPANY_ID, COMPANY_NAME, GROUP_ID, IS_PRIMARY,
            STATUS_ID, CREATED_BY, CREATED_DATE
        ) VALUES (
            v_company_id, p_company_name, v_group_id, NVL(p_is_primary,'N'),
            v_draft, p_created_by, SYSDATE
        );
    ELSE
        UPDATE EPF_COMPANIES SET
            COMPANY_NAME = p_company_name,
            GROUP_ID     = v_group_id,
            IS_PRIMARY   = NVL(p_is_primary,'N'),
            UPDATED_BY   = p_created_by,
            UPDATED_DATE = SYSDATE
        WHERE COMPANY_ID = v_company_id;
    END IF;

    -- UPSERT company settings (loan, realloc, fund limits)
    MERGE INTO EPF_COMPANY_SETTINGS cs
    USING (SELECT v_company_id AS CID FROM DUAL) s
    ON    (cs.COMPANY_ID = s.CID)
    WHEN MATCHED THEN UPDATE SET
        LOAN_ENABLED       = p_loan_enabled,
        INTEREST_TYPE_ID   = p_interest_type_id,
        FLOAT_TENURE       = p_float_tenure,
        INTEREST_RATE      = p_interest_rate,
        LOAN_LIMIT_PCT     = p_loan_limit_pct,
        MAX_INSTALMENT_MO  = p_max_instalment_mo,
        REALLOC_ENABLED    = p_realloc_enabled,
        MM_LIMIT           = p_mm_limit,
        DEBT_LIMIT         = p_debt_limit,
        EQUITY_LIMIT       = p_equity_limit,
        UPDATED_BY         = p_created_by,
        UPDATED_DATE       = SYSDATE
    WHEN NOT MATCHED THEN INSERT (
        COMPANY_ID, LOAN_ENABLED, INTEREST_TYPE_ID, FLOAT_TENURE,
        INTEREST_RATE, LOAN_LIMIT_PCT, MAX_INSTALMENT_MO,
        REALLOC_ENABLED, MM_LIMIT, DEBT_LIMIT, EQUITY_LIMIT,
        STATUS_ID, CREATED_BY, CREATED_DATE
    ) VALUES (
        v_company_id, p_loan_enabled, p_interest_type_id, p_float_tenure,
        p_interest_rate, p_loan_limit_pct, p_max_instalment_mo,
        p_realloc_enabled, p_mm_limit, p_debt_limit, p_equity_limit,
        v_draft, p_created_by, SYSDATE
    );

    -- Fund associations (fund1 + fund2)
    DELETE FROM EPF_COMPANY_FUNDS WHERE COMPANY_ID = v_company_id;
    IF p_fund1_id IS NOT NULL THEN
        INSERT INTO EPF_COMPANY_FUNDS (COMPANY_ID, FUND_ID, CREATED_BY, CREATED_DATE)
        VALUES (v_company_id, p_fund1_id, p_created_by, SYSDATE);
    END IF;
    IF p_fund2_id IS NOT NULL THEN
        INSERT INTO EPF_COMPANY_FUNDS (COMPANY_ID, FUND_ID, CREATED_BY, CREATED_DATE)
        VALUES (v_company_id, p_fund2_id, p_created_by, SYSDATE);
    END IF;

    -- Ensure an onboarding submission row exists
    DECLARE v_sid NUMBER; v_ref VARCHAR2(30);
    BEGIN INIT_ONBOARDING(v_company_id, p_created_by, v_sid, v_ref); END;

    COMMIT;
    RETURN v_company_id;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; RAISE;
END SAVE_CLIENT;

-- ══════════════════════════════════════════════════════════════
--  SUBMIT_TO_CHECKER  (2-param version used by existing process)
-- ══════════════════════════════════════════════════════════════
PROCEDURE SUBMIT_TO_CHECKER (p_company_id IN NUMBER, p_submitted_by IN NUMBER) IS
    v_pend   NUMBER := GET_SID('CLIENT_STATUS','PENDING_CHECKER');
    v_tab1   VARCHAR2(1); v_tab2 VARCHAR2(1); v_tab4 VARCHAR2(1);
    v_admin  NUMBER; v_auth NUMBER;
BEGIN
    BEGIN
        SELECT TAB1_COMPLETE, TAB2_COMPLETE, TAB4_COMPLETE
        INTO   v_tab1, v_tab2, v_tab4
        FROM   EPF_ONBOARDING_SUBMISSIONS WHERE COMPANY_ID = p_company_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;

    IF NVL(v_tab1,'N') != 'Y' THEN
        RAISE_APPLICATION_ERROR(-20001,'Tab 1 (Account Details) is not complete.');
    END IF;
    IF NVL(v_tab2,'N') != 'Y' THEN
        RAISE_APPLICATION_ERROR(-20002,'Tab 2 (Users) is not complete.');
    END IF;

    -- Validate at least 1 Corp Admin and 1 Authorizer
    SELECT COUNT(*) INTO v_admin
    FROM   EPF_USER_COMPANIES uc
    JOIN   EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
    JOIN   EPF_ROLES r ON r.ROLE_ID = ucr.ROLE_ID
    WHERE  uc.COMPANY_ID = p_company_id AND r.ROLE_CODE = 'CORP_ADMIN' AND ucr.IS_ACTIVE='Y';
    IF v_admin = 0 THEN
        RAISE_APPLICATION_ERROR(-20003,'At least one Corporate Admin must be assigned.');
    END IF;

    SELECT COUNT(*) INTO v_auth
    FROM   EPF_USER_COMPANIES uc
    JOIN   EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
    JOIN   EPF_ROLES r ON r.ROLE_ID = ucr.ROLE_ID
    WHERE  uc.COMPANY_ID = p_company_id AND r.ROLE_CODE = 'CORP_AUTHORIZER' AND ucr.IS_ACTIVE='Y';
    IF v_auth = 0 THEN
        RAISE_APPLICATION_ERROR(-20004,'At least one Corporate Authorizer must be assigned.');
    END IF;

    UPDATE EPF_COMPANIES          SET STATUS_ID=v_pend,UPDATED_BY=p_submitted_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_COMPANY_SETTINGS   SET STATUS_ID=v_pend,UPDATED_BY=p_submitted_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID=v_pend, SUBMITTED_BY=p_submitted_by, SUBMITTED_DATE=SYSDATE,
        UPDATED_BY=p_submitted_by, UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_USER_COMPANIES SET
        STATUS_ID=v_pend, UPDATED_BY=p_submitted_by, UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id
    AND   EPF_STATUS_PKG.GET_CODE(STATUS_ID)='PENDING';

    COMMIT;
    LOG_ACTIVITY('CLIENT',p_company_id,'SUBMIT_TO_CHECKER',NULL,p_submitted_by);
END SUBMIT_TO_CHECKER;

-- ══════════════════════════════════════════════════════════════
--  CHECKER_APPROVE  (confirmed signature)
-- ══════════════════════════════════════════════════════════════
PROCEDURE CHECKER_APPROVE (p_company_id IN NUMBER, p_remarks IN VARCHAR2, p_approved_by IN NUMBER) IS
    v_active NUMBER := GET_SID('CLIENT_STATUS','ACTIVE');
    v_pend   NUMBER := GET_SID('CLIENT_STATUS','PENDING_CHECKER');
    v_cur    NUMBER;
BEGIN
    SELECT STATUS_ID INTO v_cur FROM EPF_COMPANIES WHERE COMPANY_ID = p_company_id;
    IF v_cur != v_pend THEN
        RAISE_APPLICATION_ERROR(-20010,'Client is not in Pending Checker status.');
    END IF;

    UPDATE EPF_COMPANIES        SET STATUS_ID=v_active,UPDATED_BY=p_approved_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_COMPANY_SETTINGS SET STATUS_ID=v_active,UPDATED_BY=p_approved_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID=v_active, CHECKER_ID=p_approved_by, CHECKED_DATE=SYSDATE,
        CHECKER_REMARKS=p_remarks, UPDATED_BY=p_approved_by, UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id;

    UPDATE EPF_USER_COMPANIES SET
        STATUS_ID=GET_SID('USER_STATUS','ACTIVE'),UPDATED_BY=p_approved_by,UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id
    AND   EPF_STATUS_PKG.GET_CODE(STATUS_ID) IN ('PENDING','PENDING_CHECKER');

    UPDATE EPF_USERS SET
        STATUS_ID=GET_SID('USER_STATUS','ACTIVE'),UPDATED_BY=p_approved_by,UPDATED_DATE=SYSDATE
    WHERE USER_ID IN (
        SELECT USER_ID FROM EPF_USER_COMPANIES WHERE COMPANY_ID=p_company_id
    ) AND EPF_STATUS_PKG.GET_CODE(STATUS_ID)='PENDING';

    UPDATE EPF_FOLIOS SET STATUS_ID=v_active,UPDATED_BY=p_approved_by,UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id;

    COMMIT;

    -- Welcome emails
    FOR r IN (SELECT u.EMAIL, u.FULL_NAME FROM EPF_USERS u
              JOIN EPF_USER_COMPANIES uc ON uc.USER_ID=u.USER_ID
              WHERE uc.COMPANY_ID=p_company_id AND u.FORCE_PWD_CHANGE='Y')
    LOOP
        APEX_MAIL.SEND(
            p_to   => r.EMAIL,
            p_from => 'noreply@epfportal.com',
            p_subj => 'Welcome to EPF Portal – Your Account is Active',
            p_body => 'Dear '||r.FULL_NAME||','||CHR(10)||CHR(10)||
                      'Your EPF Portal account has been activated.'||CHR(10)||
                      'Temporary password: EPF@2024!'||CHR(10)||
                      'Please log in immediately and change your password.'
        );
    END LOOP;
    APEX_MAIL.PUSH_QUEUE;

    LOG_ACTIVITY('CLIENT',p_company_id,'CHECKER_APPROVED',p_remarks,p_approved_by);
END CHECKER_APPROVE;

-- ══════════════════════════════════════════════════════════════
--  CHECKER_REJECT  (hard reject – marks REJECTED, no re-submit)
-- ══════════════════════════════════════════════════════════════
PROCEDURE CHECKER_REJECT (p_company_id IN NUMBER, p_remarks IN VARCHAR2, p_rejected_by IN NUMBER) IS
    v_rej   NUMBER := GET_SID('CLIENT_STATUS','REJECTED');
    v_pend  NUMBER := GET_SID('CLIENT_STATUS','PENDING_CHECKER');
    v_cur   NUMBER;
BEGIN
    IF p_remarks IS NULL THEN
        RAISE_APPLICATION_ERROR(-20020,'Rejection remarks are required.');
    END IF;
    SELECT STATUS_ID INTO v_cur FROM EPF_COMPANIES WHERE COMPANY_ID=p_company_id;
    IF v_cur != v_pend THEN
        RAISE_APPLICATION_ERROR(-20021,'Client is not in Pending Checker status.');
    END IF;

    UPDATE EPF_COMPANIES        SET STATUS_ID=v_rej,UPDATED_BY=p_rejected_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_COMPANY_SETTINGS SET STATUS_ID=v_rej,UPDATED_BY=p_rejected_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID=v_rej, CHECKER_ID=p_rejected_by, CHECKED_DATE=SYSDATE,
        CHECKER_REMARKS=p_remarks, UPDATED_BY=p_rejected_by, UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id;

    COMMIT;
    LOG_ACTIVITY('CLIENT',p_company_id,'CHECKER_REJECTED',p_remarks,p_rejected_by);
END CHECKER_REJECT;

-- ══════════════════════════════════════════════════════════════
--  CHECKER_REVERT  (send back to Maker for corrections)
-- ══════════════════════════════════════════════════════════════
PROCEDURE CHECKER_REVERT (p_company_id IN NUMBER, p_remarks IN VARCHAR2, p_reverted_by IN NUMBER) IS
    v_draft NUMBER := GET_SID('CLIENT_STATUS','DRAFT');
    v_pend  NUMBER := GET_SID('CLIENT_STATUS','PENDING_CHECKER');
    v_cur   NUMBER;
BEGIN
    IF p_remarks IS NULL OR TRIM(p_remarks) IS NULL THEN
        RAISE_APPLICATION_ERROR(-20030,'Revert remarks are required.');
    END IF;
    SELECT STATUS_ID INTO v_cur FROM EPF_COMPANIES WHERE COMPANY_ID=p_company_id;
    IF v_cur != v_pend THEN
        RAISE_APPLICATION_ERROR(-20031,'Client is not in Pending Checker status.');
    END IF;

    UPDATE EPF_COMPANIES        SET STATUS_ID=v_draft,UPDATED_BY=p_reverted_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_COMPANY_SETTINGS SET STATUS_ID=v_draft,UPDATED_BY=p_reverted_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID=v_draft, CHECKER_ID=p_reverted_by, CHECKED_DATE=SYSDATE,
        CHECKER_REMARKS=p_remarks, UPDATED_BY=p_reverted_by, UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id;

    UPDATE EPF_USER_COMPANIES SET
        STATUS_ID=GET_SID('USER_STATUS','PENDING'),UPDATED_BY=p_reverted_by,UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id
    AND   EPF_STATUS_PKG.GET_CODE(STATUS_ID)='PENDING_CHECKER';

    COMMIT;
    LOG_ACTIVITY('CLIENT',p_company_id,'CHECKER_REVERTED',p_remarks,p_reverted_by);
END CHECKER_REVERT;

-- ══════════════════════════════════════════════════════════════
--  INIT_ONBOARDING
-- ══════════════════════════════════════════════════════════════
PROCEDURE INIT_ONBOARDING (p_company_id IN NUMBER, p_user_id IN NUMBER,
                            p_out_submission_id OUT NUMBER, p_out_ref_no OUT VARCHAR2) IS
    v_draft NUMBER := GET_SID('CLIENT_STATUS','DRAFT');
BEGIN
    BEGIN
        SELECT SUBMISSION_ID, SUBMISSION_REF_NO
        INTO   p_out_submission_id, p_out_ref_no
        FROM   EPF_ONBOARDING_SUBMISSIONS WHERE COMPANY_ID=p_company_id;
        RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
    p_out_ref_no := GEN_REF_NO('ONB');
    INSERT INTO EPF_ONBOARDING_SUBMISSIONS
        (COMPANY_ID,SUBMISSION_REF_NO,STATUS_ID,CREATED_BY,CREATED_DATE)
    VALUES (p_company_id,p_out_ref_no,v_draft,p_user_id,SYSDATE)
    RETURNING SUBMISSION_ID INTO p_out_submission_id;
    COMMIT;
END INIT_ONBOARDING;

-- ══════════════════════════════════════════════════════════════
--  SAVE_COMPANY_USER
-- ══════════════════════════════════════════════════════════════
PROCEDURE SAVE_COMPANY_USER (
    p_company_id      IN NUMBER, p_user_company_id IN NUMBER,
    p_folio_id        IN NUMBER, p_role_id         IN NUMBER,
    p_full_name       IN VARCHAR2, p_email         IN VARCHAR2,
    p_cnic            IN VARCHAR2, p_mobile_no      IN VARCHAR2,
    p_employee_code   IN VARCHAR2, p_performed_by   IN NUMBER,
    p_out_user_id     OUT NUMBER,
    p_out_success     OUT VARCHAR2, p_out_message   OUT VARCHAR2
) IS
    v_err       VARCHAR2(500);
    v_user_id   NUMBER;
    v_uc_id     NUMBER;
    v_cnt       NUMBER;
    v_salt      RAW(32);
    v_hash      RAW(64);
    v_pend      NUMBER := GET_SID('USER_STATUS','PENDING');
BEGIN
    v_err := VALIDATE_EMAIL(p_email);    IF v_err IS NOT NULL THEN p_out_success:='N';p_out_message:=v_err;RETURN;END IF;
    v_err := VALIDATE_CNIC(p_cnic);     IF v_err IS NOT NULL THEN p_out_success:='N';p_out_message:=v_err;RETURN;END IF;
    v_err := VALIDATE_MOBILE(p_mobile_no); IF v_err IS NOT NULL THEN p_out_success:='N';p_out_message:=v_err;RETURN;END IF;
    IF p_full_name IS NULL THEN p_out_success:='N';p_out_message:='Full name is required.';RETURN;END IF;

    -- Duplicate email in this company
    SELECT COUNT(*) INTO v_cnt
    FROM   EPF_USER_COMPANIES uc JOIN EPF_USERS u ON u.USER_ID=uc.USER_ID
    WHERE  uc.COMPANY_ID=p_company_id AND LOWER(u.EMAIL)=LOWER(p_email)
    AND    EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID)!='DELETED'
    AND    (p_user_company_id IS NULL OR uc.USER_COMPANY_ID!=p_user_company_id);
    IF v_cnt>0 THEN p_out_success:='N';p_out_message:='This email is already registered for this company.';RETURN;END IF;

    -- Find or create user
    BEGIN
        SELECT USER_ID INTO v_user_id FROM EPF_USERS
        WHERE LOWER(EMAIL)=LOWER(p_email) AND ROWNUM=1;
        UPDATE EPF_USERS SET
            FULL_NAME=NVL2(FULL_NAME,FULL_NAME,p_full_name),
            CNIC=NVL2(CNIC,CNIC,p_cnic), MOBILE_NO=NVL2(MOBILE_NO,MOBILE_NO,p_mobile_no),
            EMPLOYEE_CODE=NVL2(EMPLOYEE_CODE,EMPLOYEE_CODE,p_employee_code),
            UPDATED_BY=p_performed_by,UPDATED_DATE=SYSDATE
        WHERE USER_ID=v_user_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_salt := UC_CRYPTO.RANDOMBYTES(32);
        v_hash := UC_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW('EPF@2024!')||v_salt, UC_CRYPTO.HASH_SH512);
        INSERT INTO EPF_USERS (FULL_NAME,EMAIL,CNIC,MOBILE_NO,EMPLOYEE_CODE,
            PASSWORD_HASH,PASSWORD_SALT,STATUS_ID,FORCE_PWD_CHANGE,CREATED_BY,CREATED_DATE)
        VALUES (p_full_name,LOWER(p_email),p_cnic,p_mobile_no,p_employee_code,
            RAWTOHEX(v_hash),RAWTOHEX(v_salt),v_pend,'Y',p_performed_by,SYSDATE)
        RETURNING USER_ID INTO v_user_id;
    END;

    -- UPSERT user_companies → get USER_COMPANY_ID
    MERGE INTO EPF_USER_COMPANIES uc
    USING (SELECT v_user_id AS UID, p_company_id AS CID FROM DUAL) d
    ON (uc.USER_ID=d.UID AND uc.COMPANY_ID=d.CID)
    WHEN MATCHED THEN UPDATE SET FOLIO_ID=NVL(p_folio_id,uc.FOLIO_ID),UPDATED_BY=p_performed_by,UPDATED_DATE=SYSDATE
    WHEN NOT MATCHED THEN INSERT (USER_ID,COMPANY_ID,FOLIO_ID,STATUS_ID,CREATED_BY,CREATED_DATE)
    VALUES (v_user_id,p_company_id,p_folio_id,v_pend,p_performed_by,SYSDATE);

    SELECT USER_COMPANY_ID INTO v_uc_id FROM EPF_USER_COMPANIES
    WHERE USER_ID=v_user_id AND COMPANY_ID=p_company_id;

    -- UPSERT role via USER_COMPANY_ID
    SELECT COUNT(*) INTO v_cnt FROM EPF_USER_COMP_ROLES
    WHERE USER_COMPANY_ID=v_uc_id AND ROLE_ID=p_role_id;
    IF v_cnt=0 THEN
        INSERT INTO EPF_USER_COMP_ROLES (USER_COMPANY_ID,ROLE_ID,IS_ACTIVE,CREATED_BY,CREATED_DATE)
        VALUES (v_uc_id,p_role_id,'Y',p_performed_by,SYSDATE);
    ELSE
        UPDATE EPF_USER_COMP_ROLES SET IS_ACTIVE='Y',UPDATED_BY=p_performed_by,UPDATED_DATE=SYSDATE
        WHERE USER_COMPANY_ID=v_uc_id AND ROLE_ID=p_role_id;
    END IF;

    -- Mark Tab2 complete
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET TAB2_COMPLETE='Y',UPDATED_BY=p_performed_by,UPDATED_DATE=SYSDATE
    WHERE COMPANY_ID=p_company_id;

    COMMIT;
    p_out_user_id:=v_user_id; p_out_success:='Y'; p_out_message:='User saved successfully.';
EXCEPTION WHEN OTHERS THEN ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END SAVE_COMPANY_USER;

-- ══════════════════════════════════════════════════════════════
--  SAVE_AUTHORIZER_GROUP
-- ══════════════════════════════════════════════════════════════
PROCEDURE SAVE_AUTHORIZER_GROUP (
    p_group_id IN NUMBER, p_company_id IN NUMBER,
    p_group_name IN VARCHAR2, p_min_approvals IN NUMBER,
    p_member_user_ids IN VARCHAR2, p_performed_by IN NUMBER,
    p_out_group_id OUT NUMBER, p_out_success OUT VARCHAR2, p_out_message OUT VARCHAR2
) IS
    v_cnt      NUMBER;
    v_mem_cnt  NUMBER := 0;
    v_gid      NUMBER := p_group_id;
BEGIN
    IF p_group_name IS NULL THEN p_out_success:='N';p_out_message:='Group name is required.';RETURN;END IF;
    IF NVL(p_min_approvals,0)<1 THEN p_out_success:='N';p_out_message:='Minimum approvals must be >= 1.';RETURN;END IF;
    FOR r IN (SELECT TRIM(COLUMN_VALUE) AS UID FROM TABLE(APEX_STRING.SPLIT(p_member_user_ids,':')) WHERE TRIM(COLUMN_VALUE) IS NOT NULL)
    LOOP v_mem_cnt:=v_mem_cnt+1; END LOOP;
    IF v_mem_cnt=0 THEN p_out_success:='N';p_out_message:='At least one member required.';RETURN;END IF;
    IF p_min_approvals>v_mem_cnt THEN p_out_success:='N';p_out_message:='Min approvals ('||p_min_approvals||') > members ('||v_mem_cnt||').';RETURN;END IF;
    SELECT COUNT(*) INTO v_cnt FROM EPF_AUTHORIZER_GROUPS
    WHERE COMPANY_ID=p_company_id AND UPPER(GROUP_NAME)=UPPER(p_group_name)
    AND (v_gid IS NULL OR GROUP_ID!=v_gid);
    IF v_cnt>0 THEN p_out_success:='N';p_out_message:='Group name already exists.';RETURN;END IF;
    IF v_gid IS NULL THEN
        INSERT INTO EPF_AUTHORIZER_GROUPS (COMPANY_ID,GROUP_NAME,MIN_APPROVALS,CREATED_BY,CREATED_DATE)
        VALUES (p_company_id,p_group_name,p_min_approvals,p_performed_by,SYSDATE)
        RETURNING GROUP_ID INTO v_gid;
    ELSE
        UPDATE EPF_AUTHORIZER_GROUPS SET GROUP_NAME=p_group_name,MIN_APPROVALS=p_min_approvals,
            UPDATED_BY=p_performed_by,UPDATED_DATE=SYSDATE WHERE GROUP_ID=v_gid;
    END IF;
    DELETE FROM EPF_AUTHORIZER_GROUP_MEMBERS WHERE GROUP_ID=v_gid;
    FOR r IN (SELECT TRIM(COLUMN_VALUE) AS UID FROM TABLE(APEX_STRING.SPLIT(p_member_user_ids,':')) WHERE TRIM(COLUMN_VALUE) IS NOT NULL)
    LOOP
        INSERT INTO EPF_AUTHORIZER_GROUP_MEMBERS (GROUP_ID,USER_ID,CREATED_BY,CREATED_DATE)
        VALUES (v_gid,TO_NUMBER(r.UID),p_performed_by,SYSDATE);
    END LOOP;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET TAB3_COMPLETE='Y',UPDATED_BY=p_performed_by,UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    COMMIT;
    p_out_group_id:=v_gid; p_out_success:='Y'; p_out_message:='Group saved.';
EXCEPTION WHEN OTHERS THEN ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END SAVE_AUTHORIZER_GROUP;

-- ══════════════════════════════════════════════════════════════
--  BEGIN_CHANGE_REQUEST / SAVE_CR_SECTION / SUBMIT_CR_TO_CHECKER
--  / CR_CHECKER_APPROVE / CR_CHECKER_REVERT
--  (identical to 03_epf_aaml_pkg_body.sql – replicated here
--   but using GET_SID() and EPF_STATUS_PKG.GET_CODE())
-- ══════════════════════════════════════════════════════════════
PROCEDURE BEGIN_CHANGE_REQUEST (p_company_id IN NUMBER, p_user_id IN NUMBER,
    p_out_change_req_id OUT NUMBER, p_out_ref_no OUT VARCHAR2) IS
    v_draft  NUMBER := GET_SID('CHANGE_REQ_STATUS','DRAFT');
    v_pend   NUMBER := GET_SID('CHANGE_REQ_STATUS','PENDING_CHECKER');
    v_rev    NUMBER := GET_SID('CHANGE_REQ_STATUS','REVERTED');
    v_sc     VARCHAR2(30);
BEGIN
    SELECT EPF_STATUS_PKG.GET_CODE(c.STATUS_ID) INTO v_sc FROM EPF_COMPANIES c WHERE c.COMPANY_ID=p_company_id;
    IF v_sc != 'ACTIVE' THEN RAISE_APPLICATION_ERROR(-20040,'Change requests only allowed for ACTIVE clients.'); END IF;
    BEGIN
        SELECT CHANGE_REQ_ID,CHANGE_REQ_REF_NO INTO p_out_change_req_id,p_out_ref_no
        FROM EPF_CLIENT_CHANGE_REQUESTS WHERE COMPANY_ID=p_company_id AND STATUS_ID IN (v_draft,v_pend,v_rev) AND ROWNUM=1;
        RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
    p_out_ref_no := GEN_REF_NO('CRQ');
    INSERT INTO EPF_CLIENT_CHANGE_REQUESTS (COMPANY_ID,CHANGE_REQ_REF_NO,STATUS_ID,CREATED_BY,CREATED_DATE)
    VALUES (p_company_id,p_out_ref_no,v_draft,p_user_id,SYSDATE)
    RETURNING CHANGE_REQ_ID INTO p_out_change_req_id;
    COMMIT;
END BEGIN_CHANGE_REQUEST;

PROCEDURE SAVE_CR_SECTION (p_change_req_id IN NUMBER, p_section_code IN VARCHAR2,
    p_new_values_json IN CLOB, p_change_summary IN VARCHAR2, p_user_id IN NUMBER) IS
    v_company_id NUMBER;
    v_old_json   CLOB;
    v_label      VARCHAR2(100);
    v_order      NUMBER;
BEGIN
    SELECT COMPANY_ID INTO v_company_id FROM EPF_CLIENT_CHANGE_REQUESTS WHERE CHANGE_REQ_ID=p_change_req_id;
    CASE p_section_code
    WHEN 'ACCOUNT' THEN
        v_label:='Account Details'; v_order:=1;
        SELECT JSON_OBJECT('company_name' VALUE COMPANY_NAME,'company_code' VALUE COMPANY_CODE,
            'ntn' VALUE NTN,'address' VALUE ADDRESS,'city' VALUE CITY,
            'contact_email' VALUE CONTACT_EMAIL,'contact_phone' VALUE CONTACT_PHONE)
        INTO v_old_json FROM EPF_COMPANIES WHERE COMPANY_ID=v_company_id;
    WHEN 'SETTINGS' THEN
        v_label:='Fund & Contribution Settings'; v_order:=2;
        SELECT JSON_OBJECT('contribution_pct' VALUE CONTRIBUTION_PCT,'employer_pct' VALUE EMPLOYER_PCT,
            'vesting_months' VALUE VESTING_MONTHS,'min_contribution' VALUE MIN_CONTRIBUTION,
            'max_contribution' VALUE MAX_CONTRIBUTION)
        INTO v_old_json FROM EPF_COMPANY_SETTINGS WHERE COMPANY_ID=v_company_id;
    ELSE v_label:=p_section_code; v_order:=9; v_old_json:=NULL;
    END CASE;
    MERGE INTO EPF_CR_SECTION_CHANGES sc
    USING (SELECT p_change_req_id AS CID, p_section_code AS SC FROM DUAL) s
    ON (sc.CHANGE_REQ_ID=s.CID AND sc.SECTION_CODE=s.SC)
    WHEN MATCHED THEN UPDATE SET OLD_VALUES_JSON=v_old_json,NEW_VALUES_JSON=p_new_values_json,CHANGE_SUMMARY=p_change_summary,SECTION_LABEL=v_label
    WHEN NOT MATCHED THEN INSERT (CHANGE_REQ_ID,SECTION_CODE,SECTION_LABEL,OLD_VALUES_JSON,NEW_VALUES_JSON,CHANGE_SUMMARY,DISPLAY_ORDER,CREATED_BY,CREATED_DATE)
    VALUES (p_change_req_id,p_section_code,v_label,v_old_json,p_new_values_json,p_change_summary,v_order,p_user_id,SYSDATE);
    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET UPDATED_BY=p_user_id,UPDATED_DATE=SYSDATE WHERE CHANGE_REQ_ID=p_change_req_id;
    COMMIT;
END SAVE_CR_SECTION;

PROCEDURE SUBMIT_CR_TO_CHECKER (p_change_req_id IN NUMBER, p_user_id IN NUMBER,
    p_out_success OUT VARCHAR2, p_out_message OUT VARCHAR2) IS
    v_cnt  NUMBER;
    v_pend NUMBER := GET_SID('CHANGE_REQ_STATUS','PENDING_CHECKER');
BEGIN
    SELECT COUNT(*) INTO v_cnt FROM EPF_CR_SECTION_CHANGES WHERE CHANGE_REQ_ID=p_change_req_id;
    IF v_cnt=0 THEN p_out_success:='N';p_out_message:='No section changes recorded.';RETURN;END IF;
    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET STATUS_ID=v_pend,MAKER_RESUBMIT_DATE=SYSDATE,UPDATED_BY=p_user_id,UPDATED_DATE=SYSDATE WHERE CHANGE_REQ_ID=p_change_req_id;
    COMMIT; LOG_ACTIVITY('CR',p_change_req_id,'CR_SUBMITTED',NULL,p_user_id);
    p_out_success:='Y';p_out_message:='Change request submitted.';
EXCEPTION WHEN OTHERS THEN ROLLBACK;p_out_success:='N';p_out_message:=SQLERRM;
END SUBMIT_CR_TO_CHECKER;

PROCEDURE CR_CHECKER_APPROVE (p_change_req_id IN NUMBER, p_checker_id IN NUMBER,
    p_remarks IN VARCHAR2, p_out_success OUT VARCHAR2, p_out_message OUT VARCHAR2) IS
    v_approved NUMBER := GET_SID('CHANGE_REQ_STATUS','APPROVED');
    v_pend     NUMBER := GET_SID('CHANGE_REQ_STATUS','PENDING_CHECKER');
    v_cur      NUMBER; v_comp_id NUMBER;
BEGIN
    SELECT STATUS_ID,COMPANY_ID INTO v_cur,v_comp_id FROM EPF_CLIENT_CHANGE_REQUESTS WHERE CHANGE_REQ_ID=p_change_req_id;
    IF v_cur!=v_pend THEN p_out_success:='N';p_out_message:='CR not in Pending Checker status.';RETURN;END IF;
    FOR r IN (SELECT SECTION_CODE,NEW_VALUES_JSON FROM EPF_CR_SECTION_CHANGES WHERE CHANGE_REQ_ID=p_change_req_id) LOOP
        IF r.SECTION_CODE='ACCOUNT' THEN
            UPDATE EPF_COMPANIES SET
                COMPANY_NAME=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.company_name'),COMPANY_NAME),
                COMPANY_CODE=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.company_code'),COMPANY_CODE),
                NTN=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.ntn'),NTN),
                ADDRESS=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.address'),ADDRESS),
                CITY=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.city'),CITY),
                CONTACT_EMAIL=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.contact_email'),CONTACT_EMAIL),
                CONTACT_PHONE=NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.contact_phone'),CONTACT_PHONE),
                UPDATED_BY=p_checker_id,UPDATED_DATE=SYSDATE
            WHERE COMPANY_ID=v_comp_id;
        ELSIF r.SECTION_CODE='SETTINGS' THEN
            UPDATE EPF_COMPANY_SETTINGS SET
                CONTRIBUTION_PCT=NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.contribution_pct')),CONTRIBUTION_PCT),
                EMPLOYER_PCT=NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.employer_pct')),EMPLOYER_PCT),
                VESTING_MONTHS=NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.vesting_months')),VESTING_MONTHS),
                MIN_CONTRIBUTION=NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.min_contribution')),MIN_CONTRIBUTION),
                MAX_CONTRIBUTION=NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.max_contribution')),MAX_CONTRIBUTION),
                UPDATED_BY=p_checker_id,UPDATED_DATE=SYSDATE
            WHERE COMPANY_ID=v_comp_id;
        END IF;
    END LOOP;
    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET STATUS_ID=v_approved,CHECKER_ID=p_checker_id,CHECKED_DATE=SYSDATE,
        CHECKER_REMARKS=p_remarks,AAML_APPLIED_DATE=SYSDATE,UPDATED_BY=p_checker_id,UPDATED_DATE=SYSDATE
    WHERE CHANGE_REQ_ID=p_change_req_id;
    COMMIT; LOG_ACTIVITY('CR',p_change_req_id,'CR_APPROVED',p_remarks,p_checker_id);
    p_out_success:='Y';p_out_message:='CR approved and applied.';
EXCEPTION WHEN OTHERS THEN ROLLBACK;p_out_success:='N';p_out_message:=SQLERRM;
END CR_CHECKER_APPROVE;

PROCEDURE CR_CHECKER_REVERT (p_change_req_id IN NUMBER, p_checker_id IN NUMBER,
    p_revert_remarks IN VARCHAR2, p_out_success OUT VARCHAR2, p_out_message OUT VARCHAR2) IS
    v_rev  NUMBER := GET_SID('CHANGE_REQ_STATUS','REVERTED');
    v_pend NUMBER := GET_SID('CHANGE_REQ_STATUS','PENDING_CHECKER');
    v_cur  NUMBER;
BEGIN
    IF p_revert_remarks IS NULL OR TRIM(p_revert_remarks) IS NULL THEN p_out_success:='N';p_out_message:='Revert remarks required.';RETURN;END IF;
    SELECT STATUS_ID INTO v_cur FROM EPF_CLIENT_CHANGE_REQUESTS WHERE CHANGE_REQ_ID=p_change_req_id;
    IF v_cur!=v_pend THEN p_out_success:='N';p_out_message:='CR not in Pending Checker status.';RETURN;END IF;
    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET STATUS_ID=v_rev,REVERTED_DATE=SYSDATE,REVERTED_BY=p_checker_id,
        REVERT_REMARKS=p_revert_remarks,UPDATED_BY=p_checker_id,UPDATED_DATE=SYSDATE
    WHERE CHANGE_REQ_ID=p_change_req_id;
    COMMIT; LOG_ACTIVITY('CR',p_change_req_id,'CR_REVERTED',p_revert_remarks,p_checker_id);
    p_out_success:='Y';p_out_message:='CR reverted to Maker.';
EXCEPTION WHEN OTHERS THEN ROLLBACK;p_out_success:='N';p_out_message:=SQLERRM;
END CR_CHECKER_REVERT;

END EPF_AAML_PKG;
/
