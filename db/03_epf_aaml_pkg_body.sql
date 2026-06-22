CREATE OR REPLACE PACKAGE BODY EPF_AAML_PKG AS

-- ============================================================
--  Private helpers
-- ============================================================

FUNCTION GEN_REF_NO (p_prefix IN VARCHAR2) RETURN VARCHAR2 IS
    v_seq  NUMBER;
    v_ym   VARCHAR2(6) := TO_CHAR(SYSDATE,'YYYYMM');
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

FUNCTION GET_STATUS_ID (p_category_code IN VARCHAR2,
                        p_status_code   IN VARCHAR2) RETURN NUMBER IS
    v_id NUMBER;
BEGIN
    SELECT STATUS_ID INTO v_id
    FROM   EPF_STATUSES
    WHERE  CATEGORY_CODE = p_category_code
    AND    STATUS_CODE   = p_status_code
    AND    ROWNUM        = 1;
    RETURN v_id;
EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
END GET_STATUS_ID;

PROCEDURE LOG_ACTIVITY (p_entity_type IN VARCHAR2,
                         p_entity_id   IN NUMBER,
                         p_action_code IN VARCHAR2,
                         p_remarks     IN VARCHAR2,
                         p_user_id     IN NUMBER) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO EPF_ACTIVITY_LOG
        (ENTITY_TYPE, ENTITY_ID, ACTION_CODE, REMARKS, PERFORMED_BY, PERFORMED_DATE)
    VALUES
        (p_entity_type, p_entity_id, p_action_code, p_remarks, p_user_id, SYSDATE);
    COMMIT;
END LOG_ACTIVITY;

