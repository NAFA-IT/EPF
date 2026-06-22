-- ============================================================
-- FILE: /home/user/EPF/db/18_epf_corp_pkg.sql
-- EPF PORTAL  –  Corporate Package
-- Handles: Contribution Batches, Loan Requests, Withdrawal
--          Requests, Lien Requests, NOC Requests, Employee
--          Disable Requests, Workflow processing, and
--          Company Settings for loan/withdrawal/reallocation.
-- Depends on: 11_corp_txn_ddl.sql, 09_epf_auth_pkg.sql,
--             EPF_STATUS_PKG, EPF_UTIL, sequences.
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_CORP_PKG AS

    -- ── Contribution Batch ─────────────────────────────────────
    PROCEDURE CREATE_CONTRIBUTION_BATCH (
        p_company_id         IN  NUMBER,
        p_maker_ucid         IN  NUMBER,
        p_fund_id            IN  NUMBER,
        p_contribution_month IN  DATE,
        p_file_name          IN  VARCHAR2,
        p_out_success        OUT VARCHAR2,
        p_out_message        OUT VARCHAR2,
        p_out_batch_id       OUT NUMBER
    );

    PROCEDURE ADD_CONTRIBUTION_DETAIL (
        p_batch_id       IN  NUMBER,
        p_employee_cnic  IN  VARCHAR2,
        p_employee_name  IN  VARCHAR2,
        p_emp_contrib    IN  NUMBER,
        p_er_contrib     IN  NUMBER,
        p_contrib_amount IN  NUMBER,
        p_out_success    OUT VARCHAR2,
        p_out_message    OUT VARCHAR2
    );

    PROCEDURE FINALISE_BATCH (
        p_batch_id    IN  NUMBER,
        p_maker_ucid  IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    PROCEDURE SUBMIT_BATCH (
        p_batch_id    IN  NUMBER,
        p_maker_ucid  IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    -- ── Loan Request ───────────────────────────────────────────
    PROCEDURE CREATE_LOAN_REQUEST (
        p_company_id        IN  NUMBER,
        p_employee_id       IN  NUMBER,
        p_maker_ucid        IN  NUMBER,
        p_amount            IN  NUMBER,
        p_instalment_months IN  NUMBER,
        p_out_success       OUT VARCHAR2,
        p_out_message       OUT VARCHAR2,
        p_out_loan_id       OUT NUMBER
    );

    -- ── Withdrawal Request ─────────────────────────────────────
    PROCEDURE CREATE_WITHDRAWAL_REQUEST (
        p_company_id   IN  NUMBER,
        p_employee_id  IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_amount       IN  NUMBER,
        p_reason       IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_wd_id    OUT NUMBER
    );

    -- ── Lien Request ───────────────────────────────────────────
    PROCEDURE CREATE_LIEN_REQUEST (
        p_company_id   IN  NUMBER,
        p_folio_id     IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_lien_type    IN  VARCHAR2,
        p_lien_reason  IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_lien_id  OUT NUMBER
    );

    -- ── NOC Request ────────────────────────────────────────────
    PROCEDURE CREATE_NOC_REQUEST (
        p_company_id   IN  NUMBER,
        p_folio_id     IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_noc_id   OUT NUMBER
    );

    -- ── Disable Employee Request ───────────────────────────────
    PROCEDURE CREATE_DISABLE_REQUEST (
        p_company_id   IN  NUMBER,
        p_employee_id  IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_req_id   OUT NUMBER
    );

    -- ── Workflow Processing ────────────────────────────────────
    -- p_request_type: 'LOAN'|'WITHDRAWAL'|'CONTRIBUTION'|'LIEN'|'NOC'|'DISABLE_EMP'
    -- p_action      : 'APPROVE'|'REJECT'
    PROCEDURE PROCESS_WORKFLOW (
        p_request_type IN  VARCHAR2,
        p_request_id   IN  NUMBER,
        p_actor_ucid   IN  NUMBER,
        p_action       IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_has_checker  IN  BOOLEAN  DEFAULT FALSE,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    );

    -- ── Lien Apply ─────────────────────────────────────────────
    PROCEDURE P_APPLY_LIEN (
        p_lien_id     IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    -- ── Loan Instalment Schedule ───────────────────────────────
    PROCEDURE P_GENERATE_LOAN_INSTALMENTS (
        p_loan_id     IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    -- ── Company Settings ───────────────────────────────────────
    PROCEDURE SAVE_LOAN_SETTINGS (
        p_company_id           IN  NUMBER,
        p_loan_enabled         IN  VARCHAR2,
        p_interest_type_id     IN  NUMBER,
        p_interest_rate        IN  NUMBER,
        p_max_loan_pct         IN  NUMBER,
        p_max_instalment_months IN NUMBER,
        p_floating_rate_tenure IN  NUMBER DEFAULT NULL,
        p_out_success          OUT VARCHAR2,
        p_out_message          OUT VARCHAR2
    );

    PROCEDURE SAVE_WITHDRAWAL_SETTINGS (
        p_company_id         IN  NUMBER,
        p_withdrawal_enabled IN  VARCHAR2,
        p_out_success        OUT VARCHAR2,
        p_out_message        OUT VARCHAR2
    );

    PROCEDURE SAVE_REALLOCATION_SETTINGS (
        p_company_id      IN  NUMBER,
        p_realloc_enabled IN  VARCHAR2,
        p_out_success     OUT VARCHAR2,
        p_out_message     OUT VARCHAR2
    );

END EPF_CORP_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_CORP_PKG AS

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_CONTRIBUTION_BATCH
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_CONTRIBUTION_BATCH (
        p_company_id         IN  NUMBER,
        p_maker_ucid         IN  NUMBER,
        p_fund_id            IN  NUMBER,
        p_contribution_month IN  DATE,
        p_file_name          IN  VARCHAR2,
        p_out_success        OUT VARCHAR2,
        p_out_message        OUT VARCHAR2,
        p_out_batch_id       OUT NUMBER
    ) IS
        v_batch_no  VARCHAR2(30);
        v_batch_id  NUMBER;
        v_status_id NUMBER;
    BEGIN
        p_out_success  := 'N';
        p_out_batch_id := NULL;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_batch_no  := 'CB-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_CONTRIB_BATCH_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_CONTRIB_BATCHES (
            BATCH_NO, COMPANY_ID, FUND_ID, CONTRIBUTION_MONTH, FILE_NAME,
            STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            v_batch_no, p_company_id, p_fund_id,
            TO_CHAR(p_contribution_month, 'YYYY-MM'),
            p_file_name, v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING BATCH_ID INTO v_batch_id;

        COMMIT;

        p_out_success  := 'Y';
        p_out_batch_id := v_batch_id;
        p_out_message  := 'Contribution batch ' || v_batch_no || ' created successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error creating contribution batch: ' || SQLERRM;
    END CREATE_CONTRIBUTION_BATCH;

    -- ═══════════════════════════════════════════════════════════
    --  ADD_CONTRIBUTION_DETAIL
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE ADD_CONTRIBUTION_DETAIL (
        p_batch_id       IN  NUMBER,
        p_employee_cnic  IN  VARCHAR2,
        p_employee_name  IN  VARCHAR2,
        p_emp_contrib    IN  NUMBER,
        p_er_contrib     IN  NUMBER,
        p_contrib_amount IN  NUMBER,
        p_out_success    OUT VARCHAR2,
        p_out_message    OUT VARCHAR2
    ) IS
        v_folio_id   NUMBER;
        v_row_status VARCHAR2(20);
        v_error_msg  VARCHAR2(500);
        l_company_id NUMBER;
    BEGIN
        p_out_success := 'N';

        -- Get company_id from batch
        BEGIN
            SELECT COMPANY_ID INTO l_company_id
              FROM EPF_CONTRIB_BATCHES
             WHERE BATCH_ID = p_batch_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Batch not found.';
                RETURN;
        END;

        -- Resolve folio from CNIC within the company
        BEGIN
            SELECT f.FOLIO_ID
              INTO v_folio_id
              FROM EPF_FOLIOS f
             WHERE f.COMPANY_ID = l_company_id
               AND EXISTS (
                   SELECT 1 FROM EPF_USER_COMPANIES uc
                    JOIN EPF_USERS u ON u.USER_ID = uc.USER_ID
                   WHERE uc.FOLIO_ID = f.FOLIO_ID
                     AND u.CNIC = p_employee_cnic
                     AND ROWNUM = 1
               )
               AND ROWNUM = 1;
            v_row_status := 'VALID';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_folio_id   := NULL;
                v_row_status := 'ERROR';
                v_error_msg  := 'Employee not found for CNIC: ' || p_employee_cnic;
        END;

        INSERT INTO EPF_CONTRIB_BATCH_ROWS (
            BATCH_ID, FOLIO_ID, EMPLOYEE_NAME, CNIC,
            EMPLOYEE_AMOUNT, EMPLOYER_AMOUNT, TOTAL_AMOUNT,
            ROW_STATUS, ERROR_MSG
        ) VALUES (
            p_batch_id, v_folio_id, p_employee_name, p_employee_cnic,
            p_emp_contrib, p_er_contrib, p_contrib_amount,
            v_row_status, v_error_msg
        );

        -- Update batch totals
        UPDATE EPF_CONTRIB_BATCHES
           SET TOTAL_EMPLOYEES = NVL(TOTAL_EMPLOYEES, 0) + CASE WHEN v_row_status = 'VALID' THEN 1 ELSE 0 END,
               TOTAL_AMOUNT    = NVL(TOTAL_AMOUNT, 0) + CASE WHEN v_row_status = 'VALID' THEN p_contrib_amount ELSE 0 END
         WHERE BATCH_ID = p_batch_id;

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'Contribution detail added.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error adding contribution detail: ' || SQLERRM;
    END ADD_CONTRIBUTION_DETAIL;

    -- ═══════════════════════════════════════════════════════════
    --  FINALISE_BATCH
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE FINALISE_BATCH (
        p_batch_id    IN  NUMBER,
        p_maker_ucid  IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_status_id NUMBER;
        v_batch_no  VARCHAR2(30);
    BEGIN
        p_out_success := 'N';

        SELECT BATCH_NO INTO v_batch_no
          FROM EPF_CONTRIB_BATCHES
         WHERE BATCH_ID = p_batch_id;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');

        UPDATE EPF_CONTRIB_BATCHES
           SET STATUS_ID = v_status_id
         WHERE BATCH_ID = p_batch_id;

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'Batch ' || v_batch_no || ' finalised and submitted to Checker.';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_out_success := 'N';
            p_out_message := 'Batch not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error finalising batch: ' || SQLERRM;
    END FINALISE_BATCH;

    -- ═══════════════════════════════════════════════════════════
    --  SUBMIT_BATCH
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE SUBMIT_BATCH (
        p_batch_id    IN  NUMBER,
        p_maker_ucid  IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_status_id NUMBER;
        v_batch_no  VARCHAR2(30);
    BEGIN
        p_out_success := 'N';

        SELECT BATCH_NO INTO v_batch_no
          FROM EPF_CONTRIB_BATCHES
         WHERE BATCH_ID = p_batch_id;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_AUTHORIZER');

        UPDATE EPF_CONTRIB_BATCHES
           SET STATUS_ID = v_status_id
         WHERE BATCH_ID = p_batch_id;

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'Batch ' || v_batch_no || ' submitted to Authorizer.';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_out_success := 'N';
            p_out_message := 'Batch not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error submitting batch: ' || SQLERRM;
    END SUBMIT_BATCH;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_LOAN_REQUEST
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_LOAN_REQUEST (
        p_company_id        IN  NUMBER,
        p_employee_id       IN  NUMBER,
        p_maker_ucid        IN  NUMBER,
        p_amount            IN  NUMBER,
        p_instalment_months IN  NUMBER,
        p_out_success       OUT VARCHAR2,
        p_out_message       OUT VARCHAR2,
        p_out_loan_id       OUT NUMBER
    ) IS
        v_loan_no         VARCHAR2(30);
        v_loan_id         NUMBER;
        v_status_id       NUMBER;
        v_folio_id        NUMBER;
        v_int_type        VARCHAR2(10);
        v_int_rate        NUMBER;
        v_monthly         NUMBER;
    BEGIN
        p_out_success := 'N';
        p_out_loan_id := NULL;

        -- Get folio for this employee in the company
        BEGIN
            SELECT FOLIO_ID INTO v_folio_id
              FROM EPF_USER_COMPANIES
             WHERE USER_ID = p_employee_id
               AND COMPANY_ID = p_company_id
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Employee not found in this company.';
                RETURN;
        END;

        IF NVL(p_amount, 0) <= 0 THEN
            p_out_message := 'Loan amount must be greater than zero.';
            RETURN;
        END IF;

        -- Get loan settings
        BEGIN
            SELECT NVL(LOAN_INTEREST_TYPE, 'FIXED'),
                   NVL(LOAN_INTEREST_RATE, 0)
              INTO v_int_type, v_int_rate
              FROM EPF_COMPANY_SETTINGS
             WHERE COMPANY_ID = p_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_int_type := 'FIXED';
                v_int_rate := 0;
        END;

        v_monthly := ROUND((p_amount + p_amount * v_int_rate / 100) / p_instalment_months, 2);

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_loan_no   := 'LN-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_LOAN_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_LOAN_REQUESTS (
            LOAN_NO, COMPANY_ID, FOLIO_ID, AMOUNT,
            INTEREST_TYPE, INTEREST_RATE, INSTALMENT_MONTHS, MONTHLY_INSTALMENT,
            STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            v_loan_no, p_company_id, v_folio_id, p_amount,
            v_int_type, v_int_rate, p_instalment_months, v_monthly,
            v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING LOAN_ID INTO v_loan_id;

        COMMIT;

        EPF_UTIL.LOG_ACTIVITY(
            p_category      => 'LOAN',
            p_change_req_id => v_loan_id,
            p_activity_code => 'LOAN_REQUEST_CREATED',
            p_narration     => 'Loan request ' || v_loan_no || ' created.',
            p_performed_by  => p_maker_ucid
        );

        p_out_success := 'Y';
        p_out_loan_id := v_loan_id;
        p_out_message := 'Loan request ' || v_loan_no || ' created successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error creating loan request: ' || SQLERRM;
    END CREATE_LOAN_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_WITHDRAWAL_REQUEST
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_WITHDRAWAL_REQUEST (
        p_company_id   IN  NUMBER,
        p_employee_id  IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_amount       IN  NUMBER,
        p_reason       IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_wd_id    OUT NUMBER
    ) IS
        v_wd_no     VARCHAR2(30);
        v_wd_id     NUMBER;
        v_status_id NUMBER;
        v_folio_id  NUMBER;
        v_wd_type   VARCHAR2(10);
    BEGIN
        p_out_success := 'N';
        p_out_wd_id   := NULL;

        -- Get folio for this employee in the company
        BEGIN
            SELECT FOLIO_ID INTO v_folio_id
              FROM EPF_USER_COMPANIES
             WHERE USER_ID = p_employee_id
               AND COMPANY_ID = p_company_id
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Employee not found in this company.';
                RETURN;
        END;

        v_wd_type := CASE WHEN p_amount IS NOT NULL THEN 'PARTIAL' ELSE 'FULL' END;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_wd_no     := 'WD-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_WD_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_WITHDRAWAL_REQUESTS (
            WD_NO, COMPANY_ID, FOLIO_ID, AMOUNT, WD_TYPE, REASON,
            STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            v_wd_no, p_company_id, v_folio_id, p_amount, v_wd_type, p_reason,
            v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING WD_ID INTO v_wd_id;

        COMMIT;

        EPF_UTIL.LOG_ACTIVITY(
            p_category      => 'WITHDRAWAL',
            p_change_req_id => v_wd_id,
            p_activity_code => 'WD_REQUEST_CREATED',
            p_narration     => 'Withdrawal request ' || v_wd_no || ' created.',
            p_performed_by  => p_maker_ucid
        );

        p_out_success := 'Y';
        p_out_wd_id   := v_wd_id;
        p_out_message := 'Withdrawal request ' || v_wd_no || ' created successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error creating withdrawal request: ' || SQLERRM;
    END CREATE_WITHDRAWAL_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_LIEN_REQUEST
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_LIEN_REQUEST (
        p_company_id   IN  NUMBER,
        p_folio_id     IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_lien_type    IN  VARCHAR2,
        p_lien_reason  IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_lien_id  OUT NUMBER
    ) IS
        v_lien_no   VARCHAR2(30);
        v_lien_id   NUMBER;
        v_status_id NUMBER;
    BEGIN
        p_out_success := 'N';
        p_out_lien_id := NULL;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_lien_no   := 'LM-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_LIEN_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_LIEN_REQUESTS (
            LIEN_NO, COMPANY_ID, FOLIO_ID, REQUEST_TYPE, REASON,
            STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            v_lien_no, p_company_id, p_folio_id, p_lien_type, p_lien_reason,
            v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING LIEN_ID INTO v_lien_id;

        COMMIT;

        EPF_UTIL.LOG_ACTIVITY(
            p_category      => 'LIEN',
            p_change_req_id => v_lien_id,
            p_activity_code => 'LIEN_REQUEST_CREATED',
            p_narration     => 'Lien request ' || v_lien_no || ' created.',
            p_performed_by  => p_maker_ucid
        );

        p_out_success := 'Y';
        p_out_lien_id := v_lien_id;
        p_out_message := 'Lien request ' || v_lien_no || ' created successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error creating lien request: ' || SQLERRM;
    END CREATE_LIEN_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_NOC_REQUEST
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_NOC_REQUEST (
        p_company_id   IN  NUMBER,
        p_folio_id     IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_noc_id   OUT NUMBER
    ) IS
        v_noc_no    VARCHAR2(30);
        v_noc_id    NUMBER;
        v_status_id NUMBER;
    BEGIN
        p_out_success := 'N';
        p_out_noc_id  := NULL;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_noc_no    := 'NC-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_NOC_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_NOC_REQUESTS (
            NOC_NO, COMPANY_ID, FOLIO_ID, STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            v_noc_no, p_company_id, p_folio_id, v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING NOC_ID INTO v_noc_id;

        COMMIT;

        EPF_UTIL.LOG_ACTIVITY(
            p_category      => 'NOC',
            p_change_req_id => v_noc_id,
            p_activity_code => 'NOC_REQUEST_CREATED',
            p_narration     => 'NOC request ' || v_noc_no || ' created.',
            p_performed_by  => p_maker_ucid
        );

        p_out_success := 'Y';
        p_out_noc_id  := v_noc_id;
        p_out_message := 'NOC request ' || v_noc_no || ' created successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error creating NOC request: ' || SQLERRM;
    END CREATE_NOC_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_DISABLE_REQUEST
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_DISABLE_REQUEST (
        p_company_id   IN  NUMBER,
        p_employee_id  IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_req_id   OUT NUMBER
    ) IS
        v_req_id    NUMBER;
        v_status_id NUMBER;
        v_folio_id  NUMBER;
        v_ref_no    VARCHAR2(30);
    BEGIN
        p_out_success := 'N';
        p_out_req_id  := NULL;

        -- Get folio for this employee in the company
        BEGIN
            SELECT FOLIO_ID INTO v_folio_id
              FROM EPF_USER_COMPANIES
             WHERE USER_ID = p_employee_id
               AND COMPANY_ID = p_company_id
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Employee not found in this company.';
                RETURN;
        END;

        v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_ref_no    := 'DR-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_NOC_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_EMP_DISABLE_REQUESTS (
            COMPANY_ID, FOLIO_ID, STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            p_company_id, v_folio_id, v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING REQ_ID INTO v_req_id;

        COMMIT;

        EPF_UTIL.LOG_ACTIVITY(
            p_category      => 'DISABLE_EMP',
            p_change_req_id => v_req_id,
            p_activity_code => 'EMP_DISABLE_REQUESTED',
            p_narration     => 'Employee disable request ' || v_ref_no || ' created.',
            p_performed_by  => p_maker_ucid
        );

        p_out_success := 'Y';
        p_out_req_id  := v_req_id;
        p_out_message := 'Disable request created successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error creating disable request: ' || SQLERRM;
    END CREATE_DISABLE_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  PROCESS_WORKFLOW
    --  Advances a request through PENDING_CHECKER →
    --  PENDING_AUTHORIZER → AUTHORIZED, or REJECTED.
    --  p_request_type: 'LOAN'|'WITHDRAWAL'|'CONTRIBUTION'|
    --                  'LIEN'|'NOC'|'DISABLE_EMP'
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE PROCESS_WORKFLOW (
        p_request_type IN  VARCHAR2,
        p_request_id   IN  NUMBER,
        p_actor_ucid   IN  NUMBER,
        p_action       IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_has_checker  IN  BOOLEAN  DEFAULT FALSE,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    ) IS
        v_new_status_id NUMBER;
        l_has_checker   BOOLEAN := p_has_checker;
    BEGIN
        p_out_success := 'N';

        IF p_action NOT IN ('APPROVE', 'REJECT') THEN
            p_out_message := 'Invalid action. Must be APPROVE or REJECT.';
            RETURN;
        END IF;

        IF p_action = 'REJECT' THEN
            v_new_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'REJECTED');
        ELSIF l_has_checker THEN
            v_new_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_AUTHORIZER');
        ELSE
            v_new_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'AUTHORIZED');
        END IF;

        CASE p_request_type
            WHEN 'LOAN' THEN
                UPDATE EPF_LOAN_REQUESTS
                   SET STATUS_ID = v_new_status_id
                 WHERE LOAN_ID = p_request_id;

            WHEN 'WITHDRAWAL' THEN
                UPDATE EPF_WITHDRAWAL_REQUESTS
                   SET STATUS_ID = v_new_status_id
                 WHERE WD_ID = p_request_id;

            WHEN 'CONTRIBUTION' THEN
                UPDATE EPF_CONTRIB_BATCHES
                   SET STATUS_ID = v_new_status_id
                 WHERE BATCH_ID = p_request_id;

            WHEN 'LIEN' THEN
                UPDATE EPF_LIEN_REQUESTS
                   SET STATUS_ID = v_new_status_id
                 WHERE LIEN_ID = p_request_id;

                -- If authorized as MARK or UNMARK, apply the lien change
                IF p_action = 'APPROVE' AND NOT l_has_checker THEN
                    DECLARE
                        v_req_type VARCHAR2(10);
                        v_folio    NUMBER;
                    BEGIN
                        SELECT REQUEST_TYPE, FOLIO_ID
                          INTO v_req_type, v_folio
                          FROM EPF_LIEN_REQUESTS
                         WHERE LIEN_ID = p_request_id;

                        UPDATE EPF_FOLIOS
                           SET LIEN_MARKED = CASE v_req_type WHEN 'MARK' THEN 'Y' ELSE 'N' END
                         WHERE FOLIO_ID = v_folio;
                    END;
                END IF;

            WHEN 'NOC' THEN
                UPDATE EPF_NOC_REQUESTS
                   SET STATUS_ID = v_new_status_id
                 WHERE NOC_ID = p_request_id;

                -- If authorized, mark the folio as NOC issued
                IF p_action = 'APPROVE' AND NOT l_has_checker THEN
                    DECLARE
                        v_folio NUMBER;
                    BEGIN
                        SELECT FOLIO_ID INTO v_folio
                          FROM EPF_NOC_REQUESTS
                         WHERE NOC_ID = p_request_id;

                        UPDATE EPF_FOLIOS
                           SET NOC_ISSUED = 'Y'
                         WHERE FOLIO_ID = v_folio;
                    END;
                END IF;

            WHEN 'DISABLE_EMP' THEN
                UPDATE EPF_EMP_DISABLE_REQUESTS
                   SET STATUS_ID = v_new_status_id
                 WHERE REQ_ID = p_request_id;

                -- If authorized, disable the folio
                IF p_action = 'APPROVE' AND NOT l_has_checker THEN
                    DECLARE
                        v_folio NUMBER;
                    BEGIN
                        SELECT FOLIO_ID INTO v_folio
                          FROM EPF_EMP_DISABLE_REQUESTS
                         WHERE REQ_ID = p_request_id;

                        UPDATE EPF_FOLIOS
                           SET IS_DISABLED = 'Y'
                         WHERE FOLIO_ID = v_folio;
                    END;
                END IF;

            ELSE
                p_out_message := 'Invalid request type: ' || p_request_type;
                RETURN;
        END CASE;

        COMMIT;

        EPF_UTIL.LOG_ACTIVITY(
            p_category      => p_request_type,
            p_change_req_id => p_request_id,
            p_activity_code => p_request_type || '_' || p_action,
            p_narration     => p_request_type || ' request ' || p_request_id
                            || ' ' || LOWER(p_action) || 'd.'
                            || CASE WHEN p_remarks IS NOT NULL
                                    THEN ' Remarks: ' || p_remarks ELSE '' END,
            p_performed_by  => p_actor_ucid
        );

        p_out_success := 'Y';
        p_out_message := p_request_type || ' request ' || p_action || 'D successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error processing workflow: ' || SQLERRM;
    END PROCESS_WORKFLOW;

    -- ═══════════════════════════════════════════════════════════
    --  P_APPLY_LIEN
    --  Applies or removes a lien on the folio based on the
    --  REQUEST_TYPE ('MARK' / 'UNMARK') of the lien request.
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE P_APPLY_LIEN (
        p_lien_id     IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_request_type VARCHAR2(10);
        v_folio_id     NUMBER;
        v_reason       VARCHAR2(2000);
    BEGIN
        p_out_success := 'N';

        SELECT REQUEST_TYPE, FOLIO_ID, REASON
          INTO v_request_type, v_folio_id, v_reason
          FROM EPF_LIEN_REQUESTS
         WHERE LIEN_ID = p_lien_id;

        UPDATE EPF_FOLIOS
           SET LIEN_MARKED = CASE v_request_type WHEN 'MARK' THEN 'Y' ELSE 'N' END
         WHERE FOLIO_ID = v_folio_id;

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'Lien ' || LOWER(v_request_type) || 'ed on folio ' || v_folio_id || '.';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_out_success := 'N';
            p_out_message := 'Lien request not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error applying lien: ' || SQLERRM;
    END P_APPLY_LIEN;

    -- ═══════════════════════════════════════════════════════════
    --  P_GENERATE_LOAN_INSTALMENTS
    --  Generates EPF_LOAN_SCHEDULE rows for an approved loan.
    --  PRINCIPAL = 80% of MONTHLY_INSTALMENT per instalment.
    --  INTEREST  = 20% of MONTHLY_INSTALMENT per instalment.
    --  TOTAL_DUE = MONTHLY_INSTALMENT.
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE P_GENERATE_LOAN_INSTALMENTS (
        p_loan_id     IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_instalment_months NUMBER;
        v_monthly           NUMBER;
        v_principal_pm      NUMBER;
        v_interest_pm       NUMBER;
    BEGIN
        p_out_success := 'N';

        SELECT INSTALMENT_MONTHS, MONTHLY_INSTALMENT
          INTO v_instalment_months, v_monthly
          FROM EPF_LOAN_REQUESTS
         WHERE LOAN_ID = p_loan_id;

        v_principal_pm := ROUND(v_monthly * 0.80, 2);
        v_interest_pm  := ROUND(v_monthly * 0.20, 2);

        FOR i IN 1 .. v_instalment_months LOOP
            INSERT INTO EPF_LOAN_SCHEDULE (
                LOAN_ID, INSTALMENT_NO, DUE_DATE,
                PRINCIPAL, INTEREST, TOTAL_DUE, PAID_YN
            ) VALUES (
                p_loan_id, i, ADD_MONTHS(TRUNC(SYSDATE), i),
                CASE WHEN i = v_instalment_months
                     THEN v_monthly - v_interest_pm * (v_instalment_months - 1)
                          - v_principal_pm * (v_instalment_months - 1)
                     ELSE v_principal_pm END,
                CASE WHEN i = v_instalment_months
                     THEN v_monthly
                          - v_principal_pm * v_instalment_months
                          - v_interest_pm * (v_instalment_months - 1)
                          + v_interest_pm
                     ELSE v_interest_pm END,
                CASE WHEN i = v_instalment_months
                     THEN v_monthly * v_instalment_months
                          - v_monthly * (v_instalment_months - 1)
                     ELSE v_monthly END,
                'N'
            );
        END LOOP;

        COMMIT;

        p_out_success := 'Y';
        p_out_message := v_instalment_months || ' instalment(s) generated for loan ' || p_loan_id || '.';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_out_success := 'N';
            p_out_message := 'Loan not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error generating instalments: ' || SQLERRM;
    END P_GENERATE_LOAN_INSTALMENTS;

    -- ═══════════════════════════════════════════════════════════
    --  SAVE_LOAN_SETTINGS
    --  Merges loan settings into EPF_COMPANY_SETTINGS.
    --  p_interest_type_id: 1 = FIXED, 2 = FLOATING
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE SAVE_LOAN_SETTINGS (
        p_company_id            IN  NUMBER,
        p_loan_enabled          IN  VARCHAR2,
        p_interest_type_id      IN  NUMBER,
        p_interest_rate         IN  NUMBER,
        p_max_loan_pct          IN  NUMBER,
        p_max_instalment_months IN  NUMBER,
        p_floating_rate_tenure  IN  NUMBER DEFAULT NULL,
        p_out_success           OUT VARCHAR2,
        p_out_message           OUT VARCHAR2
    ) IS
        v_int_type VARCHAR2(10);
    BEGIN
        p_out_success := 'N';

        v_int_type := NVL(
            CASE p_interest_type_id
                WHEN 1 THEN 'FIXED'
                WHEN 2 THEN 'FLOATING'
            END,
            'FIXED'
        );

        MERGE INTO EPF_COMPANY_SETTINGS cs
        USING (SELECT p_company_id AS CID FROM DUAL) d
        ON (cs.COMPANY_ID = d.CID)
        WHEN MATCHED THEN UPDATE SET
            LOAN_ENABLED             = p_loan_enabled,
            LOAN_INTEREST_TYPE       = v_int_type,
            LOAN_INTEREST_RATE       = p_interest_rate,
            LOAN_LIMIT_PCT           = p_max_loan_pct,
            LOAN_MAX_INSTALMENT_MONTHS = p_max_instalment_months,
            FLOATING_RATE_TENURE     = p_floating_rate_tenure
        WHEN NOT MATCHED THEN INSERT (
            COMPANY_ID,
            LOAN_ENABLED,
            LOAN_INTEREST_TYPE,
            LOAN_INTEREST_RATE,
            LOAN_LIMIT_PCT,
            LOAN_MAX_INSTALMENT_MONTHS,
            FLOATING_RATE_TENURE
        ) VALUES (
            p_company_id,
            p_loan_enabled,
            v_int_type,
            p_interest_rate,
            p_max_loan_pct,
            p_max_instalment_months,
            p_floating_rate_tenure
        );

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'Loan settings saved successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error saving loan settings: ' || SQLERRM;
    END SAVE_LOAN_SETTINGS;

    -- ═══════════════════════════════════════════════════════════
    --  SAVE_WITHDRAWAL_SETTINGS
    --  NOTE: EPF_COMPANY_SETTINGS does not currently have a
    --  WITHDRAWAL_ENABLED column. This procedure is a no-op stub
    --  until that column is added to the schema.
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE SAVE_WITHDRAWAL_SETTINGS (
        p_company_id         IN  NUMBER,
        p_withdrawal_enabled IN  VARCHAR2,
        p_out_success        OUT VARCHAR2,
        p_out_message        OUT VARCHAR2
    ) IS
    BEGIN
        -- TODO: EPF_COMPANY_SETTINGS needs a WITHDRAWAL_ENABLED column
        -- before this procedure can be implemented.
        NULL;
        p_out_success := 'Y';
        p_out_message := 'Withdrawal settings not yet supported (schema column missing).';
    END SAVE_WITHDRAWAL_SETTINGS;

    -- ═══════════════════════════════════════════════════════════
    --  SAVE_REALLOCATION_SETTINGS
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE SAVE_REALLOCATION_SETTINGS (
        p_company_id      IN  NUMBER,
        p_realloc_enabled IN  VARCHAR2,
        p_out_success     OUT VARCHAR2,
        p_out_message     OUT VARCHAR2
    ) IS
    BEGIN
        p_out_success := 'N';

        MERGE INTO EPF_COMPANY_SETTINGS cs
        USING (SELECT p_company_id AS CID FROM DUAL) d
        ON (cs.COMPANY_ID = d.CID)
        WHEN MATCHED THEN UPDATE SET
            REALLOC_ENABLED = p_realloc_enabled
        WHEN NOT MATCHED THEN INSERT (
            COMPANY_ID,
            REALLOC_ENABLED
        ) VALUES (
            p_company_id,
            p_realloc_enabled
        );

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'Reallocation settings saved successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Error saving reallocation settings: ' || SQLERRM;
    END SAVE_REALLOCATION_SETTINGS;

END EPF_CORP_PKG;
/

-- ============================================================
-- End of 18_epf_corp_pkg.sql
-- ============================================================
