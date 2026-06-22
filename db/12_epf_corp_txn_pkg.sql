-- ============================================================
-- FILE: /home/user/EPF/db/12_epf_corp_txn_pkg.sql
-- EPF PORTAL  –  Corporate Maker / Checker Transaction Package
-- Handles: Contribution Uploads, Loan / Withdrawal / Lien / NOC
--          requests, Employee disablement, Loan & Withdrawal
--          feature-access lists, Portfolio Reallocation groups.
-- Workflow: PENDING_CHECKER → PENDING_AUTHORIZER → AUTHORIZED,
--           or REJECTED.  Checker is OPTIONAL (FSD #4): if the
--           company has no active CORP_CHECKER, Maker requests go
--           straight to PENDING_AUTHORIZER; Checker-terminal flows
--           (Disable, Feature Access, Realloc Groups) are applied
--           instantly.
-- Depends on: 11_corp_txn_ddl.sql, 09_epf_auth_pkg.sql,
--             EPF_STATUS_PKG.  FSD validations #203–#334.
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_CORP_TXN_PKG AS

    -- ── Contribution Upload (FSD #213–#227) ────────────────────
    -- Source rows are read from an APEX collection:
    --   C001 = CNIC, C002 = FOLIO_NUMBER, C003 = EMPLOYEE_NAME,
    --   N001 = EMPLOYEE_AMOUNT, N002 = EMPLOYER_AMOUNT
    PROCEDURE CREATE_CONTRIB_BATCH (
        p_company_id         IN  NUMBER,
        p_maker_ucid         IN  NUMBER,
        p_fund_id            IN  NUMBER,
        p_contribution_month IN  VARCHAR2,            -- 'YYYY-MM'
        p_file_name          IN  VARCHAR2,
        p_collection_name    IN  VARCHAR2 DEFAULT 'CONTRIB_UPLOAD',
        p_out_success        OUT VARCHAR2,
        p_out_message        OUT VARCHAR2,
        p_out_batch_id       OUT NUMBER
    );

    -- ── Loan Request (FSD #228–#233) ────────────────────────────
    PROCEDURE CREATE_LOAN_REQUEST (
        p_company_id        IN  NUMBER,
        p_maker_ucid        IN  NUMBER,
        p_folio_id          IN  NUMBER,
        p_amount            IN  NUMBER,
        p_instalment_months IN  NUMBER,
        p_current_balance   IN  NUMBER DEFAULT NULL,  -- fetched from DFN by caller
        p_out_success       OUT VARCHAR2,
        p_out_message       OUT VARCHAR2,
        p_out_loan_id       OUT NUMBER
    );

    -- ── Withdrawal Request (FSD #234–#238) ──────────────────────
    PROCEDURE CREATE_WITHDRAWAL_REQUEST (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_folio_id     IN  NUMBER,
        p_amount       IN  NUMBER,                    -- NULL when FULL
        p_wd_type      IN  VARCHAR2,                  -- 'PARTIAL' | 'FULL'
        p_reason       IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_wd_id    OUT NUMBER
    );

    -- ── Lien Mark / Unmark Request (FSD #239–#250) ──────────────
    -- p_out_loan_warning = number of selected folios with
    -- outstanding loans (manual-settlement alert, FSD #244–#246)
    PROCEDURE CREATE_LIEN_REQUEST (
        p_company_id       IN  NUMBER,
        p_maker_ucid       IN  NUMBER,
        p_folio_ids        IN  VARCHAR2,              -- colon-separated FOLIO_IDs
        p_request_type     IN  VARCHAR2,              -- 'MARK' | 'UNMARK'
        p_reason           IN  VARCHAR2 DEFAULT NULL,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_loan_warning OUT NUMBER
    );

    -- ── NOC Issuance Requests (FSD #251–#253) ───────────────────
    PROCEDURE CREATE_NOC_REQUESTS (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_folio_ids    IN  VARCHAR2,                  -- colon-separated FOLIO_IDs
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_count    OUT NUMBER
    );

    -- ── Disable Employee Requests (FSD #273–#277) ───────────────
    -- Only folios with NOC_ISSUED = 'Y' are eligible (FSD #275).
    -- Hierarchy ends at Checker; no Checker = disabled instantly.
    PROCEDURE CREATE_DISABLE_REQUESTS (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_folio_ids    IN  VARCHAR2,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_count    OUT NUMBER
    );

    -- ── Checker decision on requests (FSD #299–#321) ────────────
    -- p_request_type: 'CONTRIB'|'LOAN'|'WITHDRAWAL'|'LIEN'|'NOC'|'DISABLE'
    -- p_decision    : 'APPROVE'|'REJECT'  (remarks MANDATORY on reject)
    PROCEDURE CHECKER_DECIDE (
        p_request_type IN  VARCHAR2,
        p_request_ids  IN  VARCHAR2,                  -- colon-separated PK ids
        p_checker_ucid IN  NUMBER,
        p_decision     IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    );

    -- ── Loan / Withdrawal feature access lists (FSD #325–#331) ──
    PROCEDURE REQUEST_FEATURE_ACCESS_CHANGE (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_feature_code IN  VARCHAR2,                  -- 'LOAN' | 'WITHDRAWAL'
        p_folio_ids    IN  VARCHAR2,
        p_action       IN  VARCHAR2,                  -- 'ADD' | 'REMOVE'
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    );

    PROCEDURE CHECKER_DECIDE_FEATURE_ACCESS (
        p_access_ids   IN  VARCHAR2,                  -- colon-separated ACCESS_IDs
        p_checker_ucid IN  NUMBER,
        p_decision     IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    );

    -- ── Portfolio Reallocation custom groups (FSD #286–#294, #332–#335)
    PROCEDURE SAVE_REALLOC_GROUP (
        p_company_id       IN  NUMBER,
        p_maker_ucid       IN  NUMBER,
        p_group_id         IN  NUMBER,                -- NULL = create new group
        p_group_name       IN  VARCHAR2,
        p_mm_limit         IN  NUMBER,
        p_debt_limit       IN  NUMBER,
        p_equity_limit     IN  NUMBER,
        p_add_folio_ids    IN  VARCHAR2 DEFAULT NULL, -- colon-separated
        p_remove_folio_ids IN  VARCHAR2 DEFAULT NULL, -- colon-separated
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_group_id     OUT NUMBER
    );

    PROCEDURE CHECKER_DECIDE_REALLOC_GROUP (
        p_group_id     IN  NUMBER,
        p_checker_ucid IN  NUMBER,
        p_decision     IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    );

    -- ── Request history (status popups, FSD #258/#261/#268/#271)
    -- Narrations are tagged '[Ref <REF_TYPE>-<REF_ID>]' on insert.
    FUNCTION GET_REQUEST_HISTORY (
        p_ref_type IN VARCHAR2,
        p_ref_id   IN NUMBER
    ) RETURN SYS_REFCURSOR;

END EPF_CORP_TXN_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_CORP_TXN_PKG AS
-- ============================================================
--  EPF_CORP_TXN_PKG  –  Body
-- ============================================================

    -- ═══════════════════════════════════════════════════════════
    --  PRIVATE HELPERS
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────────
    --  HAS_ACTIVE_CHECKER
    --  TRUE when the company has at least one ACTIVE CORP_CHECKER
    --  with an active role assignment.  Key FSD rule #4.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION HAS_ACTIVE_CHECKER (
        p_company_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_cnt NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO v_cnt
          FROM EPF_USER_COMPANIES  uc
          JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
          JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
         WHERE uc.COMPANY_ID = p_company_id
           AND ucr.IS_ACTIVE = 'Y'
           AND r.ROLE_CODE   = 'CORP_CHECKER'
           AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE';
        RETURN CASE WHEN v_cnt > 0 THEN 'Y' ELSE 'N' END;
    END HAS_ACTIVE_CHECKER;

    -- ─────────────────────────────────────────────────────────────
    --  INITIAL_STATUS
    --  Returns the STATUS_ID a new Maker request should start in:
    --  PENDING_CHECKER if a Checker exists, else PENDING_AUTHORIZER.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION INITIAL_STATUS (
        p_company_id IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        IF HAS_ACTIVE_CHECKER(p_company_id) = 'Y' THEN
            RETURN EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        ELSE
            RETURN EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_AUTHORIZER');
        END IF;
    END INITIAL_STATUS;

    -- ─────────────────────────────────────────────────────────────
    --  NEXT_HOP_LABEL  –  'Checker' / 'Authorizer' for messages
    -- ─────────────────────────────────────────────────────────────
    FUNCTION NEXT_HOP_LABEL (
        p_company_id IN NUMBER
    ) RETURN VARCHAR2 IS
    BEGIN
        IF HAS_ACTIVE_CHECKER(p_company_id) = 'Y' THEN
            RETURN 'Checker';
        ELSE
            RETURN 'Authorizer';
        END IF;
    END NEXT_HOP_LABEL;

    -- ─────────────────────────────────────────────────────────────
    --  GET_ACTOR_NAME  –  FULL_NAME for a USER_COMPANY_ID
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_ACTOR_NAME (
        p_ucid IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name EPF_USERS.FULL_NAME%TYPE;
    BEGIN
        SELECT u.FULL_NAME
          INTO v_name
          FROM EPF_USERS u
          JOIN EPF_USER_COMPANIES uc ON uc.USER_ID = u.USER_ID
         WHERE uc.USER_COMPANY_ID = p_ucid;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'User';
    END GET_ACTOR_NAME;

    -- ─────────────────────────────────────────────────────────────
    --  GET_FOLIO_UCID / GET_FOLIO_NAME
    --  Resolve the employee USER_COMPANY_ID / name behind a folio
    --  (for dual logging onto the affected employee's history).
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_FOLIO_UCID (
        p_folio_id IN NUMBER
    ) RETURN NUMBER IS
        v_ucid NUMBER;
    BEGIN
        SELECT uc.USER_COMPANY_ID
          INTO v_ucid
          FROM EPF_USER_COMPANIES uc
         WHERE uc.FOLIO_ID = p_folio_id
           AND ROWNUM = 1;
        RETURN v_ucid;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_FOLIO_UCID;

    FUNCTION GET_FOLIO_NAME (
        p_folio_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name EPF_USERS.FULL_NAME%TYPE;
    BEGIN
        SELECT u.FULL_NAME
          INTO v_name
          FROM EPF_USER_COMPANIES uc
          JOIN EPF_USERS u ON u.USER_ID = uc.USER_ID
         WHERE uc.FOLIO_ID = p_folio_id
           AND ROWNUM = 1;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'Employee';
    END GET_FOLIO_NAME;

    -- ─────────────────────────────────────────────────────────────
    --  NARRATE
    --  Builds an FSD-exact narration and dual-logs it via
    --  EPF_PKG_AUTH.LOG_ACTIVITY: once for the actor, once for the
    --  affected employee (if resolvable).  Each entry is tagged
    --  '[Ref <REF_TYPE>-<REF_ID>]' so GET_REQUEST_HISTORY can
    --  retrieve request-specific history.
    --  Format suffix per FSD: 'on DD-Mon-YY, at HH:MI am'
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE NARRATE (
        p_company_id  IN NUMBER,
        p_actor_ucid  IN NUMBER,
        p_action_code IN VARCHAR2,
        p_text        IN VARCHAR2,        -- narration WITHOUT the date/time suffix
        p_ref_type    IN VARCHAR2,
        p_ref_id      IN NUMBER,
        p_folio_id    IN NUMBER DEFAULT NULL,
        p_page_name   IN VARCHAR2 DEFAULT NULL
    ) IS
        v_actor_user_id NUMBER;
        v_emp_ucid      NUMBER;
        v_emp_user_id   NUMBER;
        v_detail        VARCHAR2(4000);
    BEGIN
        v_detail := p_text
                 || ' on ' || TO_CHAR(SYSDATE, 'DD-Mon-YY')
                 || ', at ' || TO_CHAR(SYSDATE, 'HH:MI am')
                 || ' [Ref ' || p_ref_type || '-' || p_ref_id || ']';

        BEGIN
            SELECT USER_ID INTO v_actor_user_id
              FROM EPF_USER_COMPANIES WHERE USER_COMPANY_ID = p_actor_ucid;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_actor_user_id := NULL;
        END;

        -- Actor-side log
        EPF_PKG_AUTH.LOG_ACTIVITY(
            p_user_id         => v_actor_user_id,
            p_company_id      => p_company_id,
            p_user_company_id => p_actor_ucid,
            p_action_code     => p_action_code,
            p_action_detail   => v_detail,
            p_page_name       => p_page_name
        );

        -- Affected-employee-side log (dual logging)
        IF p_folio_id IS NOT NULL THEN
            v_emp_ucid := GET_FOLIO_UCID(p_folio_id);
            IF v_emp_ucid IS NOT NULL AND v_emp_ucid != p_actor_ucid THEN
                BEGIN
                    SELECT USER_ID INTO v_emp_user_id
                      FROM EPF_USER_COMPANIES WHERE USER_COMPANY_ID = v_emp_ucid;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_emp_user_id := NULL;
                END;
                EPF_PKG_AUTH.LOG_ACTIVITY(
                    p_user_id         => v_emp_user_id,
                    p_company_id      => p_company_id,
                    p_user_company_id => v_emp_ucid,
                    p_action_code     => p_action_code,
                    p_action_detail   => v_detail,
                    p_page_name       => p_page_name
                );
            END IF;
        END IF;
    END NARRATE;

    -- ─────────────────────────────────────────────────────────────
    --  NOTIFY  –  insert a row into EPF_NOTIFICATIONS (autonomous)
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE NOTIFY (
        p_company_id IN NUMBER,
        p_user_id    IN NUMBER,
        p_title      IN VARCHAR2,
        p_message    IN VARCHAR2,
        p_ref_type   IN VARCHAR2,
        p_ref_id     IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO EPF_NOTIFICATIONS (
            COMPANY_ID, USER_ID, TITLE, MESSAGE, REF_TYPE, REF_ID, IS_READ
        ) VALUES (
            p_company_id, p_user_id, p_title, p_message, p_ref_type, p_ref_id, 'N'
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END NOTIFY;

    -- ─────────────────────────────────────────────────────────────
    --  NOTIFY_ROLE  –  alert every active user of a role for the
    --  company ("system-generated alerts", FSD #299/#304/etc.)
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE NOTIFY_ROLE (
        p_company_id IN NUMBER,
        p_role_code  IN VARCHAR2,
        p_title      IN VARCHAR2,
        p_message    IN VARCHAR2,
        p_ref_type   IN VARCHAR2,
        p_ref_id     IN NUMBER
    ) IS
    BEGIN
        FOR rec IN (
            SELECT DISTINCT uc.USER_ID
              FROM EPF_USER_COMPANIES  uc
              JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
              JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
             WHERE uc.COMPANY_ID = p_company_id
               AND ucr.IS_ACTIVE = 'Y'
               AND r.ROLE_CODE   = p_role_code
               AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE'
        ) LOOP
            NOTIFY(p_company_id, rec.USER_ID, p_title, p_message, p_ref_type, p_ref_id);
        END LOOP;
    END NOTIFY_ROLE;

    -- ─────────────────────────────────────────────────────────────
    --  NOTIFY_NEXT_HOP  –  Checker(s) if one exists, else Authorizer(s)
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE NOTIFY_NEXT_HOP (
        p_company_id IN NUMBER,
        p_title      IN VARCHAR2,
        p_message    IN VARCHAR2,
        p_ref_type   IN VARCHAR2,
        p_ref_id     IN NUMBER
    ) IS
    BEGIN
        IF HAS_ACTIVE_CHECKER(p_company_id) = 'Y' THEN
            NOTIFY_ROLE(p_company_id, 'CORP_CHECKER', p_title, p_message, p_ref_type, p_ref_id);
        ELSE
            NOTIFY_ROLE(p_company_id, 'CORP_AUTHORIZER', p_title, p_message, p_ref_type, p_ref_id);
        END IF;
    END NOTIFY_NEXT_HOP;

    -- ─────────────────────────────────────────────────────────────
    --  NOTIFY_UCID  –  notify a single USER_COMPANY_ID's user
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE NOTIFY_UCID (
        p_company_id IN NUMBER,
        p_ucid       IN NUMBER,
        p_title      IN VARCHAR2,
        p_message    IN VARCHAR2,
        p_ref_type   IN VARCHAR2,
        p_ref_id     IN NUMBER
    ) IS
        v_user_id NUMBER;
    BEGIN
        SELECT USER_ID INTO v_user_id
          FROM EPF_USER_COMPANIES WHERE USER_COMPANY_ID = p_ucid;
        NOTIFY(p_company_id, v_user_id, p_title, p_message, p_ref_type, p_ref_id);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN NULL;
    END NOTIFY_UCID;

    -- ─────────────────────────────────────────────────────────────
    --  OUTSTANDING_LOAN  –  total outstanding for a folio
    -- ─────────────────────────────────────────────────────────────
    FUNCTION OUTSTANDING_LOAN (
        p_folio_id IN NUMBER
    ) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(OUTSTANDING), 0)
          INTO v_total
          FROM EPF_LOAN_REQUESTS
         WHERE FOLIO_ID = p_folio_id
           AND EPF_STATUS_PKG.GET_CODE(STATUS_ID) = 'AUTHORIZED'
           AND OUTSTANDING > 0;
        RETURN v_total;
    END OUTSTANDING_LOAN;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_CONTRIB_BATCH   (FSD #213–#227)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_CONTRIB_BATCH (
        p_company_id         IN  NUMBER,
        p_maker_ucid         IN  NUMBER,
        p_fund_id            IN  NUMBER,
        p_contribution_month IN  VARCHAR2,
        p_file_name          IN  VARCHAR2,
        p_collection_name    IN  VARCHAR2 DEFAULT 'CONTRIB_UPLOAD',
        p_out_success        OUT VARCHAR2,
        p_out_message        OUT VARCHAR2,
        p_out_batch_id       OUT NUMBER
    ) IS
        v_batch_no       VARCHAR2(30);
        v_batch_id       NUMBER;
        v_status_id      NUMBER;
        v_maker_name     EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_total_amount   NUMBER := 0;
        v_total_emp      NUMBER := 0;
        v_error_cnt      NUMBER := 0;
        v_dup_cnt        NUMBER := 0;
        -- Variance vs last authorized batch (FSD #219, #221, #222)
        v_last_amount    NUMBER;
        v_last_emp       NUMBER;
        v_var_amt_pct    NUMBER;
        v_var_emp_pct    NUMBER;
        v_hop            VARCHAR2(20) := NEXT_HOP_LABEL(p_company_id);
    BEGIN
        p_out_success  := 'N';
        p_out_batch_id := NULL;

        -- ── Guard: collection must contain rows ────────────────
        DECLARE
            v_rows NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_rows
              FROM APEX_COLLECTIONS
             WHERE COLLECTION_NAME = p_collection_name;
            IF v_rows = 0 THEN
                p_out_message := 'Required field';   -- no file content uploaded (FSD #216)
                RETURN;
            END IF;
        END;

        v_status_id := INITIAL_STATUS(p_company_id);
        v_batch_no  := 'CB-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_CONTRIB_BATCH_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_CONTRIB_BATCHES (
            COMPANY_ID, BATCH_NO, FUND_ID, CONTRIBUTION_MONTH, FILE_NAME,
            TOTAL_AMOUNT, TOTAL_EMPLOYEES, STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            p_company_id, v_batch_no, p_fund_id, p_contribution_month, p_file_name,
            0, 0, v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING BATCH_ID INTO v_batch_id;

        -- ── Row-by-row validation (FSD #219, #224, #227) ───────
        FOR rec IN (
            SELECT SEQ_ID,
                   TRIM(C001) AS CNIC,
                   TRIM(C002) AS FOLIO_NUMBER,
                   TRIM(C003) AS EMP_NAME,
                   NVL(N001, 0) AS EMP_AMT,
                   NVL(N002, 0) AS EMR_AMT
              FROM APEX_COLLECTIONS
             WHERE COLLECTION_NAME = p_collection_name
             ORDER BY SEQ_ID
        ) LOOP
            DECLARE
                v_folio_id   NUMBER;
                v_noc        VARCHAR2(1);
                v_disabled   VARCHAR2(1);
                v_row_status VARCHAR2(20) := 'VALID';
                v_error_msg  VARCHAR2(500);
                v_is_dup     VARCHAR2(1) := 'N';
                v_name       VARCHAR2(200);
            BEGIN
                -- Incorrect CNIC format (13 digits, dashes optional)
                IF rec.CNIC IS NULL
                OR NOT REGEXP_LIKE(REPLACE(rec.CNIC, '-', ''), '^[0-9]{13}$') THEN
                    v_row_status := 'ERROR';
                    v_error_msg  := 'Incorrect CNIC/NICOP';
                END IF;

                -- Resolve folio within company
                BEGIN
                    SELECT f.FOLIO_ID, NVL(f.NOC_ISSUED,'N'), NVL(f.IS_DISABLED,'N')
                      INTO v_folio_id, v_noc, v_disabled
                      FROM EPF_FOLIOS f
                     WHERE f.COMPANY_ID   = p_company_id
                       AND f.FOLIO_NUMBER = rec.FOLIO_NUMBER;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_folio_id := NULL;
                        IF v_row_status = 'VALID' THEN
                            v_row_status := 'ERROR';
                            v_error_msg  := 'Incorrect Folio';
                        END IF;
                END;

                -- NOC issued / disabled employees → 'Employee does not exist' (FSD #227)
                IF v_folio_id IS NOT NULL
                AND (v_noc = 'Y' OR v_disabled = 'Y')
                AND v_row_status = 'VALID' THEN
                    v_row_status := 'ERROR';
                    v_error_msg  := 'Employee does not exist';
                END IF;

                -- Duplicate check within this batch (same CNIC + Folio, FSD #223)
                DECLARE
                    v_dup NUMBER;
                BEGIN
                    SELECT COUNT(*) INTO v_dup
                      FROM EPF_CONTRIB_BATCH_ROWS
                     WHERE BATCH_ID = v_batch_id
                       AND CNIC     = rec.CNIC
                       AND NVL(TO_CHAR(FOLIO_ID), '~') = NVL(TO_CHAR(v_folio_id), '~');
                    IF v_dup > 0 THEN
                        v_is_dup  := 'Y';
                        v_dup_cnt := v_dup_cnt + 1;
                    END IF;
                END;

                v_name := NVL(rec.EMP_NAME,
                              CASE WHEN v_folio_id IS NOT NULL
                                   THEN GET_FOLIO_NAME(v_folio_id) END);

                INSERT INTO EPF_CONTRIB_BATCH_ROWS (
                    BATCH_ID, FOLIO_ID, EMPLOYEE_NAME, CNIC,
                    EMPLOYEE_AMOUNT, EMPLOYER_AMOUNT, TOTAL_AMOUNT,
                    ROW_STATUS, ERROR_MSG, IS_DUPLICATE
                ) VALUES (
                    v_batch_id, v_folio_id, v_name, rec.CNIC,
                    rec.EMP_AMT, rec.EMR_AMT, rec.EMP_AMT + rec.EMR_AMT,
                    v_row_status, v_error_msg, v_is_dup
                );

                IF v_row_status = 'ERROR' THEN
                    v_error_cnt := v_error_cnt + 1;
                ELSE
                    v_total_amount := v_total_amount + rec.EMP_AMT + rec.EMR_AMT;
                    v_total_emp    := v_total_emp + 1;
                END IF;
            END;
        END LOOP;

        -- ── Errors block the upload (FSD #225) ─────────────────
        IF v_error_cnt > 0 THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'File cannot be uploaded. Please fix all errors and '
                          || 're-upload the file to proceed. ('
                          || v_error_cnt || ' error(s) found)';
            RETURN;
        END IF;

        -- ── Variance vs last AUTHORIZED batch (FSD #219/#221/#222)
        BEGIN
            SELECT TOTAL_AMOUNT, TOTAL_EMPLOYEES
              INTO v_last_amount, v_last_emp
              FROM EPF_CONTRIB_BATCHES
             WHERE COMPANY_ID = p_company_id
               AND BATCH_ID  != v_batch_id
               AND EPF_STATUS_PKG.GET_CODE(STATUS_ID) = 'AUTHORIZED'
             ORDER BY AUTHORIZED_DATE DESC
             FETCH FIRST 1 ROW ONLY;

            IF NVL(v_last_amount, 0) > 0 THEN
                v_var_amt_pct := ROUND(100 * (v_total_amount - v_last_amount) / v_last_amount, 2);
            END IF;
            IF NVL(v_last_emp, 0) > 0 THEN
                v_var_emp_pct := ROUND(100 * (v_total_emp - v_last_emp) / v_last_emp, 2);
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_var_amt_pct := NULL;
                v_var_emp_pct := NULL;
        END;

        UPDATE EPF_CONTRIB_BATCHES
           SET TOTAL_AMOUNT          = v_total_amount,
               TOTAL_EMPLOYEES       = v_total_emp,
               VARIANCE_AMOUNT_PCT   = v_var_amt_pct,
               VARIANCE_EMPLOYEE_PCT = v_var_emp_pct
         WHERE BATCH_ID = v_batch_id;

        COMMIT;

        -- ── FSD narration ──────────────────────────────────────
        NARRATE(
            p_company_id  => p_company_id,
            p_actor_ucid  => p_maker_ucid,
            p_action_code => 'CONTRIB_BATCH_CREATED',
            p_text        => 'Contribution upload batch ' || v_batch_no
                          || ' created by Maker ' || v_maker_name,
            p_ref_type    => 'CONTRIB',
            p_ref_id      => v_batch_id,
            p_page_name   => 'Create Contribution Upload'
        );

        -- ── Notify next hop ────────────────────────────────────
        NOTIFY_NEXT_HOP(
            p_company_id => p_company_id,
            p_title      => 'Contribution Upload pending approval',
            p_message    => 'Contribution upload batch ' || v_batch_no
                         || ' has been created by Maker ' || v_maker_name
                         || ' and is pending your approval.',
            p_ref_type   => 'CONTRIB',
            p_ref_id     => v_batch_id
        );

        p_out_success  := 'Y';
        p_out_batch_id := v_batch_id;
        p_out_message  := 'Contribution file has been uploaded and sent to the '
                       || v_hop || ' for approval';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_CONTRIB_BATCH;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_LOAN_REQUEST   (FSD #228–#233)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_LOAN_REQUEST (
        p_company_id        IN  NUMBER,
        p_maker_ucid        IN  NUMBER,
        p_folio_id          IN  NUMBER,
        p_amount            IN  NUMBER,
        p_instalment_months IN  NUMBER,
        p_current_balance   IN  NUMBER DEFAULT NULL,
        p_out_success       OUT VARCHAR2,
        p_out_message       OUT VARCHAR2,
        p_out_loan_id       OUT NUMBER
    ) IS
        v_loan_no         VARCHAR2(30);
        v_loan_id         NUMBER;
        v_status_id       NUMBER;
        v_maker_name      EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_emp_name        VARCHAR2(200) := GET_FOLIO_NAME(p_folio_id);
        v_lien            VARCHAR2(1);
        v_noc             VARCHAR2(1);
        v_disabled        VARCHAR2(1);
        -- Loan setup (EPF_COMPANY_SETTINGS, FSD #229/#232)
        v_int_type        VARCHAR2(10);
        v_int_rate        NUMBER;
        v_limit_pct       NUMBER;
        v_max_months      NUMBER;
        -- Schedule
        v_total_interest  NUMBER;
        v_principal_pm    NUMBER;
        v_interest_pm     NUMBER;
        v_monthly         NUMBER;
        v_hop             VARCHAR2(20) := NEXT_HOP_LABEL(p_company_id);
    BEGIN
        p_out_success := 'N';
        p_out_loan_id := NULL;

        -- ── Basic validations ──────────────────────────────────
        IF NVL(p_amount, 0) <= 0 THEN
            p_out_message := 'Loan amount must be greater than zero.';
            RETURN;
        END IF;
        IF NVL(p_instalment_months, 0) <= 0 THEN
            p_out_message := 'Instalment period (months) is required.';
            RETURN;
        END IF;

        -- ── Folio guards (lien / NOC / disabled, FSD #248/#227) ─
        BEGIN
            SELECT NVL(LIEN_MARKED,'N'), NVL(NOC_ISSUED,'N'), NVL(IS_DISABLED,'N')
              INTO v_lien, v_noc, v_disabled
              FROM EPF_FOLIOS
             WHERE FOLIO_ID   = p_folio_id
               AND COMPANY_ID = p_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Folio does not exist for this company.';
                RETURN;
        END;

        IF v_lien = 'Y' THEN
            p_out_message := 'Loan requests are disabled for lien-marked employees.';
            RETURN;
        END IF;
        IF v_noc = 'Y' OR v_disabled = 'Y' THEN
            p_out_message := 'Employee does not exist';
            RETURN;
        END IF;

        -- ── Loan setup from EPF_COMPANY_SETTINGS (if configured) ─
        BEGIN
            SELECT NVL(LOAN_INTEREST_TYPE, 'FIXED'),
                   NVL(LOAN_INTEREST_RATE, 0),
                   LOAN_LIMIT_PCT,
                   LOAN_MAX_INSTALMENT_MONTHS
              INTO v_int_type, v_int_rate, v_limit_pct, v_max_months
              FROM EPF_COMPANY_SETTINGS
             WHERE COMPANY_ID = p_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_int_type := 'FIXED'; v_int_rate := 0;
                v_limit_pct := NULL;   v_max_months := NULL;
        END;

        -- Loan limit: amount cannot exceed limit % of current balance (FSD #229.5)
        IF v_limit_pct IS NOT NULL AND p_current_balance IS NOT NULL THEN
            IF p_amount > p_current_balance * v_limit_pct / 100 THEN
                p_out_message := 'Loan Amount cannot exceed the loan limit ('
                              || v_limit_pct || '% of total balance).';
                RETURN;
            END IF;
        END IF;

        -- Max instalment period (FSD #229.6)
        IF v_max_months IS NOT NULL AND p_instalment_months > v_max_months THEN
            p_out_message := 'Instalment period cannot exceed '
                          || v_max_months || ' months.';
            RETURN;
        END IF;

        -- ── Build flat / straight-line schedule (FSD #232) ─────
        -- Equal principal per instalment + flat interest charged
        -- on the loan amount, spread evenly over the tenure.
        v_total_interest := ROUND(p_amount * v_int_rate / 100, 2);
        v_principal_pm   := ROUND(p_amount / p_instalment_months, 2);
        v_interest_pm    := ROUND(v_total_interest / p_instalment_months, 2);
        v_monthly        := v_principal_pm + v_interest_pm;

        v_status_id := INITIAL_STATUS(p_company_id);
        v_loan_no   := 'LN-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_LOAN_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_LOAN_REQUESTS (
            COMPANY_ID, FOLIO_ID, LOAN_NO, AMOUNT,
            INTEREST_TYPE, INTEREST_RATE, INSTALMENT_MONTHS, MONTHLY_INSTALMENT,
            STATUS_ID, MAKER_UCID, MAKER_DATE, AMOUNT_REPAID, OUTSTANDING
        ) VALUES (
            p_company_id, p_folio_id, v_loan_no, p_amount,
            v_int_type, v_int_rate, p_instalment_months, v_monthly,
            v_status_id, p_maker_ucid, SYSDATE, 0, p_amount + v_total_interest
        )
        RETURNING LOAN_ID INTO v_loan_id;

        FOR i IN 1 .. p_instalment_months LOOP
            INSERT INTO EPF_LOAN_SCHEDULE (
                LOAN_ID, INSTALMENT_NO, DUE_DATE, PRINCIPAL, INTEREST, TOTAL_DUE, PAID_YN
            ) VALUES (
                v_loan_id, i, ADD_MONTHS(TRUNC(SYSDATE), i),
                -- last instalment absorbs rounding residue
                CASE WHEN i = p_instalment_months
                     THEN p_amount - v_principal_pm * (p_instalment_months - 1)
                     ELSE v_principal_pm END,
                CASE WHEN i = p_instalment_months
                     THEN v_total_interest - v_interest_pm * (p_instalment_months - 1)
                     ELSE v_interest_pm END,
                CASE WHEN i = p_instalment_months
                     THEN (p_amount - v_principal_pm * (p_instalment_months - 1))
                        + (v_total_interest - v_interest_pm * (p_instalment_months - 1))
                     ELSE v_monthly END,
                'N'
            );
        END LOOP;

        COMMIT;

        NARRATE(
            p_company_id  => p_company_id,
            p_actor_ucid  => p_maker_ucid,
            p_action_code => 'LOAN_REQUEST_CREATED',
            p_text        => 'Loan request ' || v_loan_no || ' for ' || v_emp_name
                          || ' created by Maker ' || v_maker_name,
            p_ref_type    => 'LOAN',
            p_ref_id      => v_loan_id,
            p_folio_id    => p_folio_id,
            p_page_name   => 'Create Loan Request'
        );

        NOTIFY_NEXT_HOP(
            p_company_id => p_company_id,
            p_title      => 'Loan Request pending approval',
            p_message    => 'Loan request ' || v_loan_no || ' for ' || v_emp_name
                         || ' has been created by Maker ' || v_maker_name
                         || ' and is pending your approval.',
            p_ref_type   => 'LOAN',
            p_ref_id     => v_loan_id
        );

        p_out_success := 'Y';
        p_out_loan_id := v_loan_id;
        p_out_message := 'Loan request has been created and sent to the '
                      || v_hop || ' for approval';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_LOAN_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_WITHDRAWAL_REQUEST   (FSD #234–#238)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_WITHDRAWAL_REQUEST (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_folio_id     IN  NUMBER,
        p_amount       IN  NUMBER,
        p_wd_type      IN  VARCHAR2,
        p_reason       IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_wd_id    OUT NUMBER
    ) IS
        v_wd_no      VARCHAR2(30);
        v_wd_id      NUMBER;
        v_status_id  NUMBER;
        v_maker_name EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_emp_name   VARCHAR2(200) := GET_FOLIO_NAME(p_folio_id);
        v_lien       VARCHAR2(1);
        v_noc        VARCHAR2(1);
        v_disabled   VARCHAR2(1);
        v_hop        VARCHAR2(20) := NEXT_HOP_LABEL(p_company_id);
    BEGIN
        p_out_success := 'N';
        p_out_wd_id   := NULL;

        IF p_wd_type NOT IN ('PARTIAL', 'FULL') THEN
            p_out_message := 'Invalid withdrawal type.';
            RETURN;
        END IF;
        IF p_wd_type = 'PARTIAL' AND NVL(p_amount, 0) <= 0 THEN
            p_out_message := 'Withdrawal amount must be greater than zero.';
            RETURN;
        END IF;

        BEGIN
            SELECT NVL(LIEN_MARKED,'N'), NVL(NOC_ISSUED,'N'), NVL(IS_DISABLED,'N')
              INTO v_lien, v_noc, v_disabled
              FROM EPF_FOLIOS
             WHERE FOLIO_ID   = p_folio_id
               AND COMPANY_ID = p_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Folio does not exist for this company.';
                RETURN;
        END;

        IF v_lien = 'Y' THEN
            p_out_message := 'Withdrawal requests are disabled for lien-marked employees.';
            RETURN;
        END IF;
        IF v_noc = 'Y' OR v_disabled = 'Y' THEN
            p_out_message := 'Employee does not exist';
            RETURN;
        END IF;

        v_status_id := INITIAL_STATUS(p_company_id);
        v_wd_no     := 'WD-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                    || LPAD(EPF_WD_REQ_SEQ.NEXTVAL, 4, '0');

        INSERT INTO EPF_WITHDRAWAL_REQUESTS (
            COMPANY_ID, FOLIO_ID, WD_NO, AMOUNT, WD_TYPE, REASON,
            STATUS_ID, MAKER_UCID, MAKER_DATE
        ) VALUES (
            p_company_id, p_folio_id, v_wd_no,
            CASE WHEN p_wd_type = 'FULL' THEN NULL ELSE p_amount END,
            p_wd_type, p_reason, v_status_id, p_maker_ucid, SYSDATE
        )
        RETURNING WD_ID INTO v_wd_id;

        COMMIT;

        NARRATE(
            p_company_id  => p_company_id,
            p_actor_ucid  => p_maker_ucid,
            p_action_code => 'WD_REQUEST_CREATED',
            p_text        => 'Withdrawal request ' || v_wd_no || ' for ' || v_emp_name
                          || ' created by Maker ' || v_maker_name,
            p_ref_type    => 'WITHDRAWAL',
            p_ref_id      => v_wd_id,
            p_folio_id    => p_folio_id,
            p_page_name   => 'Create Withdrawal Request'
        );

        NOTIFY_NEXT_HOP(
            p_company_id => p_company_id,
            p_title      => 'Withdrawal Request pending approval',
            p_message    => 'Withdrawal request ' || v_wd_no || ' for ' || v_emp_name
                         || ' has been created by Maker ' || v_maker_name
                         || ' and is pending your approval.',
            p_ref_type   => 'WITHDRAWAL',
            p_ref_id     => v_wd_id
        );

        p_out_success := 'Y';
        p_out_wd_id   := v_wd_id;
        p_out_message := 'Withdrawal request has been created and sent to the '
                      || v_hop || ' for approval';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_WITHDRAWAL_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_LIEN_REQUEST   (FSD #239–#250)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_LIEN_REQUEST (
        p_company_id       IN  NUMBER,
        p_maker_ucid       IN  NUMBER,
        p_folio_ids        IN  VARCHAR2,
        p_request_type     IN  VARCHAR2,
        p_reason           IN  VARCHAR2 DEFAULT NULL,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_loan_warning OUT NUMBER
    ) IS
        v_status_id  NUMBER;
        v_maker_name EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_count      NUMBER := 0;
        v_warn       NUMBER := 0;
        v_hop        VARCHAR2(20) := NEXT_HOP_LABEL(p_company_id);
        v_verb       VARCHAR2(20);
    BEGIN
        p_out_success      := 'N';
        p_out_loan_warning := 0;

        IF p_request_type NOT IN ('MARK', 'UNMARK') THEN
            p_out_message := 'Invalid lien request type.';
            RETURN;
        END IF;
        IF p_folio_ids IS NULL THEN
            p_out_message := 'Please select at least one employee';   -- FSD #243/#249
            RETURN;
        END IF;

        v_status_id := INITIAL_STATUS(p_company_id);
        v_verb := CASE p_request_type WHEN 'MARK' THEN 'marking' ELSE 'unmarking' END;

        FOR rec IN (
            SELECT TO_NUMBER(COLUMN_VALUE) AS FOLIO_ID
              FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_folio_ids, ':'))
        ) LOOP
            DECLARE
                v_lien_id  NUMBER;
                v_lien_no  VARCHAR2(30);
                v_emp_name VARCHAR2(200) := GET_FOLIO_NAME(rec.FOLIO_ID);
            BEGIN
                -- Manual-settlement alert: outstanding loans (FSD #244–#246)
                IF p_request_type = 'UNMARK'
                AND OUTSTANDING_LOAN(rec.FOLIO_ID) > 0 THEN
                    v_warn := v_warn + 1;
                END IF;

                v_lien_no := 'LM-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                          || LPAD(EPF_LIEN_REQ_SEQ.NEXTVAL, 4, '0');

                INSERT INTO EPF_LIEN_REQUESTS (
                    COMPANY_ID, FOLIO_ID, LIEN_NO, REQUEST_TYPE, REASON,
                    STATUS_ID, MAKER_UCID, MAKER_DATE
                ) VALUES (
                    p_company_id, rec.FOLIO_ID, v_lien_no, p_request_type, p_reason,
                    v_status_id, p_maker_ucid, SYSDATE
                )
                RETURNING LIEN_ID INTO v_lien_id;

                v_count := v_count + 1;

                NARRATE(
                    p_company_id  => p_company_id,
                    p_actor_ucid  => p_maker_ucid,
                    p_action_code => 'LIEN_' || p_request_type || '_CREATED',
                    p_text        => 'Lien ' || v_verb || ' request ' || v_lien_no
                                  || ' for ' || v_emp_name
                                  || ' created by Maker ' || v_maker_name,
                    p_ref_type    => 'LIEN',
                    p_ref_id      => v_lien_id,
                    p_folio_id    => rec.FOLIO_ID,
                    p_page_name   => 'Lien Mark / Unmark'
                );

                NOTIFY_NEXT_HOP(
                    p_company_id => p_company_id,
                    p_title      => 'Lien Request pending approval',
                    p_message    => 'Lien ' || v_verb || ' request ' || v_lien_no
                                 || ' for ' || v_emp_name
                                 || ' has been created by Maker ' || v_maker_name
                                 || ' and is pending your approval.',
                    p_ref_type   => 'LIEN',
                    p_ref_id     => v_lien_id
                );
            END;
        END LOOP;

        COMMIT;

        p_out_success      := 'Y';
        p_out_loan_warning := v_warn;
        -- Attention popup text per FSD #245/#250
        p_out_message := 'Request has been sent to the ' || v_hop || ' for approval. '
                      || 'Please visit the View All Lien Requests page for status updates.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_LIEN_REQUEST;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_NOC_REQUESTS   (FSD #251–#253)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_NOC_REQUESTS (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_folio_ids    IN  VARCHAR2,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_count    OUT NUMBER
    ) IS
        v_status_id  NUMBER;
        v_maker_name EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_count      NUMBER := 0;
        v_hop        VARCHAR2(20) := NEXT_HOP_LABEL(p_company_id);
    BEGIN
        p_out_success := 'N';
        p_out_count   := 0;

        IF p_folio_ids IS NULL THEN
            p_out_message := 'Please select at least one employee';
            RETURN;
        END IF;

        v_status_id := INITIAL_STATUS(p_company_id);

        FOR rec IN (
            SELECT TO_NUMBER(COLUMN_VALUE) AS FOLIO_ID
              FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_folio_ids, ':'))
        ) LOOP
            DECLARE
                v_noc_id   NUMBER;
                v_noc_no   VARCHAR2(30);
                v_emp_name VARCHAR2(200) := GET_FOLIO_NAME(rec.FOLIO_ID);
                v_lien     VARCHAR2(1);
            BEGIN
                -- Outstanding loans block NOC issuance (FSD #252)
                IF OUTSTANDING_LOAN(rec.FOLIO_ID) > 0 THEN
                    CONTINUE;
                END IF;
                -- Lien-marked folios cannot be issued NOC
                SELECT NVL(LIEN_MARKED, 'N') INTO v_lien
                  FROM EPF_FOLIOS
                 WHERE FOLIO_ID = rec.FOLIO_ID AND COMPANY_ID = p_company_id;
                IF v_lien = 'Y' THEN
                    CONTINUE;
                END IF;

                v_noc_no := 'NC-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-'
                         || LPAD(EPF_NOC_REQ_SEQ.NEXTVAL, 4, '0');

                INSERT INTO EPF_NOC_REQUESTS (
                    COMPANY_ID, FOLIO_ID, NOC_NO, STATUS_ID, MAKER_UCID, MAKER_DATE
                ) VALUES (
                    p_company_id, rec.FOLIO_ID, v_noc_no, v_status_id, p_maker_ucid, SYSDATE
                )
                RETURNING NOC_ID INTO v_noc_id;

                v_count := v_count + 1;

                NARRATE(
                    p_company_id  => p_company_id,
                    p_actor_ucid  => p_maker_ucid,
                    p_action_code => 'NOC_REQUEST_CREATED',
                    p_text        => 'NOC issuance request ' || v_noc_no
                                  || ' for ' || v_emp_name
                                  || ' created by Maker ' || v_maker_name,
                    p_ref_type    => 'NOC',
                    p_ref_id      => v_noc_id,
                    p_folio_id    => rec.FOLIO_ID,
                    p_page_name   => 'NOC Issuance'
                );

                NOTIFY_NEXT_HOP(
                    p_company_id => p_company_id,
                    p_title      => 'NOC Request pending approval',
                    p_message    => 'NOC issuance request ' || v_noc_no
                                 || ' for ' || v_emp_name
                                 || ' has been created by Maker ' || v_maker_name
                                 || ' and is pending your approval.',
                    p_ref_type   => 'NOC',
                    p_ref_id     => v_noc_id
                );
            EXCEPTION
                WHEN NO_DATA_FOUND THEN CONTINUE;   -- folio not in company
            END;
        END LOOP;

        COMMIT;

        IF v_count = 0 THEN
            p_out_success := 'N';
            p_out_message := 'No eligible employees were selected. Employees with '
                          || 'outstanding loans or lien-marked accounts cannot be issued NOC.';
            RETURN;
        END IF;

        p_out_success := 'Y';
        p_out_count   := v_count;
        p_out_message := 'Request has been sent to the ' || v_hop || ' for approval. '
                      || 'Please visit the View All NOC Requests page for status updates.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_NOC_REQUESTS;

    -- ═══════════════════════════════════════════════════════════
    --  CREATE_DISABLE_REQUESTS   (FSD #273–#277)
    --  Hierarchy: Maker → Checker only.  No Checker = apply now.
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CREATE_DISABLE_REQUESTS (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_folio_ids    IN  VARCHAR2,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_count    OUT NUMBER
    ) IS
        v_maker_name  EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_has_checker VARCHAR2(1) := HAS_ACTIVE_CHECKER(p_company_id);
        v_pend_sid    NUMBER  := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_auth_sid    NUMBER  := EPF_STATUS_PKG.GET_ID('REQUEST', 'AUTHORIZED');
        v_count       NUMBER  := 0;
    BEGIN
        p_out_success := 'N';
        p_out_count   := 0;

        IF p_folio_ids IS NULL THEN
            p_out_message := 'Please select at least one employee';
            RETURN;
        END IF;

        FOR rec IN (
            SELECT TO_NUMBER(COLUMN_VALUE) AS FOLIO_ID
              FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_folio_ids, ':'))
        ) LOOP
            DECLARE
                v_req_id   NUMBER;
                v_noc      VARCHAR2(1);
                v_disabled VARCHAR2(1);
                v_emp_name VARCHAR2(200) := GET_FOLIO_NAME(rec.FOLIO_ID);
            BEGIN
                SELECT NVL(NOC_ISSUED, 'N'), NVL(IS_DISABLED, 'N')
                  INTO v_noc, v_disabled
                  FROM EPF_FOLIOS
                 WHERE FOLIO_ID = rec.FOLIO_ID AND COMPANY_ID = p_company_id;

                -- Only NOC-issued employees can be disabled (FSD #275)
                IF v_noc != 'Y' OR v_disabled = 'Y' THEN
                    CONTINUE;
                END IF;

                IF v_has_checker = 'Y' THEN
                    INSERT INTO EPF_EMP_DISABLE_REQUESTS (
                        COMPANY_ID, FOLIO_ID, STATUS_ID, MAKER_UCID, MAKER_DATE
                    ) VALUES (
                        p_company_id, rec.FOLIO_ID, v_pend_sid, p_maker_ucid, SYSDATE
                    )
                    RETURNING REQ_ID INTO v_req_id;

                    NARRATE(
                        p_company_id  => p_company_id,
                        p_actor_ucid  => p_maker_ucid,
                        p_action_code => 'EMP_DISABLE_REQUESTED',
                        p_text        => 'Disablement request for ' || v_emp_name
                                      || ' created by Maker ' || v_maker_name,
                        p_ref_type    => 'DISABLE',
                        p_ref_id      => v_req_id,
                        p_folio_id    => rec.FOLIO_ID,
                        p_page_name   => 'Disable Employees'
                    );

                    NOTIFY_ROLE(
                        p_company_id => p_company_id,
                        p_role_code  => 'CORP_CHECKER',
                        p_title      => 'Employee disablement pending approval',
                        p_message    => 'Disablement request for ' || v_emp_name
                                     || ' has been created by Maker ' || v_maker_name
                                     || ' and is pending your approval.',
                        p_ref_type   => 'DISABLE',
                        p_ref_id     => v_req_id
                    );
                ELSE
                    -- No Checker → apply instantly (FSD #277, #318)
                    INSERT INTO EPF_EMP_DISABLE_REQUESTS (
                        COMPANY_ID, FOLIO_ID, STATUS_ID, MAKER_UCID, MAKER_DATE
                    ) VALUES (
                        p_company_id, rec.FOLIO_ID, v_auth_sid, p_maker_ucid, SYSDATE
                    )
                    RETURNING REQ_ID INTO v_req_id;

                    UPDATE EPF_FOLIOS
                       SET IS_DISABLED = 'Y'
                     WHERE FOLIO_ID = rec.FOLIO_ID;

                    NARRATE(
                        p_company_id  => p_company_id,
                        p_actor_ucid  => p_maker_ucid,
                        p_action_code => 'EMP_DISABLED',
                        p_text        => 'Employee ' || v_emp_name
                                      || ' disabled by Maker ' || v_maker_name
                                      || ' (no Checker exists)',
                        p_ref_type    => 'DISABLE',
                        p_ref_id      => v_req_id,
                        p_folio_id    => rec.FOLIO_ID,
                        p_page_name   => 'Disable Employees'
                    );
                END IF;

                v_count := v_count + 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN CONTINUE;
            END;
        END LOOP;

        COMMIT;

        p_out_success := 'Y';
        p_out_count   := v_count;
        IF v_has_checker = 'Y' THEN
            p_out_message := v_count || ' disablement request(s) sent to the Checker for approval.';
        ELSE
            p_out_message := v_count || ' employee(s) have been disabled.';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_DISABLE_REQUESTS;

    -- ═══════════════════════════════════════════════════════════
    --  CHECKER_DECIDE   (FSD #299, #304, #308, #313, #317, #321)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CHECKER_DECIDE (
        p_request_type IN  VARCHAR2,
        p_request_ids  IN  VARCHAR2,
        p_checker_ucid IN  NUMBER,
        p_decision     IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    ) IS
        v_checker_name EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_checker_ucid);
        v_pend_chk     NUMBER := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_pend_auth    NUMBER := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_AUTHORIZER');
        v_authorized   NUMBER := EPF_STATUS_PKG.GET_ID('REQUEST', 'AUTHORIZED');
        v_rejected     NUMBER := EPF_STATUS_PKG.GET_ID('REQUEST', 'REJECTED');
        v_count        NUMBER := 0;
        v_label        VARCHAR2(50);
    BEGIN
        p_out_success := 'N';

        -- ── Validations ────────────────────────────────────────
        IF p_request_type NOT IN ('CONTRIB','LOAN','WITHDRAWAL','LIEN','NOC','DISABLE') THEN
            p_out_message := 'Invalid request type.';
            RETURN;
        END IF;
        IF p_decision NOT IN ('APPROVE', 'REJECT') THEN
            p_out_message := 'Invalid decision. Must be APPROVE or REJECT.';
            RETURN;
        END IF;
        -- Remarks are MANDATORY on rejection (FSD #299.6, #304.3, etc.)
        IF p_decision = 'REJECT' AND TRIM(p_remarks) IS NULL THEN
            p_out_message := 'Remarks are required for rejection.';
            RETURN;
        END IF;
        IF p_request_ids IS NULL THEN
            p_out_message := 'Please select at least one request.';
            RETURN;
        END IF;

        v_label := CASE p_request_type
                       WHEN 'CONTRIB'    THEN 'Contribution upload batch'
                       WHEN 'LOAN'       THEN 'Loan request'
                       WHEN 'WITHDRAWAL' THEN 'Withdrawal request'
                       WHEN 'LIEN'       THEN 'Lien request'
                       WHEN 'NOC'        THEN 'NOC issuance request'
                       WHEN 'DISABLE'    THEN 'Employee disablement request'
                   END;

        FOR rec IN (
            SELECT TO_NUMBER(COLUMN_VALUE) AS REQ_ID
              FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_request_ids, ':'))
        ) LOOP
            DECLARE
                v_company_id NUMBER;
                v_folio_id   NUMBER;
                v_maker_ucid NUMBER;
                v_status_id  NUMBER;
                v_ref_no     VARCHAR2(30);
                v_new_status NUMBER;
                v_text       VARCHAR2(2000);
            BEGIN
                -- ── Fetch the request per type (status must be PENDING_CHECKER)
                CASE p_request_type
                    WHEN 'CONTRIB' THEN
                        SELECT COMPANY_ID, NULL, MAKER_UCID, STATUS_ID, BATCH_NO
                          INTO v_company_id, v_folio_id, v_maker_ucid, v_status_id, v_ref_no
                          FROM EPF_CONTRIB_BATCHES WHERE BATCH_ID = rec.REQ_ID;
                    WHEN 'LOAN' THEN
                        SELECT COMPANY_ID, FOLIO_ID, MAKER_UCID, STATUS_ID, LOAN_NO
                          INTO v_company_id, v_folio_id, v_maker_ucid, v_status_id, v_ref_no
                          FROM EPF_LOAN_REQUESTS WHERE LOAN_ID = rec.REQ_ID;
                    WHEN 'WITHDRAWAL' THEN
                        SELECT COMPANY_ID, FOLIO_ID, MAKER_UCID, STATUS_ID, WD_NO
                          INTO v_company_id, v_folio_id, v_maker_ucid, v_status_id, v_ref_no
                          FROM EPF_WITHDRAWAL_REQUESTS WHERE WD_ID = rec.REQ_ID;
                    WHEN 'LIEN' THEN
                        SELECT COMPANY_ID, FOLIO_ID, MAKER_UCID, STATUS_ID, LIEN_NO
                          INTO v_company_id, v_folio_id, v_maker_ucid, v_status_id, v_ref_no
                          FROM EPF_LIEN_REQUESTS WHERE LIEN_ID = rec.REQ_ID;
                    WHEN 'NOC' THEN
                        SELECT COMPANY_ID, FOLIO_ID, MAKER_UCID, STATUS_ID, NOC_NO
                          INTO v_company_id, v_folio_id, v_maker_ucid, v_status_id, v_ref_no
                          FROM EPF_NOC_REQUESTS WHERE NOC_ID = rec.REQ_ID;
                    WHEN 'DISABLE' THEN
                        SELECT COMPANY_ID, FOLIO_ID, MAKER_UCID, STATUS_ID, TO_CHAR(REQ_ID)
                          INTO v_company_id, v_folio_id, v_maker_ucid, v_status_id, v_ref_no
                          FROM EPF_EMP_DISABLE_REQUESTS WHERE REQ_ID = rec.REQ_ID;
                END CASE;

                -- Only pending-at-checker requests may be decided
                IF v_status_id != v_pend_chk THEN
                    CONTINUE;
                END IF;

                -- ── Determine new status ───────────────────────
                IF p_decision = 'REJECT' THEN
                    v_new_status := v_rejected;
                ELSIF p_request_type = 'DISABLE' THEN
                    v_new_status := v_authorized;    -- hierarchy ends at Checker (FSD #321)
                ELSE
                    v_new_status := v_pend_auth;
                END IF;

                -- ── Apply per type ─────────────────────────────
                CASE p_request_type
                    WHEN 'CONTRIB' THEN
                        UPDATE EPF_CONTRIB_BATCHES
                           SET STATUS_ID = v_new_status, CHECKER_UCID = p_checker_ucid,
                               CHECKER_DATE = SYSDATE, CHECKER_REMARKS = p_remarks
                         WHERE BATCH_ID = rec.REQ_ID;
                    WHEN 'LOAN' THEN
                        UPDATE EPF_LOAN_REQUESTS
                           SET STATUS_ID = v_new_status, CHECKER_UCID = p_checker_ucid,
                               CHECKER_DATE = SYSDATE, CHECKER_REMARKS = p_remarks
                         WHERE LOAN_ID = rec.REQ_ID;
                    WHEN 'WITHDRAWAL' THEN
                        UPDATE EPF_WITHDRAWAL_REQUESTS
                           SET STATUS_ID = v_new_status, CHECKER_UCID = p_checker_ucid,
                               CHECKER_DATE = SYSDATE, CHECKER_REMARKS = p_remarks
                         WHERE WD_ID = rec.REQ_ID;
                    WHEN 'LIEN' THEN
                        UPDATE EPF_LIEN_REQUESTS
                           SET STATUS_ID = v_new_status, CHECKER_UCID = p_checker_ucid,
                               CHECKER_DATE = SYSDATE, CHECKER_REMARKS = p_remarks
                         WHERE LIEN_ID = rec.REQ_ID;
                    WHEN 'NOC' THEN
                        UPDATE EPF_NOC_REQUESTS
                           SET STATUS_ID = v_new_status, CHECKER_UCID = p_checker_ucid,
                               CHECKER_DATE = SYSDATE, CHECKER_REMARKS = p_remarks
                         WHERE NOC_ID = rec.REQ_ID;
                    WHEN 'DISABLE' THEN
                        UPDATE EPF_EMP_DISABLE_REQUESTS
                           SET STATUS_ID = v_new_status, CHECKER_UCID = p_checker_ucid,
                               CHECKER_DATE = SYSDATE, CHECKER_REMARKS = p_remarks
                         WHERE REQ_ID = rec.REQ_ID;
                        -- Approval = employee disabled immediately (FSD #321.4)
                        IF p_decision = 'APPROVE' THEN
                            UPDATE EPF_FOLIOS SET IS_DISABLED = 'Y'
                             WHERE FOLIO_ID = v_folio_id;
                        END IF;
                END CASE;

                v_count := v_count + 1;

                -- ── FSD-exact narration + notifications ────────
                IF p_decision = 'APPROVE' THEN
                    v_text := v_label || ' ' || v_ref_no
                           || ' approved by Checker ' || v_checker_name;
                ELSE
                    v_text := v_label || ' ' || v_ref_no
                           || ' rejected by Checker ' || v_checker_name
                           || ' with remarks: ' || p_remarks;
                END IF;

                NARRATE(
                    p_company_id  => v_company_id,
                    p_actor_ucid  => p_checker_ucid,
                    p_action_code => p_request_type || '_CHECKER_' || p_decision,
                    p_text        => v_text,
                    p_ref_type    => p_request_type,
                    p_ref_id      => rec.REQ_ID,
                    p_folio_id    => v_folio_id,
                    p_page_name   => 'Check Requests'
                );

                IF p_decision = 'REJECT' THEN
                    -- Maker is notified via system-generated alerts (FSD #299.8 etc.)
                    NOTIFY_UCID(
                        p_company_id => v_company_id,
                        p_ucid       => v_maker_ucid,
                        p_title      => v_label || ' rejected',
                        p_message    => v_text || '.',
                        p_ref_type   => p_request_type,
                        p_ref_id     => rec.REQ_ID
                    );
                ELSIF p_request_type != 'DISABLE' THEN
                    -- Authorizers are notified via system-generated alerts (FSD #299.9 etc.)
                    NOTIFY_ROLE(
                        p_company_id => v_company_id,
                        p_role_code  => 'CORP_AUTHORIZER',
                        p_title      => v_label || ' pending authorization',
                        p_message    => v_label || ' ' || v_ref_no
                                     || ' approved by Checker ' || v_checker_name
                                     || ' and is pending your authorization.',
                        p_ref_type   => p_request_type,
                        p_ref_id     => rec.REQ_ID
                    );
                END IF;

            EXCEPTION
                WHEN NO_DATA_FOUND THEN CONTINUE;
            END;
        END LOOP;

        COMMIT;

        IF v_count = 0 THEN
            p_out_message := 'No pending requests were processed.';
            RETURN;
        END IF;

        p_out_success := 'Y';
        IF p_decision = 'APPROVE' THEN
            p_out_message := v_count || ' request(s) approved.';
        ELSE
            p_out_message := v_count || ' request(s) rejected.';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CHECKER_DECIDE;

    -- ═══════════════════════════════════════════════════════════
    --  REQUEST_FEATURE_ACCESS_CHANGE   (FSD #325–#331)
    --  Maker → Checker only; no Checker = applied instantly.
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE REQUEST_FEATURE_ACCESS_CHANGE (
        p_company_id   IN  NUMBER,
        p_maker_ucid   IN  NUMBER,
        p_feature_code IN  VARCHAR2,
        p_folio_ids    IN  VARCHAR2,
        p_action       IN  VARCHAR2,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    ) IS
        v_maker_name  EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_has_checker VARCHAR2(1) := HAS_ACTIVE_CHECKER(p_company_id);
        v_count       NUMBER  := 0;
        v_feat_label  VARCHAR2(30);
    BEGIN
        p_out_success := 'N';

        IF p_feature_code NOT IN ('LOAN', 'WITHDRAWAL') THEN
            p_out_message := 'Invalid feature code.';
            RETURN;
        END IF;
        IF p_action NOT IN ('ADD', 'REMOVE') THEN
            p_out_message := 'Invalid action. Must be ADD or REMOVE.';
            RETURN;
        END IF;
        IF p_folio_ids IS NULL THEN
            p_out_message := 'Please select at least one employee';
            RETURN;
        END IF;

        v_feat_label := CASE p_feature_code WHEN 'LOAN' THEN 'Loan' ELSE 'Withdrawal' END;

        FOR rec IN (
            SELECT TO_NUMBER(COLUMN_VALUE) AS FOLIO_ID
              FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_folio_ids, ':'))
        ) LOOP
            DECLARE
                v_access_id NUMBER;
                v_emp_name  VARCHAR2(200) := GET_FOLIO_NAME(rec.FOLIO_ID);
            BEGIN
                IF p_action = 'ADD' THEN
                    MERGE INTO EPF_FEATURE_ACCESS fa
                    USING (SELECT p_company_id AS CID, rec.FOLIO_ID AS FID,
                                  p_feature_code AS FC FROM DUAL) d
                    ON (fa.COMPANY_ID = d.CID AND fa.FOLIO_ID = d.FID
                        AND fa.FEATURE_CODE = d.FC)
                    WHEN MATCHED THEN UPDATE SET
                        ACCESS_STATUS = CASE WHEN v_has_checker = 'Y'
                                             THEN 'PENDING_ADDITION' ELSE 'ENABLED' END,
                        MAKER_UCID = p_maker_ucid, MAKER_DATE = SYSDATE,
                        CHECKER_UCID = NULL, CHECKER_DATE = NULL
                        WHERE fa.ACCESS_STATUS != 'ENABLED'
                    WHEN NOT MATCHED THEN INSERT (
                        COMPANY_ID, FOLIO_ID, FEATURE_CODE, ACCESS_STATUS,
                        MAKER_UCID, MAKER_DATE
                    ) VALUES (
                        d.CID, d.FID, d.FC,
                        CASE WHEN v_has_checker = 'Y' THEN 'PENDING_ADDITION' ELSE 'ENABLED' END,
                        p_maker_ucid, SYSDATE
                    );
                ELSE  -- REMOVE
                    IF v_has_checker = 'Y' THEN
                        UPDATE EPF_FEATURE_ACCESS
                           SET ACCESS_STATUS = 'PENDING_DELETION',
                               MAKER_UCID = p_maker_ucid, MAKER_DATE = SYSDATE
                         WHERE COMPANY_ID   = p_company_id
                           AND FOLIO_ID     = rec.FOLIO_ID
                           AND FEATURE_CODE = p_feature_code
                           AND ACCESS_STATUS = 'ENABLED';
                    ELSE
                        DELETE FROM EPF_FEATURE_ACCESS
                         WHERE COMPANY_ID   = p_company_id
                           AND FOLIO_ID     = rec.FOLIO_ID
                           AND FEATURE_CODE = p_feature_code;
                    END IF;
                END IF;

                v_count := v_count + 1;

                BEGIN
                    SELECT ACCESS_ID INTO v_access_id
                      FROM EPF_FEATURE_ACCESS
                     WHERE COMPANY_ID = p_company_id
                       AND FOLIO_ID = rec.FOLIO_ID
                       AND FEATURE_CODE = p_feature_code;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_access_id := 0;
                END;

                NARRATE(
                    p_company_id  => p_company_id,
                    p_actor_ucid  => p_maker_ucid,
                    p_action_code => 'FEATURE_' || p_action || '_REQUESTED',
                    p_text        => CASE WHEN v_has_checker = 'Y'
                                          THEN v_feat_label || ' access '
                                            || LOWER(p_action) || 'ition request for '
                                            || v_emp_name || ' created by Maker ' || v_maker_name
                                          ELSE v_emp_name
                                            || CASE p_action WHEN 'ADD'
                                                    THEN ' added to ' ELSE ' removed from ' END
                                            || v_feat_label
                                            || ' List of Added Employees by Maker ' || v_maker_name
                                            || ' (no Checker exists)' END,
                    p_ref_type    => 'FEATURE',
                    p_ref_id      => v_access_id,
                    p_folio_id    => rec.FOLIO_ID,
                    p_page_name   => 'Settings – ' || v_feat_label || ' Settings'
                );

                IF v_has_checker = 'Y' THEN
                    NOTIFY_ROLE(
                        p_company_id => p_company_id,
                        p_role_code  => 'CORP_CHECKER',
                        p_title      => v_feat_label || ' access change pending approval',
                        p_message    => v_feat_label || ' access change for ' || v_emp_name
                                     || ' has been created by Maker ' || v_maker_name
                                     || ' and is pending your approval.',
                        p_ref_type   => 'FEATURE',
                        p_ref_id     => v_access_id
                    );
                END IF;
            END;
        END LOOP;

        COMMIT;

        p_out_success := 'Y';
        IF v_has_checker = 'Y' THEN
            p_out_message := v_count || ' change request(s) sent to the Checker for approval.';
        ELSE
            p_out_message := 'Changes have been saved.';   -- instant apply (FSD #4, #326)
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END REQUEST_FEATURE_ACCESS_CHANGE;

    -- ═══════════════════════════════════════════════════════════
    --  CHECKER_DECIDE_FEATURE_ACCESS   (FSD #326, #330)
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CHECKER_DECIDE_FEATURE_ACCESS (
        p_access_ids   IN  VARCHAR2,
        p_checker_ucid IN  NUMBER,
        p_decision     IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    ) IS
        v_checker_name EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_checker_ucid);
        v_count        NUMBER := 0;
    BEGIN
        p_out_success := 'N';

        IF p_decision NOT IN ('APPROVE', 'REJECT') THEN
            p_out_message := 'Invalid decision. Must be APPROVE or REJECT.';
            RETURN;
        END IF;
        IF p_decision = 'REJECT' AND TRIM(p_remarks) IS NULL THEN
            p_out_message := 'Remarks are required for rejection.';
            RETURN;
        END IF;
        IF p_access_ids IS NULL THEN
            p_out_message := 'Please select at least one request.';
            RETURN;
        END IF;

        FOR rec IN (
            SELECT TO_NUMBER(COLUMN_VALUE) AS ACCESS_ID
              FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_access_ids, ':'))
        ) LOOP
            DECLARE
                v_row      EPF_FEATURE_ACCESS%ROWTYPE;
                v_emp_name VARCHAR2(200);
                v_feat     VARCHAR2(30);
                v_change   VARCHAR2(20);
                v_text     VARCHAR2(2000);
            BEGIN
                SELECT * INTO v_row
                  FROM EPF_FEATURE_ACCESS
                 WHERE ACCESS_ID = rec.ACCESS_ID
                   AND ACCESS_STATUS IN ('PENDING_ADDITION', 'PENDING_DELETION');

                v_emp_name := GET_FOLIO_NAME(v_row.FOLIO_ID);
                v_feat     := CASE v_row.FEATURE_CODE WHEN 'LOAN' THEN 'Loan' ELSE 'Withdrawal' END;
                v_change   := CASE v_row.ACCESS_STATUS
                                  WHEN 'PENDING_ADDITION' THEN 'addition' ELSE 'deletion' END;

                IF p_decision = 'APPROVE' THEN
                    IF v_row.ACCESS_STATUS = 'PENDING_ADDITION' THEN
                        UPDATE EPF_FEATURE_ACCESS
                           SET ACCESS_STATUS = 'ENABLED',
                               CHECKER_UCID = p_checker_ucid, CHECKER_DATE = SYSDATE
                         WHERE ACCESS_ID = rec.ACCESS_ID;
                    ELSE
                        DELETE FROM EPF_FEATURE_ACCESS WHERE ACCESS_ID = rec.ACCESS_ID;
                    END IF;
                    v_text := v_feat || ' access ' || v_change || ' request for ' || v_emp_name
                           || ' approved by Checker ' || v_checker_name;
                ELSE
                    IF v_row.ACCESS_STATUS = 'PENDING_ADDITION' THEN
                        -- Rejected addition: employee is NOT added (FSD #326.3)
                        DELETE FROM EPF_FEATURE_ACCESS WHERE ACCESS_ID = rec.ACCESS_ID;
                    ELSE
                        -- Rejected deletion: access remains ENABLED
                        UPDATE EPF_FEATURE_ACCESS
                           SET ACCESS_STATUS = 'ENABLED',
                               CHECKER_UCID = p_checker_ucid, CHECKER_DATE = SYSDATE
                         WHERE ACCESS_ID = rec.ACCESS_ID;
                    END IF;
                    v_text := v_feat || ' access ' || v_change || ' request for ' || v_emp_name
                           || ' rejected by Checker ' || v_checker_name
                           || ' with remarks: ' || p_remarks;
                END IF;

                v_count := v_count + 1;

                NARRATE(
                    p_company_id  => v_row.COMPANY_ID,
                    p_actor_ucid  => p_checker_ucid,
                    p_action_code => 'FEATURE_CHECKER_' || p_decision,
                    p_text        => v_text,
                    p_ref_type    => 'FEATURE',
                    p_ref_id      => rec.ACCESS_ID,
                    p_folio_id    => v_row.FOLIO_ID,
                    p_page_name   => 'Settings – ' || v_feat || ' Settings'
                );

                IF p_decision = 'REJECT' AND v_row.MAKER_UCID IS NOT NULL THEN
                    NOTIFY_UCID(
                        p_company_id => v_row.COMPANY_ID,
                        p_ucid       => v_row.MAKER_UCID,
                        p_title      => v_feat || ' access change rejected',
                        p_message    => v_text || '.',
                        p_ref_type   => 'FEATURE',
                        p_ref_id     => rec.ACCESS_ID
                    );
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN CONTINUE;
            END;
        END LOOP;

        COMMIT;

        IF v_count = 0 THEN
            p_out_message := 'No pending requests were processed.';
            RETURN;
        END IF;

        p_out_success := 'Y';
        p_out_message := v_count || ' request(s) '
                      || CASE p_decision WHEN 'APPROVE' THEN 'approved.' ELSE 'rejected.' END;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CHECKER_DECIDE_FEATURE_ACCESS;

    -- ═══════════════════════════════════════════════════════════
    --  SAVE_REALLOC_GROUP   (FSD #286–#294)
    --  Create or edit a custom group.  Pending at Checker unless
    --  the company has no Checker (instant save).
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE SAVE_REALLOC_GROUP (
        p_company_id       IN  NUMBER,
        p_maker_ucid       IN  NUMBER,
        p_group_id         IN  NUMBER,
        p_group_name       IN  VARCHAR2,
        p_mm_limit         IN  NUMBER,
        p_debt_limit       IN  NUMBER,
        p_equity_limit     IN  NUMBER,
        p_add_folio_ids    IN  VARCHAR2 DEFAULT NULL,
        p_remove_folio_ids IN  VARCHAR2 DEFAULT NULL,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_group_id     OUT NUMBER
    ) IS
        v_maker_name  EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_maker_ucid);
        v_has_checker VARCHAR2(1) := HAS_ACTIVE_CHECKER(p_company_id);
        v_pend_sid    NUMBER  := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_auth_sid    NUMBER  := EPF_STATUS_PKG.GET_ID('REQUEST', 'AUTHORIZED');
        v_group_id    NUMBER  := p_group_id;
        v_is_default  VARCHAR2(1);
        v_is_new      BOOLEAN := (p_group_id IS NULL);
        v_member_stat VARCHAR2(20);
        v_json        CLOB;
    BEGIN
        p_out_success  := 'N';
        p_out_group_id := NULL;

        -- ── Limit validations (0–100, FSD #287) ────────────────
        IF p_mm_limit     NOT BETWEEN 0 AND 100
        OR p_debt_limit   NOT BETWEEN 0 AND 100
        OR p_equity_limit NOT BETWEEN 0 AND 100 THEN
            p_out_message := 'Maximum limits must be between 0 and 100.';
            RETURN;
        END IF;

        IF v_is_new THEN
            -- ── New group ──────────────────────────────────────
            INSERT INTO EPF_REALLOC_GROUPS (
                COMPANY_ID, GROUP_NAME, MM_LIMIT, DEBT_LIMIT, EQUITY_LIMIT,
                IS_DEFAULT, STATUS_ID, MAKER_UCID, MAKER_DATE
            ) VALUES (
                p_company_id, p_group_name, p_mm_limit, p_debt_limit, p_equity_limit,
                'N', CASE WHEN v_has_checker = 'Y' THEN v_pend_sid ELSE v_auth_sid END,
                p_maker_ucid, SYSDATE
            )
            RETURNING GROUP_ID INTO v_group_id;
        ELSE
            -- ── Edit: Default Group cannot be edited by Maker (FSD #287)
            SELECT NVL(IS_DEFAULT, 'N') INTO v_is_default
              FROM EPF_REALLOC_GROUPS
             WHERE GROUP_ID = v_group_id AND COMPANY_ID = p_company_id;

            IF v_is_default = 'Y' THEN
                p_out_message := 'Default Group can only be managed by AAML.';
                RETURN;
            END IF;

            IF v_has_checker = 'Y' THEN
                -- Stash the pending edit; old data stays live (FSD #334.2b)
                v_json := JSON_OBJECT(
                              'group_name'   VALUE p_group_name,
                              'mm_limit'     VALUE p_mm_limit,
                              'debt_limit'   VALUE p_debt_limit,
                              'equity_limit' VALUE p_equity_limit
                          );
                UPDATE EPF_REALLOC_GROUPS
                   SET STATUS_ID = v_pend_sid,
                       PENDING_CHANGES_JSON = v_json,
                       MAKER_UCID = p_maker_ucid, MAKER_DATE = SYSDATE,
                       CHECKER_UCID = NULL, CHECKER_DATE = NULL, CHECKER_REMARKS = NULL
                 WHERE GROUP_ID = v_group_id;
            ELSE
                UPDATE EPF_REALLOC_GROUPS
                   SET GROUP_NAME = p_group_name,
                       MM_LIMIT = p_mm_limit, DEBT_LIMIT = p_debt_limit,
                       EQUITY_LIMIT = p_equity_limit,
                       STATUS_ID = v_auth_sid, PENDING_CHANGES_JSON = NULL,
                       MAKER_UCID = p_maker_ucid, MAKER_DATE = SYSDATE
                 WHERE GROUP_ID = v_group_id;
            END IF;
        END IF;

        -- ── Member additions / removals ────────────────────────
        v_member_stat := CASE WHEN v_has_checker = 'Y' THEN 'PENDING_ADDITION' ELSE 'ENABLED' END;

        IF p_add_folio_ids IS NOT NULL THEN
            FOR rec IN (
                SELECT TO_NUMBER(COLUMN_VALUE) AS FOLIO_ID
                  FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_add_folio_ids, ':'))
            ) LOOP
                MERGE INTO EPF_REALLOC_GROUP_MEMBERS m
                USING (SELECT v_group_id AS GID, rec.FOLIO_ID AS FID FROM DUAL) d
                ON (m.GROUP_ID = d.GID AND m.FOLIO_ID = d.FID)
                WHEN MATCHED THEN UPDATE SET ACCESS_STATUS = v_member_stat
                    WHERE m.ACCESS_STATUS = 'PENDING_DELETION'
                WHEN NOT MATCHED THEN INSERT (GROUP_ID, FOLIO_ID, ACCESS_STATUS)
                VALUES (d.GID, d.FID, v_member_stat);
            END LOOP;
        END IF;

        IF p_remove_folio_ids IS NOT NULL THEN
            FOR rec IN (
                SELECT TO_NUMBER(COLUMN_VALUE) AS FOLIO_ID
                  FROM TABLE(APEX_STRING.SPLIT_NUMBERS(p_remove_folio_ids, ':'))
            ) LOOP
                IF v_has_checker = 'Y' THEN
                    UPDATE EPF_REALLOC_GROUP_MEMBERS
                       SET ACCESS_STATUS = 'PENDING_DELETION'
                     WHERE GROUP_ID = v_group_id AND FOLIO_ID = rec.FOLIO_ID
                       AND ACCESS_STATUS = 'ENABLED';
                ELSE
                    -- Removed members rejoin the Default Group automatically (FSD #294)
                    DELETE FROM EPF_REALLOC_GROUP_MEMBERS
                     WHERE GROUP_ID = v_group_id AND FOLIO_ID = rec.FOLIO_ID;
                END IF;
            END LOOP;
        END IF;

        COMMIT;

        NARRATE(
            p_company_id  => p_company_id,
            p_actor_ucid  => p_maker_ucid,
            p_action_code => CASE WHEN v_is_new THEN 'REALLOC_GROUP_CREATED'
                                  ELSE 'REALLOC_GROUP_EDITED' END,
            p_text        => 'Portfolio reallocation group ' || p_group_name
                          || CASE WHEN v_is_new THEN ' created' ELSE ' edited' END
                          || ' by Maker ' || v_maker_name
                          || CASE WHEN v_has_checker = 'N'
                                  THEN ' and saved (no Checker exists)' ELSE '' END,
            p_ref_type    => 'REALLOC',
            p_ref_id      => v_group_id,
            p_page_name   => 'Settings – Portfolio Reallocation'
        );

        IF v_has_checker = 'Y' THEN
            NOTIFY_ROLE(
                p_company_id => p_company_id,
                p_role_code  => 'CORP_CHECKER',
                p_title      => 'Portfolio reallocation group pending approval',
                p_message    => 'Group ' || p_group_name
                             || CASE WHEN v_is_new THEN ' (new)' ELSE ' (edited)' END
                             || ' by Maker ' || v_maker_name
                             || ' is pending your approval.',
                p_ref_type   => 'REALLOC',
                p_ref_id     => v_group_id
            );
        END IF;

        p_out_success  := 'Y';
        p_out_group_id := v_group_id;
        IF v_has_checker = 'Y' THEN
            p_out_message := 'Group has been sent to the Checker for approval.';
        ELSE
            p_out_message := 'Group has been saved.';
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Group not found for this company.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END SAVE_REALLOC_GROUP;

    -- ═══════════════════════════════════════════════════════════
    --  CHECKER_DECIDE_REALLOC_GROUP   (FSD #332–#335)
    --  Reject NEW group  = delete it entirely.
    --  Reject EDIT       = discard PENDING_CHANGES_JSON, keep old data.
    -- ═══════════════════════════════════════════════════════════
    PROCEDURE CHECKER_DECIDE_REALLOC_GROUP (
        p_group_id     IN  NUMBER,
        p_checker_ucid IN  NUMBER,
        p_decision     IN  VARCHAR2,
        p_remarks      IN  VARCHAR2 DEFAULT NULL,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2
    ) IS
        v_checker_name EPF_USERS.FULL_NAME%TYPE := GET_ACTOR_NAME(p_checker_ucid);
        v_pend_sid     NUMBER := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');
        v_auth_sid     NUMBER := EPF_STATUS_PKG.GET_ID('REQUEST', 'AUTHORIZED');
        v_grp          EPF_REALLOC_GROUPS%ROWTYPE;
        v_is_new       BOOLEAN;
        v_text         VARCHAR2(2000);
    BEGIN
        p_out_success := 'N';

        IF p_decision NOT IN ('APPROVE', 'REJECT') THEN
            p_out_message := 'Invalid decision. Must be APPROVE or REJECT.';
            RETURN;
        END IF;
        IF p_decision = 'REJECT' AND TRIM(p_remarks) IS NULL THEN
            p_out_message := 'Remarks are required for rejection.';
            RETURN;
        END IF;

        BEGIN
            SELECT * INTO v_grp
              FROM EPF_REALLOC_GROUPS
             WHERE GROUP_ID = p_group_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Group not found.';
                RETURN;
        END;

        IF v_grp.STATUS_ID != v_pend_sid THEN
            p_out_message := 'Group is not pending at Checker.';
            RETURN;
        END IF;

        -- New group = no pending-edit JSON (whole group is the request)
        v_is_new := (v_grp.PENDING_CHANGES_JSON IS NULL);

        IF p_decision = 'APPROVE' THEN
            IF NOT v_is_new THEN
                -- Apply pending edits from JSON
                UPDATE EPF_REALLOC_GROUPS
                   SET GROUP_NAME   = JSON_VALUE(PENDING_CHANGES_JSON, '$.group_name'),
                       MM_LIMIT     = TO_NUMBER(JSON_VALUE(PENDING_CHANGES_JSON, '$.mm_limit')),
                       DEBT_LIMIT   = TO_NUMBER(JSON_VALUE(PENDING_CHANGES_JSON, '$.debt_limit')),
                       EQUITY_LIMIT = TO_NUMBER(JSON_VALUE(PENDING_CHANGES_JSON, '$.equity_limit'))
                 WHERE GROUP_ID = p_group_id;
            END IF;

            UPDATE EPF_REALLOC_GROUPS
               SET STATUS_ID = v_auth_sid, PENDING_CHANGES_JSON = NULL,
                   CHECKER_UCID = p_checker_ucid, CHECKER_DATE = SYSDATE,
                   CHECKER_REMARKS = p_remarks
             WHERE GROUP_ID = p_group_id;

            -- Resolve member changes
            UPDATE EPF_REALLOC_GROUP_MEMBERS
               SET ACCESS_STATUS = 'ENABLED'
             WHERE GROUP_ID = p_group_id AND ACCESS_STATUS = 'PENDING_ADDITION';

            -- Removed members rejoin Default Group automatically (FSD #294)
            DELETE FROM EPF_REALLOC_GROUP_MEMBERS
             WHERE GROUP_ID = p_group_id AND ACCESS_STATUS = 'PENDING_DELETION';

            v_text := 'Portfolio reallocation group ' || v_grp.GROUP_NAME
                   || ' approved by Checker ' || v_checker_name;
        ELSE
            IF v_is_new THEN
                -- Rejected new group is never saved (FSD #334.2a)
                DELETE FROM EPF_REALLOC_GROUP_MEMBERS WHERE GROUP_ID = p_group_id;
                DELETE FROM EPF_REALLOC_GROUPS        WHERE GROUP_ID = p_group_id;
            ELSE
                -- Rejected edit: discard pending changes, keep old data (FSD #334.2b)
                UPDATE EPF_REALLOC_GROUPS
                   SET STATUS_ID = v_auth_sid, PENDING_CHANGES_JSON = NULL,
                       CHECKER_UCID = p_checker_ucid, CHECKER_DATE = SYSDATE,
                       CHECKER_REMARKS = p_remarks
                 WHERE GROUP_ID = p_group_id;

                DELETE FROM EPF_REALLOC_GROUP_MEMBERS
                 WHERE GROUP_ID = p_group_id AND ACCESS_STATUS = 'PENDING_ADDITION';

                UPDATE EPF_REALLOC_GROUP_MEMBERS
                   SET ACCESS_STATUS = 'ENABLED'
                 WHERE GROUP_ID = p_group_id AND ACCESS_STATUS = 'PENDING_DELETION';
            END IF;

            v_text := 'Portfolio reallocation group ' || v_grp.GROUP_NAME
                   || ' rejected by Checker ' || v_checker_name
                   || ' with remarks: ' || p_remarks;
        END IF;

        COMMIT;

        NARRATE(
            p_company_id  => v_grp.COMPANY_ID,
            p_actor_ucid  => p_checker_ucid,
            p_action_code => 'REALLOC_CHECKER_' || p_decision,
            p_text        => v_text,
            p_ref_type    => 'REALLOC',
            p_ref_id      => p_group_id,
            p_page_name   => 'Settings – Portfolio Reallocation'
        );

        IF p_decision = 'REJECT' AND v_grp.MAKER_UCID IS NOT NULL THEN
            NOTIFY_UCID(
                p_company_id => v_grp.COMPANY_ID,
                p_ucid       => v_grp.MAKER_UCID,
                p_title      => 'Portfolio reallocation group rejected',
                p_message    => v_text || '.',
                p_ref_type   => 'REALLOC',
                p_ref_id     => p_group_id
            );
        END IF;

        p_out_success := 'Y';
        p_out_message := CASE p_decision
                             WHEN 'APPROVE' THEN 'Group has been approved and saved.'
                             ELSE 'Group changes have been rejected.'
                         END;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CHECKER_DECIDE_REALLOC_GROUP;

    -- ═══════════════════════════════════════════════════════════
    --  GET_REQUEST_HISTORY
    --  History narrations specific to one request, newest first.
    --  Matches the '[Ref <REF_TYPE>-<REF_ID>]' tag written by NARRATE.
    -- ═══════════════════════════════════════════════════════════
    FUNCTION GET_REQUEST_HISTORY (
        p_ref_type IN VARCHAR2,
        p_ref_id   IN NUMBER
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT
                al.REF_NO,
                TO_CHAR(al.ACTION_DATE, 'DD-Mon-YY')  AS ACTION_DATE_FMT,
                TO_CHAR(al.ACTION_DATE, 'HH:MI am')   AS ACTION_TIME_FMT,
                al.ACTION_DATE,
                al.ACTION_CODE,
                al.ACTION_DETAIL
              FROM EPF_ACTIVITY_LOGS al
             WHERE al.ACTION_DETAIL LIKE '%[Ref ' || p_ref_type || '-' || p_ref_id || ']%'
             ORDER BY al.ACTION_DATE DESC, al.LOG_ID DESC;
        RETURN v_cur;
    END GET_REQUEST_HISTORY;

END EPF_CORP_TXN_PKG;
/

-- ============================================================
-- End of 12_epf_corp_txn_pkg.sql
-- ============================================================