FUNCTION VALIDATE_EMAIL (p_email IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
    IF p_email IS NULL THEN RETURN 'Email is required.'; END IF;
    IF NOT REGEXP_LIKE(p_email,'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')
    THEN RETURN 'Invalid email format: '||p_email; END IF;
    RETURN NULL;
END VALIDATE_EMAIL;

FUNCTION VALIDATE_CNIC (p_cnic IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
    IF p_cnic IS NULL THEN RETURN NULL; END IF;  -- optional field
    IF NOT REGEXP_LIKE(p_cnic,'^\d{13}$') AND
       NOT REGEXP_LIKE(p_cnic,'^\d{5}-\d{7}-\d{1}$')
    THEN RETURN 'CNIC must be 13 digits (with or without dashes).'; END IF;
    RETURN NULL;
END VALIDATE_CNIC;

FUNCTION VALIDATE_MOBILE (p_mobile IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
    IF p_mobile IS NULL THEN RETURN NULL; END IF;
    IF NOT REGEXP_LIKE(p_mobile,'^(\+92|0)?3[0-9]{9}$')
    THEN RETURN 'Mobile must be a valid Pakistani number (03XXXXXXXXX).'; END IF;
    RETURN NULL;
END VALIDATE_MOBILE;

-- ============================================================
--  INIT_ONBOARDING
-- ============================================================
PROCEDURE INIT_ONBOARDING (
    p_company_id        IN  NUMBER,
    p_user_id           IN  NUMBER,
    p_out_submission_id OUT NUMBER,
    p_out_ref_no        OUT VARCHAR2
) IS
    v_status_id NUMBER := GET_STATUS_ID('CLIENT_STATUS','DRAFT');
BEGIN
    -- Return existing if already started
    BEGIN
        SELECT SUBMISSION_ID, SUBMISSION_REF_NO
        INTO   p_out_submission_id, p_out_ref_no
        FROM   EPF_ONBOARDING_SUBMISSIONS
        WHERE  COMPANY_ID = p_company_id;
        RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;

    p_out_ref_no := GEN_REF_NO('ONB');

    INSERT INTO EPF_ONBOARDING_SUBMISSIONS
        (COMPANY_ID, SUBMISSION_REF_NO, STATUS_ID, CREATED_BY, CREATED_DATE)
    VALUES
        (p_company_id, p_out_ref_no, v_status_id, p_user_id, SYSDATE)
    RETURNING SUBMISSION_ID INTO p_out_submission_id;

    COMMIT;
END INIT_ONBOARDING;

-- ============================================================
--  SAVE_TAB1_ACCOUNT
-- ============================================================
PROCEDURE SAVE_TAB1_ACCOUNT (
    p_company_id         IN  NUMBER,
    p_company_name       IN  VARCHAR2,
    p_company_code       IN  VARCHAR2,
    p_ntn                IN  VARCHAR2,
    p_address            IN  VARCHAR2,
    p_city               IN  VARCHAR2,
    p_contact_email      IN  VARCHAR2,
    p_contact_phone      IN  VARCHAR2,
    p_group_id           IN  NUMBER,
    p_group_name_new     IN  VARCHAR2,
    p_fund_ids           IN  VARCHAR2,
    p_contribution_pct   IN  NUMBER,
    p_employer_pct       IN  NUMBER,
    p_vesting_months     IN  NUMBER,
    p_min_contrib        IN  NUMBER,
    p_max_contrib        IN  NUMBER,
    p_performed_by       IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_err      VARCHAR2(500) := VALIDATE_EMAIL(p_contact_email);
    v_group_id NUMBER := p_group_id;
    v_status   NUMBER := GET_STATUS_ID('CLIENT_STATUS','DRAFT');
BEGIN
    IF v_err IS NOT NULL THEN
        p_out_success := 'N'; p_out_message := v_err; RETURN;
    END IF;
    IF p_company_name IS NULL THEN
        p_out_success := 'N'; p_out_message := 'Company name is required.'; RETURN;
    END IF;

    -- Inline group creation
    IF v_group_id IS NULL AND p_group_name_new IS NOT NULL THEN
        INSERT INTO EPF_COMPANY_GROUPS (GROUP_NAME, CREATED_BY, CREATED_DATE)
        VALUES (p_group_name_new, p_performed_by, SYSDATE)
        RETURNING GROUP_ID INTO v_group_id;
    END IF;

    -- UPSERT EPF_COMPANIES
    MERGE INTO EPF_COMPANIES c
    USING (SELECT p_company_id AS CID FROM DUAL) s
    ON    (c.COMPANY_ID = s.CID)
    WHEN MATCHED THEN UPDATE SET
        COMPANY_NAME   = p_company_name,
        COMPANY_CODE   = p_company_code,
        NTN            = p_ntn,
        ADDRESS        = p_address,
        CITY           = p_city,
        CONTACT_EMAIL  = p_contact_email,
        CONTACT_PHONE  = p_contact_phone,
        GROUP_ID       = v_group_id,
        UPDATED_BY     = p_performed_by,
        UPDATED_DATE   = SYSDATE
    WHEN NOT MATCHED THEN INSERT
        (COMPANY_ID,COMPANY_NAME,COMPANY_CODE,NTN,ADDRESS,CITY,
         CONTACT_EMAIL,CONTACT_PHONE,GROUP_ID,STATUS_ID,CREATED_BY,CREATED_DATE)
    VALUES
        (p_company_id,p_company_name,p_company_code,p_ntn,p_address,p_city,
         p_contact_email,p_contact_phone,v_group_id,v_status,p_performed_by,SYSDATE);

    -- UPSERT EPF_COMPANY_SETTINGS
    MERGE INTO EPF_COMPANY_SETTINGS cs
    USING (SELECT p_company_id AS CID FROM DUAL) s
    ON    (cs.COMPANY_ID = s.CID)
    WHEN MATCHED THEN UPDATE SET
        CONTRIBUTION_PCT  = p_contribution_pct,
        EMPLOYER_PCT      = p_employer_pct,
        VESTING_MONTHS    = p_vesting_months,
        MIN_CONTRIBUTION  = p_min_contrib,
        MAX_CONTRIBUTION  = p_max_contrib,
        UPDATED_BY        = p_performed_by,
        UPDATED_DATE      = SYSDATE
    WHEN NOT MATCHED THEN INSERT
        (COMPANY_ID,CONTRIBUTION_PCT,EMPLOYER_PCT,VESTING_MONTHS,
         MIN_CONTRIBUTION,MAX_CONTRIBUTION,STATUS_ID,CREATED_BY,CREATED_DATE)
    VALUES
        (p_company_id,p_contribution_pct,p_employer_pct,p_vesting_months,
         p_min_contrib,p_max_contrib,v_status,p_performed_by,SYSDATE);

    -- Rebuild fund associations
    DELETE FROM EPF_COMPANY_FUNDS WHERE COMPANY_ID = p_company_id;
    FOR r IN (
        SELECT TRIM(COLUMN_VALUE) AS FID
        FROM   TABLE(APEX_STRING.SPLIT(p_fund_ids,':'))
        WHERE  TRIM(COLUMN_VALUE) IS NOT NULL
    ) LOOP
        INSERT INTO EPF_COMPANY_FUNDS (COMPANY_ID, FUND_ID, CREATED_BY, CREATED_DATE)
        VALUES (p_company_id, TO_NUMBER(r.FID), p_performed_by, SYSDATE);
    END LOOP;

    -- Mark Tab 1 complete
    UPDATE EPF_ONBOARDING_SUBMISSIONS
    SET    TAB1_COMPLETE = 'Y', UPDATED_BY = p_performed_by, UPDATED_DATE = SYSDATE
    WHERE  COMPANY_ID = p_company_id;

    COMMIT;
    LOG_ACTIVITY('CLIENT', p_company_id, 'TAB1_SAVED', NULL, p_performed_by);
    p_out_success := 'Y'; p_out_message := 'Account details saved.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    p_out_success := 'N'; p_out_message := SQLERRM;
END SAVE_TAB1_ACCOUNT;

-- ============================================================
--  SAVE_COMPANY_USER
-- ============================================================
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
) IS
    v_err            VARCHAR2(500);
    v_user_id        NUMBER;
    v_cnt            NUMBER;
    v_salt           RAW(32);
    v_hash           RAW(64);
    v_pwd            VARCHAR2(100) := 'EPF@2024!';
    v_status_pending NUMBER := GET_STATUS_ID('USER_STATUS','PENDING');
    v_deleted_sid    NUMBER := GET_STATUS_ID('USER_STATUS','DELETED');
BEGIN
    -- Validate
    v_err := VALIDATE_EMAIL(p_email);    IF v_err IS NOT NULL THEN p_out_success:='N'; p_out_message:=v_err; RETURN; END IF;
    v_err := VALIDATE_CNIC(p_cnic);     IF v_err IS NOT NULL THEN p_out_success:='N'; p_out_message:=v_err; RETURN; END IF;
    v_err := VALIDATE_MOBILE(p_mobile_no); IF v_err IS NOT NULL THEN p_out_success:='N'; p_out_message:=v_err; RETURN; END IF;
    IF p_full_name IS NULL THEN p_out_success:='N'; p_out_message:='Full name is required.'; RETURN; END IF;

    -- Duplicate email within same company (exclude current record on edit)
    SELECT COUNT(*) INTO v_cnt
    FROM   EPF_USER_COMPANIES uc
    JOIN   EPF_USERS u ON u.USER_ID = uc.USER_ID
    WHERE  uc.COMPANY_ID     = p_company_id
    AND    LOWER(u.EMAIL)    = LOWER(p_email)
    AND    uc.STATUS_ID     != v_deleted_sid
    AND    (p_user_company_id IS NULL OR uc.USER_COMPANY_ID != p_user_company_id);

    IF v_cnt > 0 THEN
        p_out_success:='N'; p_out_message:='This email is already registered for this company.'; RETURN;
    END IF;

    -- Lookup existing user by email (any company)
    BEGIN
        SELECT USER_ID INTO v_user_id FROM EPF_USERS
        WHERE  LOWER(EMAIL) = LOWER(p_email) AND ROWNUM = 1;
        -- Update any missing fields
        UPDATE EPF_USERS SET
            FULL_NAME       = NVL2(FULL_NAME,    FULL_NAME,    p_full_name),
            CNIC            = NVL2(CNIC,          CNIC,          p_cnic),
            MOBILE_NO       = NVL2(MOBILE_NO,     MOBILE_NO,     p_mobile_no),
            EMPLOYEE_CODE   = NVL2(EMPLOYEE_CODE, EMPLOYEE_CODE, p_employee_code),
            UPDATED_BY      = p_performed_by,
            UPDATED_DATE    = SYSDATE
        WHERE USER_ID = v_user_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        -- New user
        v_salt := UC_CRYPTO.RANDOMBYTES(32);
        v_hash := UC_CRYPTO.HASH(
                      UTL_RAW.CAST_TO_RAW(v_pwd) || v_salt,
                      UC_CRYPTO.HASH_SH512);
        INSERT INTO EPF_USERS
            (FULL_NAME, EMAIL, CNIC, MOBILE_NO, EMPLOYEE_CODE,
             PASSWORD_HASH, PASSWORD_SALT, STATUS_ID,
             FORCE_PWD_CHANGE, CREATED_BY, CREATED_DATE)
        VALUES
            (p_full_name, LOWER(p_email), p_cnic, p_mobile_no, p_employee_code,
             RAWTOHEX(v_hash), RAWTOHEX(v_salt), v_status_pending,
             'Y', p_performed_by, SYSDATE)
        RETURNING USER_ID INTO v_user_id;
    END;

    -- UPSERT EPF_USER_COMPANIES
    MERGE INTO EPF_USER_COMPANIES uc
    USING (SELECT v_user_id AS UID, p_company_id AS CID FROM DUAL) s
    ON    (uc.USER_ID = s.UID AND uc.COMPANY_ID = s.CID)
    WHEN MATCHED THEN UPDATE SET
        FOLIO_ID     = NVL(p_folio_id, uc.FOLIO_ID),
        UPDATED_BY   = p_performed_by,
        UPDATED_DATE = SYSDATE
    WHEN NOT MATCHED THEN INSERT
        (USER_ID, COMPANY_ID, FOLIO_ID, STATUS_ID, CREATED_BY, CREATED_DATE)
    VALUES
        (v_user_id, p_company_id, p_folio_id, v_status_pending, p_performed_by, SYSDATE);

    -- UPSERT role assignment via USER_COMPANY_ID
    DECLARE v_uc_id NUMBER; BEGIN
        SELECT USER_COMPANY_ID INTO v_uc_id
        FROM   EPF_USER_COMPANIES
        WHERE  USER_ID = v_user_id AND COMPANY_ID = p_company_id;

        SELECT COUNT(*) INTO v_cnt
        FROM   EPF_USER_COMP_ROLES
        WHERE  USER_COMPANY_ID = v_uc_id AND ROLE_ID = p_role_id;

        IF v_cnt = 0 THEN
            INSERT INTO EPF_USER_COMP_ROLES (USER_COMPANY_ID, ROLE_ID, IS_ACTIVE, CREATED_BY, CREATED_DATE)
            VALUES (v_uc_id, p_role_id, 'Y', p_performed_by, SYSDATE);
        ELSE
            UPDATE EPF_USER_COMP_ROLES SET IS_ACTIVE = 'Y', UPDATED_BY = p_performed_by, UPDATED_DATE = SYSDATE
            WHERE  USER_COMPANY_ID = v_uc_id AND ROLE_ID = p_role_id;
        END IF;
    END;

    -- Mark Tab 2 complete
    UPDATE EPF_ONBOARDING_SUBMISSIONS
    SET    TAB2_COMPLETE = 'Y', UPDATED_BY = p_performed_by, UPDATED_DATE = SYSDATE
    WHERE  COMPANY_ID = p_company_id;

    COMMIT;
    p_out_user_id := v_user_id;
    p_out_success := 'Y';
    p_out_message := 'User saved successfully.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    p_out_success := 'N'; p_out_message := SQLERRM;
END SAVE_COMPANY_USER;

-- ============================================================
--  SAVE_AUTHORIZER_GROUP
-- ============================================================
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
) IS
    v_cnt         NUMBER;
    v_member_cnt  NUMBER := 0;
    v_group_id    NUMBER := p_group_id;
BEGIN
    -- Validations
    IF p_group_name IS NULL THEN
        p_out_success:='N'; p_out_message:='Group name is required.'; RETURN;
    END IF;
    IF NVL(p_min_approvals,0) < 1 THEN
        p_out_success:='N'; p_out_message:='Minimum approvals must be at least 1.'; RETURN;
    END IF;

    -- Count members
    FOR r IN (SELECT TRIM(COLUMN_VALUE) AS UID FROM TABLE(APEX_STRING.SPLIT(p_member_user_ids,':'))
              WHERE TRIM(COLUMN_VALUE) IS NOT NULL)
    LOOP v_member_cnt := v_member_cnt + 1; END LOOP;

    IF v_member_cnt = 0 THEN
        p_out_success:='N'; p_out_message:='At least one group member is required.'; RETURN;
    END IF;
    IF p_min_approvals > v_member_cnt THEN
        p_out_success:='N';
        p_out_message:='Minimum approvals ('||p_min_approvals||') cannot exceed member count ('||v_member_cnt||').';
        RETURN;
    END IF;

    -- Duplicate name check within company (exclude current on edit)
    SELECT COUNT(*) INTO v_cnt
    FROM   EPF_AUTHORIZER_GROUPS
    WHERE  COMPANY_ID  = p_company_id
    AND    UPPER(GROUP_NAME) = UPPER(p_group_name)
    AND    (v_group_id IS NULL OR GROUP_ID != v_group_id);

    IF v_cnt > 0 THEN
        p_out_success:='N'; p_out_message:='A group with this name already exists for this company.'; RETURN;
    END IF;

    -- UPSERT group
    IF v_group_id IS NULL THEN
        INSERT INTO EPF_AUTHORIZER_GROUPS
            (COMPANY_ID, GROUP_NAME, MIN_APPROVALS, CREATED_BY, CREATED_DATE)
        VALUES
            (p_company_id, p_group_name, p_min_approvals, p_performed_by, SYSDATE)
        RETURNING GROUP_ID INTO v_group_id;
    ELSE
        UPDATE EPF_AUTHORIZER_GROUPS SET
            GROUP_NAME    = p_group_name,
            MIN_APPROVALS = p_min_approvals,
            UPDATED_BY    = p_performed_by,
            UPDATED_DATE  = SYSDATE
        WHERE GROUP_ID = v_group_id;
    END IF;

    -- Rebuild members
    DELETE FROM EPF_AUTHORIZER_GROUP_MEMBERS WHERE GROUP_ID = v_group_id;

    FOR r IN (SELECT TRIM(COLUMN_VALUE) AS UID FROM TABLE(APEX_STRING.SPLIT(p_member_user_ids,':'))
              WHERE TRIM(COLUMN_VALUE) IS NOT NULL)
    LOOP
        INSERT INTO EPF_AUTHORIZER_GROUP_MEMBERS (GROUP_ID, USER_ID, CREATED_BY, CREATED_DATE)
        VALUES (v_group_id, TO_NUMBER(r.UID), p_performed_by, SYSDATE);
    END LOOP;

    -- Mark Tab 3 complete
    UPDATE EPF_ONBOARDING_SUBMISSIONS
    SET    TAB3_COMPLETE = 'Y', UPDATED_BY = p_performed_by, UPDATED_DATE = SYSDATE
    WHERE  COMPANY_ID = p_company_id;

    COMMIT;
    p_out_group_id := v_group_id;
    p_out_success  := 'Y';
    p_out_message  := 'Authorizer group saved.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    p_out_success := 'N'; p_out_message := SQLERRM;
END SAVE_AUTHORIZER_GROUP;

-- ============================================================
--  SUBMIT_TO_CHECKER
-- ============================================================
PROCEDURE SUBMIT_TO_CHECKER (
    p_company_id         IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_tab1   VARCHAR2(1); v_tab2 VARCHAR2(1); v_tab4 VARCHAR2(1);
    v_admin_cnt  NUMBER; v_auth_cnt NUMBER;
    v_pend   NUMBER := GET_STATUS_ID('CLIENT_STATUS','PENDING_CHECKER');
    v_sub_id NUMBER;
BEGIN
    SELECT TAB1_COMPLETE, TAB2_COMPLETE, TAB4_COMPLETE, SUBMISSION_ID
    INTO   v_tab1, v_tab2, v_tab4, v_sub_id
    FROM   EPF_ONBOARDING_SUBMISSIONS
    WHERE  COMPANY_ID = p_company_id;

    IF NVL(v_tab1,'N') != 'Y' THEN
        p_out_success:='N'; p_out_message:='Tab 1 (Account Details) is not complete.'; RETURN;
    END IF;
    IF NVL(v_tab2,'N') != 'Y' THEN
        p_out_success:='N'; p_out_message:='Tab 2 (Users) is not complete.'; RETURN;
    END IF;
    IF NVL(v_tab4,'N') != 'Y' THEN
        p_out_success:='N'; p_out_message:='Tab 4 (Employee Data) is not complete.'; RETURN;
    END IF;

    -- Must have at least 1 Corp Admin
    SELECT COUNT(*) INTO v_admin_cnt
    FROM   EPF_USER_COMP_ROLES ucr
    JOIN   EPF_USER_COMPANIES  uc  ON uc.USER_COMPANY_ID = ucr.USER_COMPANY_ID
    WHERE  uc.COMPANY_ID = p_company_id AND ucr.ROLE_ID = 5 AND ucr.IS_ACTIVE = 'Y';
    IF v_admin_cnt = 0 THEN
        p_out_success:='N'; p_out_message:='At least one Corporate Admin (role) must be assigned.'; RETURN;
    END IF;

    -- Must have at least 1 Authorizer
    SELECT COUNT(*) INTO v_auth_cnt
    FROM   EPF_USER_COMP_ROLES ucr
    JOIN   EPF_USER_COMPANIES  uc  ON uc.USER_COMPANY_ID = ucr.USER_COMPANY_ID
    WHERE  uc.COMPANY_ID = p_company_id AND ucr.ROLE_ID = 8 AND ucr.IS_ACTIVE = 'Y';
    IF v_auth_cnt = 0 THEN
        p_out_success:='N'; p_out_message:='At least one Corporate Authorizer (role) must be assigned.'; RETURN;
    END IF;

    -- Update statuses
    UPDATE EPF_COMPANIES          SET STATUS_ID = v_pend, UPDATED_BY = p_user_id, UPDATED_DATE = SYSDATE WHERE COMPANY_ID = p_company_id;
    UPDATE EPF_COMPANY_SETTINGS   SET STATUS_ID = v_pend, UPDATED_BY = p_user_id, UPDATED_DATE = SYSDATE WHERE COMPANY_ID = p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID      = v_pend,
        SUBMITTED_BY   = p_user_id,
        SUBMITTED_DATE = SYSDATE,
        UPDATED_BY     = p_user_id,
        UPDATED_DATE   = SYSDATE
    WHERE COMPANY_ID = p_company_id;
    DECLARE v_uc_pend NUMBER := GET_STATUS_ID('USER_STATUS','PENDING'); BEGIN
    UPDATE EPF_USER_COMPANIES SET
        STATUS_ID    = v_pend,
        UPDATED_BY   = p_user_id,
        UPDATED_DATE = SYSDATE
    WHERE COMPANY_ID = p_company_id
    AND   STATUS_ID  = v_uc_pend;
    END;

    COMMIT;
    LOG_ACTIVITY('CLIENT', p_company_id, 'SUBMIT_TO_CHECKER', NULL, p_user_id);
    p_out_success := 'Y'; p_out_message := 'Successfully submitted to AAML Checker.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END SUBMIT_TO_CHECKER;

-- ============================================================
--  CHECKER_APPROVE
-- ============================================================
PROCEDURE CHECKER_APPROVE (
    p_company_id         IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_remarks            IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_active      NUMBER := GET_STATUS_ID('CLIENT_STATUS','ACTIVE');
    v_pend        NUMBER := GET_STATUS_ID('CLIENT_STATUS','PENDING_CHECKER');
    v_uc_active   NUMBER := GET_STATUS_ID('USER_STATUS','ACTIVE');
    v_uc_pend     NUMBER := GET_STATUS_ID('USER_STATUS','PENDING');
    v_cur         NUMBER;
BEGIN
    SELECT STATUS_ID INTO v_cur FROM EPF_COMPANIES WHERE COMPANY_ID = p_company_id;
    IF v_cur != v_pend THEN
        p_out_success:='N'; p_out_message:='Client is not in Pending Checker status.'; RETURN;
    END IF;

    UPDATE EPF_COMPANIES        SET STATUS_ID=v_active, UPDATED_BY=p_checker_id, UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_COMPANY_SETTINGS SET STATUS_ID=v_active, UPDATED_BY=p_checker_id, UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID     = v_active,
        CHECKER_ID    = p_checker_id,
        CHECKED_DATE  = SYSDATE,
        CHECKER_REMARKS = p_remarks,
        UPDATED_BY    = p_checker_id,
        UPDATED_DATE  = SYSDATE
    WHERE COMPANY_ID = p_company_id;

    UPDATE EPF_USER_COMPANIES SET
        STATUS_ID = v_uc_active,
        UPDATED_BY = p_checker_id, UPDATED_DATE = SYSDATE
    WHERE COMPANY_ID = p_company_id
    AND   STATUS_ID IN (v_uc_pend, v_pend);

    UPDATE EPF_USERS SET
        STATUS_ID = v_uc_active,
        UPDATED_BY = p_checker_id, UPDATED_DATE = SYSDATE
    WHERE USER_ID IN (
        SELECT USER_ID FROM EPF_USER_COMPANIES
        WHERE  COMPANY_ID = p_company_id
    )
    AND STATUS_ID = v_uc_pend;

    UPDATE EPF_FOLIOS SET
        STATUS_ID = v_active,
        UPDATED_BY = p_checker_id, UPDATED_DATE = SYSDATE
    WHERE COMPANY_ID = p_company_id;

    COMMIT;

    -- Welcome emails
    FOR r IN (
        SELECT u.EMAIL, u.FULL_NAME
        FROM   EPF_USERS u
        JOIN   EPF_USER_COMPANIES uc ON uc.USER_ID = u.USER_ID
        WHERE  uc.COMPANY_ID = p_company_id
        AND    u.FORCE_PWD_CHANGE = 'Y'
    ) LOOP
        APEX_MAIL.SEND(
            p_to      => r.EMAIL,
            p_from    => 'noreply@epfportal.com',
            p_subj    => 'Welcome to EPF Portal – Account Activated',
            p_body    => 'Dear '||r.FULL_NAME||','||CHR(10)||CHR(10)||
                         'Your EPF Portal account has been activated.'||CHR(10)||
                         'Temporary password: EPF@2024!'||CHR(10)||
                         'Please log in and change your password immediately.'
        );
    END LOOP;
    APEX_MAIL.PUSH_QUEUE;

    LOG_ACTIVITY('CLIENT', p_company_id, 'CHECKER_APPROVED', p_remarks, p_checker_id);
    p_out_success := 'Y'; p_out_message := 'Client approved and activated successfully.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END CHECKER_APPROVE;

-- ============================================================
--  CHECKER_REVERT
-- ============================================================
PROCEDURE CHECKER_REVERT (
    p_company_id         IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_revert_remarks     IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_draft     NUMBER := GET_STATUS_ID('CLIENT_STATUS','DRAFT');
    v_pend      NUMBER := GET_STATUS_ID('CLIENT_STATUS','PENDING_CHECKER');
    v_uc_pend   NUMBER := GET_STATUS_ID('USER_STATUS','PENDING');
    v_cur       NUMBER;
BEGIN
    IF p_revert_remarks IS NULL OR TRIM(p_revert_remarks) IS NULL THEN
        p_out_success:='N'; p_out_message:='Revert remarks are mandatory.'; RETURN;
    END IF;

    SELECT STATUS_ID INTO v_cur FROM EPF_COMPANIES WHERE COMPANY_ID = p_company_id;
    IF v_cur != v_pend THEN
        p_out_success:='N'; p_out_message:='Client is not in Pending Checker status.'; RETURN;
    END IF;

    UPDATE EPF_COMPANIES        SET STATUS_ID=v_draft, UPDATED_BY=p_checker_id, UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_COMPANY_SETTINGS SET STATUS_ID=v_draft, UPDATED_BY=p_checker_id, UPDATED_DATE=SYSDATE WHERE COMPANY_ID=p_company_id;
    UPDATE EPF_ONBOARDING_SUBMISSIONS SET
        STATUS_ID       = v_draft,
        CHECKER_ID      = p_checker_id,
        CHECKED_DATE    = SYSDATE,
        CHECKER_REMARKS = p_revert_remarks,
        UPDATED_BY      = p_checker_id,
        UPDATED_DATE    = SYSDATE
    WHERE COMPANY_ID = p_company_id;

    UPDATE EPF_USER_COMPANIES SET
        STATUS_ID    = v_uc_pend,
        UPDATED_BY   = p_checker_id,
        UPDATED_DATE = SYSDATE
    WHERE COMPANY_ID = p_company_id
    AND   STATUS_ID  = v_pend;

    COMMIT;
    LOG_ACTIVITY('CLIENT', p_company_id, 'CHECKER_REVERTED', p_revert_remarks, p_checker_id);
    p_out_success := 'Y'; p_out_message := 'Client reverted to Maker for corrections.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END CHECKER_REVERT;

-- ============================================================
--  BEGIN_CHANGE_REQUEST
-- ============================================================
PROCEDURE BEGIN_CHANGE_REQUEST (
    p_company_id         IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_change_req_id  OUT NUMBER,
    p_out_ref_no         OUT VARCHAR2
) IS
    v_status_code VARCHAR2(30);
    v_draft_id    NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','DRAFT');
    v_pend_id     NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','PENDING_CHECKER');
    v_revert_id   NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','REVERTED');
BEGIN
    -- Only active clients can raise a CR
    SELECT s.STATUS_CODE INTO v_status_code
    FROM   EPF_COMPANIES c
    JOIN   EPF_STATUSES  s ON s.STATUS_ID = c.STATUS_ID
    WHERE  c.COMPANY_ID = p_company_id;

    IF v_status_code != 'ACTIVE' THEN
        RAISE_APPLICATION_ERROR(-20001,'Change requests can only be raised for ACTIVE clients.');
    END IF;

    -- Return existing open CR if any
    BEGIN
        SELECT CHANGE_REQ_ID, CHANGE_REQ_REF_NO
        INTO   p_out_change_req_id, p_out_ref_no
        FROM   EPF_CLIENT_CHANGE_REQUESTS
        WHERE  COMPANY_ID = p_company_id
        AND    STATUS_ID  IN (v_draft_id, v_pend_id, v_revert_id)
        AND    ROWNUM     = 1;
        RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;

    p_out_ref_no := GEN_REF_NO('CRQ');

    INSERT INTO EPF_CLIENT_CHANGE_REQUESTS
        (COMPANY_ID, CHANGE_REQ_REF_NO, STATUS_ID, CREATED_BY, CREATED_DATE)
    VALUES
        (p_company_id, p_out_ref_no, v_draft_id, p_user_id, SYSDATE)
    RETURNING CHANGE_REQ_ID INTO p_out_change_req_id;

    COMMIT;
END BEGIN_CHANGE_REQUEST;

-- ============================================================
--  SAVE_CR_SECTION
-- ============================================================
PROCEDURE SAVE_CR_SECTION (
    p_change_req_id      IN  NUMBER,
    p_section_code       IN  VARCHAR2,
    p_new_values_json    IN  CLOB,
    p_change_summary     IN  VARCHAR2,
    p_user_id            IN  NUMBER
) IS
    v_company_id NUMBER;
    v_old_json   CLOB;
    v_label      VARCHAR2(100);
    v_order      NUMBER;
BEGIN
    SELECT COMPANY_ID INTO v_company_id
    FROM   EPF_CLIENT_CHANGE_REQUESTS
    WHERE  CHANGE_REQ_ID = p_change_req_id;

    -- Snapshot OLD values from live tables
    CASE p_section_code
    WHEN 'ACCOUNT' THEN
        v_label := 'Account Details'; v_order := 1;
        SELECT JSON_OBJECT(
            'company_name'   VALUE COMPANY_NAME,
            'company_code'   VALUE COMPANY_CODE,
            'ntn'            VALUE NTN,
            'address'        VALUE ADDRESS,
            'city'           VALUE CITY,
            'contact_email'  VALUE CONTACT_EMAIL,
            'contact_phone'  VALUE CONTACT_PHONE
        ) INTO v_old_json
        FROM EPF_COMPANIES WHERE COMPANY_ID = v_company_id;
    WHEN 'SETTINGS' THEN
        v_label := 'Fund & Contribution Settings'; v_order := 2;
        SELECT JSON_OBJECT(
            'contribution_pct'  VALUE CONTRIBUTION_PCT,
            'employer_pct'      VALUE EMPLOYER_PCT,
            'vesting_months'    VALUE VESTING_MONTHS,
            'min_contribution'  VALUE MIN_CONTRIBUTION,
            'max_contribution'  VALUE MAX_CONTRIBUTION
        ) INTO v_old_json
        FROM EPF_COMPANY_SETTINGS WHERE COMPANY_ID = v_company_id;
    ELSE
        v_label := p_section_code; v_order := 9;
        v_old_json := NULL;
    END CASE;

    -- UPSERT section change
    MERGE INTO EPF_CR_SECTION_CHANGES sc
    USING (SELECT p_change_req_id AS CID, p_section_code AS SC FROM DUAL) s
    ON    (sc.CHANGE_REQ_ID = s.CID AND sc.SECTION_CODE = s.SC)
    WHEN MATCHED THEN UPDATE SET
        OLD_VALUES_JSON = v_old_json,
        NEW_VALUES_JSON = p_new_values_json,
        CHANGE_SUMMARY  = p_change_summary,
        SECTION_LABEL   = v_label
    WHEN NOT MATCHED THEN INSERT
        (CHANGE_REQ_ID, SECTION_CODE, SECTION_LABEL,
         OLD_VALUES_JSON, NEW_VALUES_JSON, CHANGE_SUMMARY,
         DISPLAY_ORDER, CREATED_BY, CREATED_DATE)
    VALUES
        (p_change_req_id, p_section_code, v_label,
         v_old_json, p_new_values_json, p_change_summary,
         v_order, p_user_id, SYSDATE);

    -- Update CR modified date
    UPDATE EPF_CLIENT_CHANGE_REQUESTS
    SET UPDATED_BY = p_user_id, UPDATED_DATE = SYSDATE
    WHERE CHANGE_REQ_ID = p_change_req_id;

    COMMIT;
END SAVE_CR_SECTION;

-- ============================================================
--  SUBMIT_CR_TO_CHECKER
-- ============================================================
PROCEDURE SUBMIT_CR_TO_CHECKER (
    p_change_req_id      IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_cnt  NUMBER;
    v_pend NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','PENDING_CHECKER');
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM   EPF_CR_SECTION_CHANGES
    WHERE  CHANGE_REQ_ID = p_change_req_id;

    IF v_cnt = 0 THEN
        p_out_success:='N'; p_out_message:='No section changes have been recorded.'; RETURN;
    END IF;

    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET
        STATUS_ID            = v_pend,
        MAKER_RESUBMIT_DATE  = SYSDATE,
        UPDATED_BY           = p_user_id,
        UPDATED_DATE         = SYSDATE
    WHERE CHANGE_REQ_ID = p_change_req_id;

    COMMIT;
    LOG_ACTIVITY('CR', p_change_req_id, 'CR_SUBMITTED', NULL, p_user_id);
    p_out_success:='Y'; p_out_message:='Change request submitted to AAML Checker.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END SUBMIT_CR_TO_CHECKER;

-- ============================================================
--  CR_CHECKER_APPROVE
-- ============================================================
PROCEDURE CR_CHECKER_APPROVE (
    p_change_req_id      IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_remarks            IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_approved NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','APPROVED');
    v_pend     NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','PENDING_CHECKER');
    v_cur      NUMBER;
    v_comp_id  NUMBER;
BEGIN
    SELECT STATUS_ID, COMPANY_ID INTO v_cur, v_comp_id
    FROM   EPF_CLIENT_CHANGE_REQUESTS
    WHERE  CHANGE_REQ_ID = p_change_req_id;

    IF v_cur != v_pend THEN
        p_out_success:='N'; p_out_message:='Change request is not in Pending Checker status.'; RETURN;
    END IF;

    -- Apply each section's changes
    FOR r IN (SELECT SECTION_CODE, NEW_VALUES_JSON
              FROM   EPF_CR_SECTION_CHANGES
              WHERE  CHANGE_REQ_ID = p_change_req_id)
    LOOP
        IF r.SECTION_CODE = 'ACCOUNT' THEN
            UPDATE EPF_COMPANIES SET
                COMPANY_NAME  = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.company_name'),  COMPANY_NAME),
                COMPANY_CODE  = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.company_code'),  COMPANY_CODE),
                NTN           = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.ntn'),           NTN),
                ADDRESS       = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.address'),        ADDRESS),
                CITY          = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.city'),           CITY),
                CONTACT_EMAIL = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.contact_email'), CONTACT_EMAIL),
                CONTACT_PHONE = NVL(JSON_VALUE(r.NEW_VALUES_JSON,'$.contact_phone'), CONTACT_PHONE),
                UPDATED_BY    = p_checker_id,
                UPDATED_DATE  = SYSDATE
            WHERE COMPANY_ID = v_comp_id;
        ELSIF r.SECTION_CODE = 'SETTINGS' THEN
            UPDATE EPF_COMPANY_SETTINGS SET
                CONTRIBUTION_PCT = NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.contribution_pct')), CONTRIBUTION_PCT),
                EMPLOYER_PCT     = NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.employer_pct')),     EMPLOYER_PCT),
                VESTING_MONTHS   = NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.vesting_months')),   VESTING_MONTHS),
                MIN_CONTRIBUTION = NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.min_contribution')), MIN_CONTRIBUTION),
                MAX_CONTRIBUTION = NVL(TO_NUMBER(JSON_VALUE(r.NEW_VALUES_JSON,'$.max_contribution')), MAX_CONTRIBUTION),
                UPDATED_BY       = p_checker_id,
                UPDATED_DATE     = SYSDATE
            WHERE COMPANY_ID = v_comp_id;
        END IF;
    END LOOP;

    -- Close the CR
    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET
        STATUS_ID         = v_approved,
        CHECKER_ID        = p_checker_id,
        CHECKED_DATE      = SYSDATE,
        CHECKER_REMARKS   = p_remarks,
        AAML_APPLIED_DATE = SYSDATE,
        UPDATED_BY        = p_checker_id,
        UPDATED_DATE      = SYSDATE
    WHERE CHANGE_REQ_ID = p_change_req_id;

    COMMIT;
    LOG_ACTIVITY('CR', p_change_req_id, 'CR_APPROVED', p_remarks, p_checker_id);
    p_out_success:='Y'; p_out_message:='Change request approved and applied to client data.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END CR_CHECKER_APPROVE;

-- ============================================================
--  CR_CHECKER_REVERT
-- ============================================================
PROCEDURE CR_CHECKER_REVERT (
    p_change_req_id      IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_revert_remarks     IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
) IS
    v_reverted NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','REVERTED');
    v_pend     NUMBER := GET_STATUS_ID('CHANGE_REQ_STATUS','PENDING_CHECKER');
    v_cur      NUMBER;
BEGIN
    IF p_revert_remarks IS NULL OR TRIM(p_revert_remarks) IS NULL THEN
        p_out_success:='N'; p_out_message:='Revert remarks are mandatory.'; RETURN;
    END IF;

    SELECT STATUS_ID INTO v_cur FROM EPF_CLIENT_CHANGE_REQUESTS WHERE CHANGE_REQ_ID = p_change_req_id;
    IF v_cur != v_pend THEN
        p_out_success:='N'; p_out_message:='Change request is not in Pending Checker status.'; RETURN;
    END IF;

    UPDATE EPF_CLIENT_CHANGE_REQUESTS SET
        STATUS_ID      = v_reverted,
        REVERTED_DATE  = SYSDATE,
        REVERTED_BY    = p_checker_id,
        REVERT_REMARKS = p_revert_remarks,
        UPDATED_BY     = p_checker_id,
        UPDATED_DATE   = SYSDATE
    WHERE CHANGE_REQ_ID = p_change_req_id;

    COMMIT;
    LOG_ACTIVITY('CR', p_change_req_id, 'CR_REVERTED', p_revert_remarks, p_checker_id);
    p_out_success:='Y'; p_out_message:='Change request reverted to Maker for corrections.';
EXCEPTION WHEN OTHERS THEN
    ROLLBACK; p_out_success:='N'; p_out_message:=SQLERRM;
END CR_CHECKER_REVERT;

END EPF_AAML_PKG;
/
