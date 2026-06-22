-- ============================================================
-- FILE: /home/user/EPF/apex/corp_maker_checker/page_processes.sql
-- EPF PORTAL  –  Corporate Maker / Checker Module – APEX Page Processes
-- All processes are PL/SQL Anonymous Blocks to be pasted into
-- APEX Application Builder as "Execute PL/SQL Code" processes.
-- Binds: :APP_COMPANY_ID, :APP_USER_COMPANY_ID (application items).
-- FSD validations: #203–#334.
-- ============================================================

-- ============================================================
-- PAGE 40  –  Create Contribution Upload (4-step wizard)
-- Steps: Create → Review → Alerts → Finish  (FSD #213)
-- Items: P40_STEP, P40_FUND_ID, P40_CONTRIB_MONTH, P40_FILE,
--        P40_FILE_NAME, P40_INSTRUMENT, P40_BATCH_ID, P40_BATCH_NO,
--        P40_FINISH_MSG, P40_ERROR_COUNT
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P40_PARSE_UPLOAD
-- When:    On Submit
-- Condition: Request = 'UPLOAD_FILE'  (Step 1 → Step 2)
-- Parses the CSV into APEX collection CONTRIB_UPLOAD:
--   C001=CNIC, C002=FOLIO_NUMBER, C003=EMPLOYEE_NAME,
--   N001=EMPLOYEE_AMOUNT, N002=EMPLOYER_AMOUNT
-- ------------------------------------------------------------
DECLARE
    v_blob      BLOB;
    v_clob      CLOB;
    v_line      VARCHAR2(4000);
    v_pos       PLS_INTEGER := 1;
    v_nl        PLS_INTEGER;
    v_line_no   PLS_INTEGER := 0;
BEGIN
    IF :P40_FILE IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Required field',          -- FSD #216
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    SELECT BLOB_CONTENT INTO v_blob
      FROM APEX_APPLICATION_TEMP_FILES
     WHERE NAME = :P40_FILE;

    v_clob := APEX_UTIL.BLOB_TO_CLOB(v_blob);

    APEX_COLLECTION.CREATE_OR_TRUNCATE_COLLECTION('CONTRIB_UPLOAD');

    LOOP
        v_nl := INSTR(v_clob, CHR(10), v_pos);
        EXIT WHEN v_nl = 0 AND v_pos > LENGTH(v_clob);
        IF v_nl = 0 THEN
            v_line := SUBSTR(v_clob, v_pos);
            v_pos  := LENGTH(v_clob) + 1;
        ELSE
            v_line := SUBSTR(v_clob, v_pos, v_nl - v_pos);
            v_pos  := v_nl + 1;
        END IF;
        v_line := REPLACE(v_line, CHR(13));
        v_line_no := v_line_no + 1;

        -- Skip header row and blank lines
        IF v_line_no = 1 OR TRIM(v_line) IS NULL THEN
            CONTINUE;
        END IF;

        DECLARE
            v_parts APEX_T_VARCHAR2 := APEX_STRING.SPLIT(v_line, ',');
        BEGIN
            APEX_COLLECTION.ADD_MEMBER(
                p_collection_name => 'CONTRIB_UPLOAD',
                p_c001 => TRIM(v_parts(1)),                              -- CNIC
                p_c002 => TRIM(v_parts(2)),                              -- Folio
                p_c003 => CASE WHEN v_parts.COUNT >= 5 THEN TRIM(v_parts(5)) END, -- Name (optional col)
                p_n001 => TO_NUMBER(NULLIF(TRIM(v_parts(4)), '')),       -- Employee Contribution
                p_n002 => TO_NUMBER(NULLIF(TRIM(v_parts(3)), ''))        -- Employer Contribution
            );
        EXCEPTION
            WHEN OTHERS THEN
                -- Malformed row → invalid format (FSD #214)
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'Invalid format',
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
                RETURN;
        END;
    END LOOP;

    :P40_FILE_NAME := :P40_FILE;
    :P40_STEP      := '2';   -- advance to Review
END;

-- ------------------------------------------------------------
-- PROCESS: P40_CREATE_BATCH
-- When:    On Submit
-- Condition: Request = 'CREATE_BATCH'  (Step 3 Alerts → Step 4 Finish)
-- Only callable when the Alerts step shows no blocking errors
-- (FSD #225: variance/duplicates do not block; errors do).
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_batch_id NUMBER;
BEGIN
    EPF_CORP_TXN_PKG.CREATE_CONTRIB_BATCH(
        p_company_id         => :APP_COMPANY_ID,
        p_maker_ucid         => :APP_USER_COMPANY_ID,
        p_fund_id            => :P40_FUND_ID,
        p_contribution_month => :P40_CONTRIB_MONTH,
        p_file_name          => :P40_FILE_NAME,
        p_collection_name    => 'CONTRIB_UPLOAD',
        p_out_success        => v_success,
        p_out_message        => v_message,
        p_out_batch_id       => v_batch_id
    );

    IF v_success = 'Y' THEN
        :P40_BATCH_ID := v_batch_id;
        SELECT BATCH_NO INTO :P40_BATCH_NO
          FROM EPF_CONTRIB_BATCHES WHERE BATCH_ID = v_batch_id;
        -- Finish page text (FSD #226)
        :P40_FINISH_MSG := v_message
            || ' Please visit the View All Contribution Uploads page for status updates.'
            || ' Date & Time: ' || TO_CHAR(SYSDATE, 'DD-MM-YYYY, HH:MI am')
            || ' Reference No.: ' || :P40_BATCH_NO;
        :P40_STEP := '4';
        APEX_COLLECTION.DELETE_COLLECTION('CONTRIB_UPLOAD');
    ELSE
        :P40_STEP := '3';   -- stay on Alerts; errors shown there
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 41  –  Create Loan Request (3-step: Create → Review → Finish)
-- Items: P41_STEP, P41_CNIC, P41_FOLIO_ID, P41_FOLIO_NUMBER,
--        P41_EMP_NAME, P41_CURRENT_BALANCE, P41_AMOUNT,
--        P41_INSTALMENT_MONTHS, P41_PAY_MODE, P41_LOAN_ID,
--        P41_LOAN_NO, P41_FINISH_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P41_CREATE_LOAN
-- When:    On Submit
-- Condition: Request = 'CREATE_LOAN'  (Step 2 Review → Step 3 Finish)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_loan_id NUMBER;
BEGIN
    EPF_CORP_TXN_PKG.CREATE_LOAN_REQUEST(
        p_company_id        => :APP_COMPANY_ID,
        p_maker_ucid        => :APP_USER_COMPANY_ID,
        p_folio_id          => :P41_FOLIO_ID,
        p_amount            => :P41_AMOUNT,
        p_instalment_months => :P41_INSTALMENT_MONTHS,
        p_current_balance   => :P41_CURRENT_BALANCE,
        p_out_success       => v_success,
        p_out_message       => v_message,
        p_out_loan_id       => v_loan_id
    );

    IF v_success = 'Y' THEN
        :P41_LOAN_ID := v_loan_id;
        SELECT LOAN_NO INTO :P41_LOAN_NO
          FROM EPF_LOAN_REQUESTS WHERE LOAN_ID = v_loan_id;
        -- Finish page text (FSD #233)
        :P41_FINISH_MSG := v_message
            || ' Please visit the View All Loan Requests page for status updates.'
            || ' Date & Time: ' || TO_CHAR(SYSDATE, 'DD-MM-YYYY, HH:MI am')
            || ' Reference No.: ' || :P41_LOAN_NO;
        :P41_STEP := '3';
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 42  –  Create Withdrawal Request (3-step)
-- Items: P42_STEP, P42_FOLIO_ID, P42_AMOUNT, P42_FULL_WITHDRAWAL,
--        P42_PAY_MODE, P42_REASON, P42_WD_ID, P42_WD_NO, P42_FINISH_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P42_CREATE_WITHDRAWAL
-- When:    On Submit
-- Condition: Request = 'CREATE_WITHDRAWAL'
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_wd_id   NUMBER;
BEGIN
    EPF_CORP_TXN_PKG.CREATE_WITHDRAWAL_REQUEST(
        p_company_id  => :APP_COMPANY_ID,
        p_maker_ucid  => :APP_USER_COMPANY_ID,
        p_folio_id    => :P42_FOLIO_ID,
        p_amount      => :P42_AMOUNT,
        p_wd_type     => CASE WHEN :P42_FULL_WITHDRAWAL = 'Y' THEN 'FULL' ELSE 'PARTIAL' END,
        p_reason      => :P42_REASON,
        p_out_success => v_success,
        p_out_message => v_message,
        p_out_wd_id   => v_wd_id
    );

    IF v_success = 'Y' THEN
        :P42_WD_ID := v_wd_id;
        SELECT WD_NO INTO :P42_WD_NO
          FROM EPF_WITHDRAWAL_REQUESTS WHERE WD_ID = v_wd_id;
        -- Finish page text (FSD #238)
        :P42_FINISH_MSG := v_message
            || ' Please visit the View All Loan Requests page for status updates.'
            || ' Date & Time: ' || TO_CHAR(SYSDATE, 'DD-MM-YYYY, HH:MI am')
            || ' Reference No.: ' || :P42_WD_NO;
        :P42_STEP := '3';
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 43  –  Lien Mark / Unmark
-- Items: P43_TOGGLE ('MARKED'/'UNMARKED'), P43_SELECTED_FOLIO_IDS,
--        P43_REASON, P43_ATTENTION_MSG, P43_LOAN_WARNING
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P43_CREATE_LIEN_REQUEST
-- When:    On Submit
-- Condition: Request IN ('MARK_LIEN','UNMARK_LIEN')   (FSD #243–#250)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_warn    NUMBER;
    v_type    VARCHAR2(10);
BEGIN
    IF :P43_SELECTED_FOLIO_IDS IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one employee',   -- FSD #243/#249
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    v_type := CASE :REQUEST WHEN 'MARK_LIEN' THEN 'MARK' ELSE 'UNMARK' END;

    EPF_CORP_TXN_PKG.CREATE_LIEN_REQUEST(
        p_company_id       => :APP_COMPANY_ID,
        p_maker_ucid       => :APP_USER_COMPANY_ID,
        p_folio_ids        => :P43_SELECTED_FOLIO_IDS,
        p_request_type     => v_type,
        p_reason           => :P43_REASON,
        p_out_success      => v_success,
        p_out_message      => v_message,
        p_out_loan_warning => v_warn
    );

    IF v_success = 'Y' THEN
        :P43_SELECTED_FOLIO_IDS := NULL;
        :P43_LOAN_WARNING       := v_warn;
        :P43_ATTENTION_MSG      := v_message;   -- attention popup (FSD #245/#250)
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 44  –  NOC Issuance
-- Items: P44_SELECTED_FOLIO_IDS, P44_ATTENTION_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P44_ISSUE_NOC
-- When:    On Submit
-- Condition: Request = 'ISSUE_NOC'   (FSD #253)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_count   NUMBER;
BEGIN
    EPF_CORP_TXN_PKG.CREATE_NOC_REQUESTS(
        p_company_id  => :APP_COMPANY_ID,
        p_maker_ucid  => :APP_USER_COMPANY_ID,
        p_folio_ids   => :P44_SELECTED_FOLIO_IDS,
        p_out_success => v_success,
        p_out_message => v_message,
        p_out_count   => v_count
    );

    IF v_success = 'Y' THEN
        :P44_SELECTED_FOLIO_IDS := NULL;
        :P44_ATTENTION_MSG      := v_message;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 45  –  Disable Employees (Employee Management)
-- Items: P45_SELECTED_FOLIO_IDS
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P45_DISABLE_EMPLOYEES
-- When:    On Submit
-- Condition: Request = 'DISABLE_EMPLOYEES'   (FSD #277)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_count   NUMBER;
BEGIN
    EPF_CORP_TXN_PKG.CREATE_DISABLE_REQUESTS(
        p_company_id  => :APP_COMPANY_ID,
        p_maker_ucid  => :APP_USER_COMPANY_ID,
        p_folio_ids   => :P45_SELECTED_FOLIO_IDS,
        p_out_success => v_success,
        p_out_message => v_message,
        p_out_count   => v_count
    );

    IF v_success = 'Y' THEN
        :P45_SELECTED_FOLIO_IDS := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGES 50–55  –  CHECK REQUEST PAGES
-- Shared item pattern: P5x_SELECTED_IDS (colon-separated),
--                      P5x_REMARKS (mandatory on reject)
-- Requests: 'APPROVE_SELECTED' / 'REJECT_SELECTED'
-- ============================================================

-- ------------------------------------------------------------
-- PAGE 50: Check Contribution Uploads  (FSD #296–#299)
-- PROCESS: P50_CHECKER_DECIDE
-- When:    On Submit
-- Condition: Request IN ('APPROVE_SELECTED','REJECT_SELECTED')
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type => 'CONTRIB',
        p_request_ids  => :P50_SELECTED_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'APPROVE_SELECTED' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P50_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P50_SELECTED_IDS := NULL;
        :P50_REMARKS      := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PAGE 51: Check Loan Requests  (FSD #300–#304)
-- PROCESS: P51_CHECKER_DECIDE
-- When:    On Submit
-- Condition: Request IN ('APPROVE_SELECTED','REJECT_SELECTED')
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type => 'LOAN',
        p_request_ids  => :P51_SELECTED_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'APPROVE_SELECTED' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P51_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P51_SELECTED_IDS := NULL;
        :P51_REMARKS      := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PAGE 52: Check Withdrawal Requests  (FSD #305–#308)
-- PROCESS: P52_CHECKER_DECIDE
-- When:    On Submit
-- Condition: Request IN ('APPROVE_SELECTED','REJECT_SELECTED')
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type => 'WITHDRAWAL',
        p_request_ids  => :P52_SELECTED_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'APPROVE_SELECTED' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P52_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P52_SELECTED_IDS := NULL;
        :P52_REMARKS      := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PAGE 53: Check Lien Requests  (FSD #309–#313)
-- Items also include P53_TOGGLE ('MARK'/'UNMARK') for the
-- Lien Marking Request / Lien Unmarking Request toggle (FSD #311)
-- PROCESS: P53_CHECKER_DECIDE
-- When:    On Submit
-- Condition: Request IN ('APPROVE_SELECTED','REJECT_SELECTED')
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type => 'LIEN',
        p_request_ids  => :P53_SELECTED_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'APPROVE_SELECTED' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P53_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P53_SELECTED_IDS := NULL;
        :P53_REMARKS      := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PAGE 54: Check NOC Requests  (FSD #314–#317)
-- PROCESS: P54_CHECKER_DECIDE
-- When:    On Submit
-- Condition: Request IN ('APPROVE_SELECTED','REJECT_SELECTED')
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type => 'NOC',
        p_request_ids  => :P54_SELECTED_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'APPROVE_SELECTED' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P54_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P54_SELECTED_IDS := NULL;
        :P54_REMARKS      := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PAGE 55: Check Disabled Employees  (FSD #318–#321)
-- Hierarchy ends at Checker: APPROVE applies IS_DISABLED='Y'.
-- PROCESS: P55_CHECKER_DECIDE
-- When:    On Submit
-- Condition: Request IN ('APPROVE_SELECTED','REJECT_SELECTED')
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type => 'DISABLE',
        p_request_ids  => :P55_SELECTED_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'APPROVE_SELECTED' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P55_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P55_SELECTED_IDS := NULL;
        :P55_REMARKS      := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 60  –  Settings (Loan / Withdrawal / Portfolio Reallocation)
-- Maker access-list changes + Checker decisions.
-- Items: P60_FEATURE_CODE ('LOAN'/'WITHDRAWAL'),
--        P60_SELECTED_FOLIO_IDS, P60_SELECTED_ACCESS_IDS,
--        P60_REMARKS, P60_GROUP_ID, P60_GROUP_NAME,
--        P60_MM_LIMIT, P60_DEBT_LIMIT, P60_EQUITY_LIMIT,
--        P60_ADD_FOLIO_IDS, P60_REMOVE_FOLIO_IDS
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P60_FEATURE_ACCESS_ADD
-- When:    On Submit
-- Condition: Request = 'FEATURE_ADD'   (Maker; FSD #325/#329)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.REQUEST_FEATURE_ACCESS_CHANGE(
        p_company_id   => :APP_COMPANY_ID,
        p_maker_ucid   => :APP_USER_COMPANY_ID,
        p_feature_code => :P60_FEATURE_CODE,
        p_folio_ids    => :P60_SELECTED_FOLIO_IDS,
        p_action       => 'ADD',
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P60_SELECTED_FOLIO_IDS := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: P60_FEATURE_ACCESS_REMOVE
-- When:    On Submit
-- Condition: Request = 'FEATURE_REMOVE'   (Maker; FSD #325/#329)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.REQUEST_FEATURE_ACCESS_CHANGE(
        p_company_id   => :APP_COMPANY_ID,
        p_maker_ucid   => :APP_USER_COMPANY_ID,
        p_feature_code => :P60_FEATURE_CODE,
        p_folio_ids    => :P60_SELECTED_FOLIO_IDS,
        p_action       => 'REMOVE',
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P60_SELECTED_FOLIO_IDS := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: P60_FEATURE_ACCESS_DECIDE
-- When:    On Submit
-- Condition: Request IN ('FEATURE_APPROVE','FEATURE_REJECT')
-- (Checker; FSD #326/#330 — remarks mandatory on reject)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE_FEATURE_ACCESS(
        p_access_ids   => :P60_SELECTED_ACCESS_IDS,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'FEATURE_APPROVE' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P60_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P60_SELECTED_ACCESS_IDS := NULL;
        :P60_REMARKS             := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: P60_SAVE_REALLOC_GROUP
-- When:    On Submit
-- Condition: Request = 'SAVE_GROUP'   (Maker; FSD #287–#293)
-- P60_GROUP_ID NULL = create new group
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_group_id NUMBER;
BEGIN
    EPF_CORP_TXN_PKG.SAVE_REALLOC_GROUP(
        p_company_id       => :APP_COMPANY_ID,
        p_maker_ucid       => :APP_USER_COMPANY_ID,
        p_group_id         => :P60_GROUP_ID,
        p_group_name       => :P60_GROUP_NAME,
        p_mm_limit         => :P60_MM_LIMIT,
        p_debt_limit       => :P60_DEBT_LIMIT,
        p_equity_limit     => :P60_EQUITY_LIMIT,
        p_add_folio_ids    => :P60_ADD_FOLIO_IDS,
        p_remove_folio_ids => :P60_REMOVE_FOLIO_IDS,
        p_out_success      => v_success,
        p_out_message      => v_message,
        p_out_group_id     => v_group_id
    );

    IF v_success = 'Y' THEN
        :P60_GROUP_ID         := v_group_id;
        :P60_ADD_FOLIO_IDS    := NULL;
        :P60_REMOVE_FOLIO_IDS := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: P60_REALLOC_GROUP_DECIDE
-- When:    On Submit
-- Condition: Request IN ('GROUP_APPROVE','GROUP_REJECT')
-- (Checker; FSD #334 — reject new = delete; reject edit = discard)
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CHECKER_DECIDE_REALLOC_GROUP(
        p_group_id     => :P60_GROUP_ID,
        p_checker_ucid => :APP_USER_COMPANY_ID,
        p_decision     => CASE :REQUEST WHEN 'GROUP_APPROVE' THEN 'APPROVE' ELSE 'REJECT' END,
        p_remarks      => :P60_REMARKS,
        p_out_success  => v_success,
        p_out_message  => v_message
    );

    IF v_success = 'Y' THEN
        :P60_GROUP_ID := NULL;
        :P60_REMARKS  := NULL;
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- APPLICATION PROCESS: GET_REQUEST_HISTORY_AJAX
-- Type:    On Demand (Application Process)
-- Returns: JSON array of history narrations for a request
-- Called via: apex.server.process('GET_REQUEST_HISTORY_AJAX',
--             {x01: refType, x02: refId}, ...)
-- ============================================================
DECLARE
    v_cur     SYS_REFCURSOR;
    v_ref_no  VARCHAR2(30);
    v_dt      VARCHAR2(30);
    v_tm      VARCHAR2(30);
    v_date    DATE;
    v_code    VARCHAR2(100);
    v_detail  VARCHAR2(4000);
BEGIN
    v_cur := EPF_CORP_TXN_PKG.GET_REQUEST_HISTORY(
                 p_ref_type => APEX_APPLICATION.G_X01,
                 p_ref_id   => TO_NUMBER(APEX_APPLICATION.G_X02));

    APEX_JSON.OPEN_ARRAY;
    LOOP
        FETCH v_cur INTO v_ref_no, v_dt, v_tm, v_date, v_code, v_detail;
        EXIT WHEN v_cur%NOTFOUND;
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('refNo',  v_ref_no);
        APEX_JSON.WRITE('date',   v_dt);
        APEX_JSON.WRITE('time',   v_tm);
        APEX_JSON.WRITE('detail', v_detail);
        APEX_JSON.CLOSE_OBJECT;
    END LOOP;
    CLOSE v_cur;
    APEX_JSON.CLOSE_ARRAY;
END;

-- ============================================================
-- End of page_processes.sql
-- ============================================================
