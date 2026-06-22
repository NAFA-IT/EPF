-- ============================================================
-- FILE: /home/user/EPF/db/16_epf_employee_pkg.sql
-- EPF PORTAL  –  Employee Self-Service Package (Spec + Body)
-- EPF_EMPLOYEE_PKG  –  Employee portal functions
-- FSD validations: #346-372 (Employee Dashboard, Account
--   Statement, Certificates, Portfolio Reallocation,
--   Loan/Withdrawal Requests).
-- Depends on: 11_corp_txn_ddl.sql, 13_authorizer_employee_ddl.sql,
--             14_epf_email_pkg_addons.sql, EPF_STATUS_PKG,
--             EPF_AUTH_PKG.
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_EMPLOYEE_PKG AS
-- ============================================================
--  EPF_EMPLOYEE_PKG  –  Employee self-service operations
-- ============================================================

    -- ── Dashboard: Fund Overview data (FSD #346-350) ────────────
    -- Returns SYS_REFCURSOR with sub-fund rows for the employee folio:
    --   FUND_NAME, SUBFUND_NAME, UNITS, NAV, CURRENT_BALANCE,
    --   NET_INVESTMENT, PROFIT_LOSS
    -- Date filter optional; both NULL = all time.
    FUNCTION GET_DASHBOARD_DATA (
        p_folio_id  IN NUMBER,
        p_date_from IN DATE DEFAULT NULL,
        p_date_to   IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- ── Account Statement (FSD #351-352) ────────────────────────
    -- Returns SYS_REFCURSOR of transaction rows; logs to
    -- EPF_ACCOUNT_STMT_LOG (DELIVERY = 'VIEW').
    FUNCTION GET_ACCOUNT_STATEMENT (
        p_folio_id   IN NUMBER,
        p_period_type IN VARCHAR2,   -- LAST30 | LAST90 | INCEPTION | DATE_RANGE
        p_date_from  IN DATE,
        p_date_to    IN DATE
    ) RETURN SYS_REFCURSOR;

    -- ── Account Statement via Email (FSD #353, email #21) ───────
    PROCEDURE REQUEST_ACCOUNT_STATEMENT_EMAIL (
        p_user_id     IN  NUMBER,
        p_folio_id    IN  NUMBER,
        p_fund_id     IN  NUMBER,
        p_date_from   IN  DATE,
        p_date_to     IN  DATE,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    -- ── Tax Certificate (FSD #354-355) ──────────────────────────
    -- Builds an HTML certificate stub; actual values pending
    -- DFN data feed integration.
    PROCEDURE GENERATE_TAX_CERTIFICATE (
        p_user_id     IN  NUMBER,
        p_folio_id    IN  NUMBER,
        p_tax_year    IN  VARCHAR2,   -- e.g. '2024-25'
        p_out_html    OUT CLOB,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    -- ── Portfolio Reallocation (FSD #356-358, #372) ─────────────
    -- Validates limits, employee membership, and inserts
    -- EPF_REALLOC_REQUESTS.
    PROCEDURE CREATE_PORTFOLIO_REALLOC (
        p_folio_id    IN  NUMBER,
        p_group_id    IN  NUMBER,
        p_mm_pct      IN  NUMBER,
        p_debt_pct    IN  NUMBER,
        p_equity_pct  IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    );

    -- ── Loan Request by Employee (FSD #359-364) ─────────────────
    -- Creates PENDING_MAKER status loan in EPF_LOAN_REQUESTS.
    -- Narration: [name] (employee): Created loan request on DD-Mon-YY, at HH:MI am
    -- Notifies Maker on completion.
    PROCEDURE CREATE_LOAN_REQUEST (
        p_folio_id          IN  NUMBER,
        p_amount            IN  NUMBER,
        p_instalment_months IN  NUMBER,
        p_payment_mode      IN  VARCHAR2,   -- CHEQUE | ONLINE
        p_out_success       OUT VARCHAR2,
        p_out_message       OUT VARCHAR2,
        p_out_loan_id       OUT NUMBER
    );

    -- ── Withdrawal Request by Employee (FSD #365-369) ───────────
    -- Creates PENDING_MAKER status withdrawal in EPF_WITHDRAWAL_REQUESTS.
    PROCEDURE CREATE_WITHDRAWAL_REQUEST (
        p_folio_id     IN  NUMBER,
        p_amount       IN  NUMBER,    -- NULL when FULL
        p_wd_type      IN  VARCHAR2,  -- PARTIAL | FULL
        p_reason       IN  VARCHAR2 DEFAULT NULL,
        p_payment_mode IN  VARCHAR2,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_wd_id    OUT NUMBER
    );

END EPF_EMPLOYEE_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_EMPLOYEE_PKG AS
-- ============================================================
--  EPF_EMPLOYEE_PKG  –  Body
-- ============================================================

    -- ═══════════════════════════════════════════════════════════
    --  PRIVATE HELPERS
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────
    --  GET_FOLIO_INFO
    --  Returns key folio fields for validation and display.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE GET_FOLIO_INFO (
        p_folio_id    IN  NUMBER,
        p_company_id  OUT NUMBER,
        p_fund_id     OUT NUMBER,
        p_folio_no    OUT VARCHAR2,
        p_lien_marked OUT VARCHAR2,
        p_is_disabled OUT VARCHAR2,
        p_noc_issued  OUT VARCHAR2,
        p_user_id     OUT NUMBER
    ) IS
    BEGIN
        SELECT f.COMPANY_ID,
               (SELECT ffm.FUND_ID FROM EPF_FOLIO_FUND_MAPPING ffm
                 WHERE ffm.FOLIO_ID = f.FOLIO_ID AND ROWNUM = 1),
               f.FOLIO_NUMBER,
               NVL(f.LIEN_MARKED,'N'),
               NVL(f.IS_DISABLED,'N'),
               NVL(f.NOC_ISSUED,'N'),
               uc.USER_ID
          INTO p_company_id, p_fund_id, p_folio_no,
               p_lien_marked, p_is_disabled, p_noc_issued,
               p_user_id
          FROM EPF_FOLIOS         f
          JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
         WHERE f.FOLIO_ID = p_folio_id
           AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_company_id  := NULL;
            p_fund_id     := NULL;
            p_folio_no    := NULL;
            p_lien_marked := 'N';
            p_is_disabled := 'N';
            p_noc_issued  := 'N';
            p_user_id     := NULL;
    END GET_FOLIO_INFO;

    -- ─────────────────────────────────────────────────────────
    --  GET_EMPLOYEE_NAME
    --  Returns the employee's full name from their folio.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_EMPLOYEE_NAME (
        p_folio_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name VARCHAR2(200);
    BEGIN
        SELECT u.FULL_NAME
          INTO v_name
          FROM EPF_FOLIOS         f
          JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
          JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
         WHERE f.FOLIO_ID = p_folio_id
           AND ROWNUM = 1;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'Employee';
    END GET_EMPLOYEE_NAME;

    -- ─────────────────────────────────────────────────────────
    --  GET_MAKER_UCID_FOR_COMPANY
    --  Returns the first active CORP_MAKER USER_COMPANY_ID
    --  for a company (to notify Maker of employee requests).
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_MAKER_UCID_FOR_COMPANY (
        p_company_id IN NUMBER
    ) RETURN NUMBER IS
        v_ucid NUMBER;
    BEGIN
        SELECT uc.USER_COMPANY_ID
          INTO v_ucid
          FROM EPF_USER_COMPANIES  uc
          JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
          JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
         WHERE uc.COMPANY_ID = p_company_id
           AND ucr.IS_ACTIVE  = 'Y'
           AND r.ROLE_CODE    = 'CORP_MAKER'
           AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE'
           AND ROWNUM = 1;
        RETURN v_ucid;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END GET_MAKER_UCID_FOR_COMPANY;

    -- ─────────────────────────────────────────────────────────
    --  NARRATE_EMPLOYEE
    --  Log an activity narration for an employee action.
    --  PRAGMA AUTONOMOUS_TRANSACTION.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE NARRATE_EMPLOYEE (
        p_company_id  IN NUMBER,
        p_user_id     IN NUMBER,
        p_action_code IN VARCHAR2,
        p_narration   IN VARCHAR2,
        p_ref_type    IN VARCHAR2,
        p_ref_id      IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO EPF_ACTIVITY_LOGS (
            COMPANY_ID, USER_ID, ACTION_CODE, ACTION_DETAIL, ACTION_DATE
        ) VALUES (
            p_company_id, p_user_id, p_action_code,
            p_narration || ' [Ref ' || p_ref_type || '-' || p_ref_id || ']',
            SYSDATE
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END NARRATE_EMPLOYEE;

    -- ─────────────────────────────────────────────────────────
    --  NOTIFY_USER_ID
    --  Insert a notification for a specific USER_ID.
    --  PRAGMA AUTONOMOUS_TRANSACTION.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE NOTIFY_USER_ID (
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
            COMPANY_ID, USER_ID, TITLE, MESSAGE, REF_TYPE, REF_ID
        ) VALUES (
            p_company_id, p_user_id, p_title, p_message, p_ref_type, p_ref_id
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END NOTIFY_USER_ID;

    -- ─────────────────────────────────────────────────────────
    --  COMPUTE_DATE_RANGE
    --  Converts a PERIOD_TYPE + optional dates into FROM/TO.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE COMPUTE_DATE_RANGE (
        p_period_type  IN  VARCHAR2,
        p_date_from_in IN  DATE,
        p_date_to_in   IN  DATE,
        p_date_from    OUT DATE,
        p_date_to      OUT DATE
    ) IS
    BEGIN
        p_date_to := TRUNC(SYSDATE);
        CASE p_period_type
            WHEN 'LAST30'      THEN p_date_from := TRUNC(SYSDATE) - 30;
            WHEN 'LAST90'      THEN p_date_from := TRUNC(SYSDATE) - 90;
            WHEN 'INCEPTION'   THEN p_date_from := DATE '1900-01-01';
            WHEN 'DATE_RANGE'  THEN
                p_date_from := NVL(TRUNC(p_date_from_in), TRUNC(SYSDATE) - 30);
                p_date_to   := NVL(TRUNC(p_date_to_in),   TRUNC(SYSDATE));
            ELSE
                p_date_from := TRUNC(SYSDATE) - 30;
        END CASE;
    END COMPUTE_DATE_RANGE;

    -- ═══════════════════════════════════════════════════════════
    --  PUBLIC PROCEDURES
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────
    --  GET_DASHBOARD_DATA  –  FSD #346-350
    --  Returns fund-level aggregates for employee's own folio.
    --  Columns: FUND_NAME, SUBFUND_NAME, UNITS, NAV,
    --           CURRENT_BALANCE, NET_INVESTMENT, PROFIT_LOSS
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_DASHBOARD_DATA (
        p_folio_id  IN NUMBER,
        p_date_from IN DATE DEFAULT NULL,
        p_date_to   IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cur         SYS_REFCURSOR;
        v_from        DATE := NVL(TRUNC(p_date_from), DATE '1900-01-01');
        v_to          DATE := NVL(TRUNC(p_date_to),   TRUNC(SYSDATE));
    BEGIN
        -- Fund overview for an employee's folio: sub-fund breakdown
        -- The actual columns (UNITS, NAV, etc.) depend on the DFN data feed
        -- tables (EPF_FOLIO_FUND_MAPPING, EPF_FUNDS, etc.).
        -- This query is a structural stub referencing those tables.
        -- EPF_FOLIO_FUND_MAPPING is a mapping table only (FOLIO_ID, FUND_ID).
        -- NAV/units/balance data comes from the DFN data feed; stub with 0.
        OPEN v_cur FOR
            SELECT f.FUND_NAME,
                   'TOTAL'  AS SUBFUND_NAME,
                   0        AS UNITS,
                   0        AS NAV,
                   0        AS CURRENT_BALANCE,
                   0        AS NET_INVESTMENT,
                   0        AS PROFIT_LOSS
              FROM EPF_FOLIO_FUND_MAPPING ffm
              JOIN EPF_FUNDS              f   ON f.FUND_ID = ffm.FUND_ID
             WHERE ffm.FOLIO_ID = p_folio_id
             ORDER BY f.FUND_NAME;
        RETURN v_cur;
    END GET_DASHBOARD_DATA;

    -- ─────────────────────────────────────────────────────────
    --  GET_ACCOUNT_STATEMENT  –  FSD #351-352
    --  Returns transaction rows for the folio/period.
    --  Logs to EPF_ACCOUNT_STMT_LOG (DELIVERY = 'VIEW').
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_ACCOUNT_STATEMENT (
        p_folio_id    IN NUMBER,
        p_period_type IN VARCHAR2,
        p_date_from   IN DATE,
        p_date_to     IN DATE
    ) RETURN SYS_REFCURSOR IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_cur         SYS_REFCURSOR;
        v_from        DATE;
        v_to          DATE;
        v_company_id  NUMBER;
        v_user_id     NUMBER;
        v_fund_id     NUMBER;
        v_folio_no    VARCHAR2(30);
        v_lien        VARCHAR2(1);
        v_dis         VARCHAR2(1);
        v_noc         VARCHAR2(1);
    BEGIN
        COMPUTE_DATE_RANGE(p_period_type, p_date_from, p_date_to, v_from, v_to);
        GET_FOLIO_INFO(p_folio_id, v_company_id, v_fund_id, v_folio_no,
                       v_lien, v_dis, v_noc, v_user_id);

        -- Log the statement view
        BEGIN
            INSERT INTO EPF_ACCOUNT_STMT_LOG (
                FOLIO_ID, USER_ID, PERIOD_TYPE,
                DATE_FROM, DATE_TO, DELIVERY
            ) VALUES (
                p_folio_id, v_user_id, p_period_type,
                v_from, v_to, 'VIEW'
            );
            COMMIT;
        EXCEPTION
            WHEN OTHERS THEN ROLLBACK;
        END;

        -- Transaction query: joins EPF_LOAN_SCHEDULE, EPF_LOAN_REQUESTS,
        -- EPF_WITHDRAWAL_REQUESTS and EPF_CONTRIB_BATCH_ROWS for the folio.
        -- This is a structural query referencing existing tables.
        OPEN v_cur FOR
            SELECT 'LOAN_REPAYMENT'      AS TXN_TYPE,
                   ls.DUE_DATE           AS TXN_DATE,
                   ls.TOTAL_DUE          AS AMOUNT,
                   lr.LOAN_NO            AS REF_NO,
                   lr.INTEREST_RATE      AS NAV,
                   NULL                  AS UNITS,
                   ls.PRINCIPAL          AS EMPLOYER_CONTRIBUTION,
                   ls.INTEREST           AS EMPLOYEE_CONTRIBUTION,
                   0                     AS PROFIT,
                   ls.TOTAL_DUE          AS LOAN_REPAYMENT,
                   0                     AS WITHDRAWAL,
                   NULL                  AS LOAN_OUTSTANDING
              FROM EPF_LOAN_SCHEDULE  ls
              JOIN EPF_LOAN_REQUESTS  lr ON lr.LOAN_ID  = ls.LOAN_ID
             WHERE lr.FOLIO_ID  = p_folio_id
               AND ls.DUE_DATE BETWEEN v_from AND v_to
               AND ls.PAID_YN = 'Y'
            UNION ALL
            SELECT 'WITHDRAWAL'           AS TXN_TYPE,
                   wr.MAKER_DATE          AS TXN_DATE,
                   NVL(wr.AMOUNT, 0)      AS AMOUNT,
                   wr.WD_NO               AS REF_NO,
                   NULL, NULL,
                   0, 0, 0, 0,
                   NVL(wr.AMOUNT, 0)      AS WITHDRAWAL,
                   NULL
              FROM EPF_WITHDRAWAL_REQUESTS wr
             WHERE wr.FOLIO_ID   = p_folio_id
               AND EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID) IN ('AUTHORIZED','COMPLETED')
               AND wr.MAKER_DATE BETWEEN v_from AND v_to
            UNION ALL
            SELECT 'CONTRIBUTION'           AS TXN_TYPE,
                   cb.MAKER_DATE            AS TXN_DATE,
                   cbr.TOTAL_AMOUNT         AS AMOUNT,
                   cb.BATCH_NO              AS REF_NO,
                   NULL, NULL,
                   cbr.EMPLOYER_AMOUNT      AS EMPLOYER_CONTRIBUTION,
                   cbr.EMPLOYEE_AMOUNT      AS EMPLOYEE_CONTRIBUTION,
                   0, 0, 0, NULL
              FROM EPF_CONTRIB_BATCH_ROWS cbr
              JOIN EPF_CONTRIB_BATCHES   cb  ON cb.BATCH_ID = cbr.BATCH_ID
             WHERE cbr.FOLIO_ID   = p_folio_id
               AND EPF_STATUS_PKG.GET_CODE(cb.STATUS_ID) IN ('AUTHORIZED','COMPLETED')
               AND cb.MAKER_DATE  BETWEEN v_from AND v_to
             ORDER BY TXN_DATE ASC;
        RETURN v_cur;
    END GET_ACCOUNT_STATEMENT;

    -- ─────────────────────────────────────────────────────────
    --  REQUEST_ACCOUNT_STATEMENT_EMAIL  –  FSD #353, email #21
    -- ─────────────────────────────────────────────────────────
    PROCEDURE REQUEST_ACCOUNT_STATEMENT_EMAIL (
        p_user_id     IN  NUMBER,
        p_folio_id    IN  NUMBER,
        p_fund_id     IN  NUMBER,
        p_date_from   IN  DATE,
        p_date_to     IN  DATE,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_folio_no   VARCHAR2(50);
        v_fund_name  VARCHAR2(200);
        v_company_id NUMBER;
        v_dummy_id   NUMBER;
        v_lien       VARCHAR2(1);
        v_dis        VARCHAR2(1);
        v_noc        VARCHAR2(1);
        v_uid        NUMBER;
    BEGIN
        p_out_success := 'N';

        -- Get folio number
        BEGIN
            SELECT FOLIO_NUMBER INTO v_folio_no
              FROM EPF_FOLIOS WHERE FOLIO_ID = p_folio_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Folio not found.';
                RETURN;
        END;

        -- Get fund name
        BEGIN
            SELECT FUND_NAME INTO v_fund_name
              FROM EPF_FUNDS WHERE FUND_ID = p_fund_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_fund_name := 'EPF Fund';
        END;

        GET_FOLIO_INFO(p_folio_id, v_company_id, v_dummy_id, v_folio_no,
                       v_lien, v_dis, v_noc, v_uid);

        -- Log request
        BEGIN
            INSERT INTO EPF_ACCOUNT_STMT_LOG (
                FOLIO_ID, USER_ID, PERIOD_TYPE,
                DATE_FROM, DATE_TO, DELIVERY
            ) VALUES (
                p_folio_id, p_user_id, 'DATE_RANGE',
                TRUNC(p_date_from), TRUNC(p_date_to), 'EMAIL'
            );
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

        -- Send email #21 (attachment = NULL stub; actual PDF pending DFN feed)
        EPF_EMAIL_PKG.SEND_ACCOUNT_STATEMENT_EMAIL(
            p_employee_user_id => p_user_id,
            p_folio            => v_folio_no,
            p_fund_name        => v_fund_name,
            p_date_from        => TRUNC(p_date_from),
            p_date_to          => TRUNC(p_date_to),
            p_attachment       => NULL
        );

        p_out_success := 'Y';
        p_out_message := 'Account statement has been emailed to your registered email address.';
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Unexpected error in REQUEST_ACCOUNT_STATEMENT_EMAIL: ' || SQLERRM;
    END REQUEST_ACCOUNT_STATEMENT_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  GENERATE_TAX_CERTIFICATE  –  FSD #354-355
    --  Builds styled HTML certificate for the given tax year.
    --  Pending full DFN data feed integration — stub values used.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE GENERATE_TAX_CERTIFICATE (
        p_user_id     IN  NUMBER,
        p_folio_id    IN  NUMBER,
        p_tax_year    IN  VARCHAR2,
        p_out_html    OUT CLOB,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_folio_no     VARCHAR2(50);
        v_emp_name     VARCHAR2(200);
        v_fund_name    VARCHAR2(200);
        v_company_name VARCHAR2(400);
        v_cnic         VARCHAR2(20);
        v_company_id   NUMBER;
        v_fund_id      NUMBER;
        v_lien         VARCHAR2(1);
        v_dis          VARCHAR2(1);
        v_noc          VARCHAR2(1);
        v_user_id_f    NUMBER;
        v_content      CLOB;
    BEGIN
        p_out_success := 'N';

        -- Resolve folio details
        GET_FOLIO_INFO(p_folio_id, v_company_id, v_fund_id, v_folio_no,
                       v_lien, v_dis, v_noc, v_user_id_f);

        IF v_company_id IS NULL THEN
            p_out_message := 'Folio not found.';
            RETURN;
        END IF;

        v_emp_name := GET_EMPLOYEE_NAME(p_folio_id);

        BEGIN
            SELECT FUND_NAME INTO v_fund_name FROM EPF_FUNDS WHERE FUND_ID = v_fund_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_fund_name := 'EPF Fund';
        END;

        BEGIN
            SELECT COMPANY_NAME INTO v_company_name FROM EPF_COMPANIES WHERE COMPANY_ID = v_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_company_name := 'Employer';
        END;

        BEGIN
            SELECT u.CNIC INTO v_cnic
              FROM EPF_USER_COMPANIES uc
              JOIN EPF_USERS          u  ON u.USER_ID = uc.USER_ID
             WHERE uc.FOLIO_ID = p_folio_id
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_cnic := 'N/A';
        END;

        -- Build certificate HTML (Alfalah Investments letterhead style)
        v_content :=
            '<div style="border:2px solid #003087;border-radius:8px;padding:32px;'
         || 'font-family:Arial,sans-serif;max-width:800px;margin:0 auto">'
         -- Header
         || '<div style="text-align:center;border-bottom:2px solid #003087;padding-bottom:20px;margin-bottom:24px">'
         || '<h1 style="color:#003087;font-size:24px;margin:0">Alfalah Investments Management Limited</h1>'
         || '<p style="color:#666;font-size:13px;margin:4px 0">Dedicated Employee Pension Fund Platform</p>'
         || '<h2 style="color:#333;font-size:18px;margin:16px 0 0">GENERAL TAX CERTIFICATE</h2>'
         || '<p style="color:#003087;font-size:15px;font-weight:bold;margin:4px 0">'
         || 'Tax Year: ' || p_tax_year || '</p>'
         || '</div>'
         -- Certificate details
         || '<table style="width:100%;border-collapse:collapse;margin-bottom:24px">'
         || '<tr><td style="padding:10px;background:#f5f5f5;font-weight:bold;border:1px solid #ddd;width:35%">'
         || 'Employee Name</td><td style="padding:10px;border:1px solid #ddd">' || v_emp_name || '</td></tr>'
         || '<tr><td style="padding:10px;background:#f5f5f5;font-weight:bold;border:1px solid #ddd">'
         || 'CNIC / NICOP</td><td style="padding:10px;border:1px solid #ddd">' || v_cnic || '</td></tr>'
         || '<tr><td style="padding:10px;background:#f5f5f5;font-weight:bold;border:1px solid #ddd">'
         || 'Folio Number</td><td style="padding:10px;border:1px solid #ddd">' || v_folio_no || '</td></tr>'
         || '<tr><td style="padding:10px;background:#f5f5f5;font-weight:bold;border:1px solid #ddd">'
         || 'Fund Name</td><td style="padding:10px;border:1px solid #ddd">' || v_fund_name || '</td></tr>'
         || '<tr><td style="padding:10px;background:#f5f5f5;font-weight:bold;border:1px solid #ddd">'
         || 'Employer / Company</td><td style="padding:10px;border:1px solid #ddd">' || v_company_name || '</td></tr>'
         || '</table>'
         -- Summary section (stub — pending DFN data feed)
         || '<div style="background:#e8f0fe;border:1px solid #003087;border-radius:4px;padding:16px;margin-bottom:24px">'
         || '<h3 style="color:#003087;margin:0 0 12px">Tax Year Summary – ' || p_tax_year || '</h3>'
         || '<table style="width:100%;border-collapse:collapse">'
         || '<tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #ccc;width:50%">'
         || 'Total Employer Contributions</td>'
         || '<td style="padding:8px;border-bottom:1px solid #ccc;text-align:right">'
         || 'PKR [Pending DFN Data]</td></tr>'
         || '<tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #ccc">'
         || 'Total Employee Contributions</td>'
         || '<td style="padding:8px;border-bottom:1px solid #ccc;text-align:right">'
         || 'PKR [Pending DFN Data]</td></tr>'
         || '<tr><td style="padding:8px;font-weight:bold;border-bottom:1px solid #ccc">'
         || 'Profit / Return Earned</td>'
         || '<td style="padding:8px;border-bottom:1px solid #ccc;text-align:right">'
         || 'PKR [Pending DFN Data]</td></tr>'
         || '<tr style="background:#e8f5e9"><td style="padding:8px;font-weight:bold">'
         || 'Closing Balance (Year End)</td>'
         || '<td style="padding:8px;text-align:right;font-weight:bold">'
         || 'PKR [Pending DFN Data]</td></tr>'
         || '</table>'
         || '</div>'
         -- Note
         || '<p style="font-size:12px;color:#888;font-style:italic">'
         || 'Note: This certificate is generated as at '
         || TO_CHAR(SYSDATE, 'DD-Mon-YYYY HH:MI AM')
         || '. Values will be updated once DFN data feed integration is complete.</p>'
         -- Footer
         || '<div style="border-top:2px solid #003087;margin-top:24px;padding-top:16px;text-align:center">'
         || '<p style="font-size:12px;color:#666">'
         || 'Alfalah Investments Management Limited &bull; EPF Platform &bull; '
         || 'This is a computer-generated document.</p>'
         || '</div>'
         || '</div>';

        p_out_html    := v_content;
        p_out_success := 'Y';
        p_out_message := 'Tax certificate generated for tax year ' || p_tax_year || '.';
    EXCEPTION
        WHEN OTHERS THEN
            p_out_success := 'N';
            p_out_message := 'Unexpected error in GENERATE_TAX_CERTIFICATE: ' || SQLERRM;
    END GENERATE_TAX_CERTIFICATE;

    -- ─────────────────────────────────────────────────────────
    --  CREATE_PORTFOLIO_REALLOC  –  FSD #356-358, #372
    --  Validates percentages, group membership, max limits.
    --  Inserts EPF_REALLOC_REQUESTS.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE CREATE_PORTFOLIO_REALLOC (
        p_folio_id    IN  NUMBER,
        p_group_id    IN  NUMBER,
        p_mm_pct      IN  NUMBER,
        p_debt_pct    IN  NUMBER,
        p_equity_pct  IN  NUMBER,
        p_out_success OUT VARCHAR2,
        p_out_message OUT VARCHAR2
    ) IS
        v_company_id  NUMBER;
        v_fund_id     NUMBER;
        v_folio_no    VARCHAR2(50);
        v_lien        VARCHAR2(1);
        v_dis         VARCHAR2(1);
        v_noc         VARCHAR2(1);
        v_user_id     NUMBER;
        v_total_pct   NUMBER;
        v_mm_limit    NUMBER;
        v_debt_limit  NUMBER;
        v_eq_limit    NUMBER;
        v_mem_status  VARCHAR2(20);
    BEGIN
        p_out_success := 'N';

        -- Validate total = 100%
        v_total_pct := NVL(p_mm_pct,0) + NVL(p_debt_pct,0) + NVL(p_equity_pct,0);
        IF v_total_pct != 100 THEN
            p_out_message := 'Total allocation must equal 100%. Current total: ' || v_total_pct || '%.';
            RETURN;
        END IF;

        -- Validate individual percentages 0-100
        IF p_mm_pct    < 0 OR p_mm_pct    > 100 THEN p_out_message := 'Money Market % must be between 0 and 100.'; RETURN; END IF;
        IF p_debt_pct  < 0 OR p_debt_pct  > 100 THEN p_out_message := 'Debt % must be between 0 and 100.'; RETURN; END IF;
        IF p_equity_pct < 0 OR p_equity_pct > 100 THEN p_out_message := 'Equity % must be between 0 and 100.'; RETURN; END IF;

        GET_FOLIO_INFO(p_folio_id, v_company_id, v_fund_id, v_folio_no,
                       v_lien, v_dis, v_noc, v_user_id);

        IF v_company_id IS NULL THEN
            p_out_message := 'Folio not found.';
            RETURN;
        END IF;
        IF v_dis = 'Y' THEN
            p_out_message := 'Your account has been disabled. Portfolio reallocation is not available.';
            RETURN;
        END IF;

        -- Check employee is in the group with ENABLED status (FSD #356)
        BEGIN
            SELECT ACCESS_STATUS INTO v_mem_status
              FROM EPF_REALLOC_GROUP_MEMBERS
             WHERE GROUP_ID = p_group_id
               AND FOLIO_ID = p_folio_id;
            IF v_mem_status != 'ENABLED' THEN
                p_out_message := 'Portfolio Reallocation feature is not enabled for your account.';
                RETURN;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'You are not a member of the specified reallocation group.';
                RETURN;
        END;

        -- Fetch group max limits and validate (FSD #356-357)
        BEGIN
            SELECT MM_LIMIT, DEBT_LIMIT, EQUITY_LIMIT
              INTO v_mm_limit, v_debt_limit, v_eq_limit
              FROM EPF_REALLOC_GROUPS
             WHERE GROUP_ID = p_group_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Reallocation group not found.';
                RETURN;
        END;

        IF v_mm_limit IS NOT NULL AND p_mm_pct > v_mm_limit THEN
            p_out_message := 'Money Market allocation (' || p_mm_pct || '%) exceeds the allowed maximum ('
                          || v_mm_limit || '%).';
            RETURN;
        END IF;
        IF v_debt_limit IS NOT NULL AND p_debt_pct > v_debt_limit THEN
            p_out_message := 'Debt allocation (' || p_debt_pct || '%) exceeds the allowed maximum ('
                          || v_debt_limit || '%).';
            RETURN;
        END IF;
        IF v_eq_limit IS NOT NULL AND p_equity_pct > v_eq_limit THEN
            p_out_message := 'Equity allocation (' || p_equity_pct || '%) exceeds the allowed maximum ('
                          || v_eq_limit || '%).';
            RETURN;
        END IF;

        -- Insert reallocation request
        INSERT INTO EPF_REALLOC_REQUESTS (
            COMPANY_ID, FOLIO_ID, GROUP_ID,
            NEW_MM_PCT, NEW_DEBT_PCT, NEW_EQUITY_PCT,
            STATUS, REQUEST_DATE
        ) VALUES (
            v_company_id, p_folio_id, p_group_id,
            p_mm_pct, p_debt_pct, p_equity_pct,
            'PENDING', SYSDATE
        );

        -- Log activity
        NARRATE_EMPLOYEE(
            p_company_id  => v_company_id,
            p_user_id     => v_user_id,
            p_action_code => 'EMPLOYEE_REALLOC',
            p_narration   => GET_EMPLOYEE_NAME(p_folio_id)
                          || ' (employee): Submitted portfolio reallocation request on '
                          || TO_CHAR(SYSDATE,'DD-Mon-YY') || ', at '
                          || TO_CHAR(SYSDATE,'HH:MI am')
                          || ' (MM: ' || p_mm_pct || '%, Debt: ' || p_debt_pct
                          || '%, Equity: ' || p_equity_pct || '%)',
            p_ref_type    => 'REALLOC',
            p_ref_id      => p_folio_id
        );

        p_out_success := 'Y';
        p_out_message := 'Portfolio reallocation request submitted. It will be processed at day end by DFN.';
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Unexpected error in CREATE_PORTFOLIO_REALLOC: ' || SQLERRM;
    END CREATE_PORTFOLIO_REALLOC;

    -- ─────────────────────────────────────────────────────────
    --  CREATE_LOAN_REQUEST  –  FSD #359-364
    --  Employee creates loan request → PENDING_MAKER status.
    --  Narration 3.1: [employee name] (employee): Created loan
    --    request on DD-Mon-YY, at HH:MI am
    --  Notifies Maker.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE CREATE_LOAN_REQUEST (
        p_folio_id          IN  NUMBER,
        p_amount            IN  NUMBER,
        p_instalment_months IN  NUMBER,
        p_payment_mode      IN  VARCHAR2,
        p_out_success       OUT VARCHAR2,
        p_out_message       OUT VARCHAR2,
        p_out_loan_id       OUT NUMBER
    ) IS
        v_company_id     NUMBER;
        v_fund_id        NUMBER;
        v_folio_no       VARCHAR2(50);
        v_lien           VARCHAR2(1);
        v_dis            VARCHAR2(1);
        v_noc            VARCHAR2(1);
        v_user_id        NUMBER;
        v_loan_no        VARCHAR2(30);
        v_loan_id        NUMBER;
        v_emp_name       VARCHAR2(200);
        v_loan_limit_pct NUMBER(5,2);
        v_max_months     NUMBER;
        v_itype          VARCHAR2(10);
        v_irate          NUMBER(7,3);
        v_monthly_inst   NUMBER(18,2);
        v_current_bal    NUMBER(18,2) := 0;
        v_maker_ucid     NUMBER;
        v_maker_user_id  NUMBER;
    BEGIN
        p_out_success := 'N';
        p_out_loan_id := NULL;

        -- Validation
        IF p_amount IS NULL OR p_amount <= 0 THEN
            p_out_message := 'Loan amount must be greater than zero.';
            RETURN;
        END IF;
        IF p_instalment_months IS NULL OR p_instalment_months <= 0 THEN
            p_out_message := 'Instalment period must be greater than zero.';
            RETURN;
        END IF;
        IF p_payment_mode NOT IN ('CHEQUE','ONLINE') THEN
            p_out_message := 'Payment mode must be CHEQUE or ONLINE.';
            RETURN;
        END IF;

        GET_FOLIO_INFO(p_folio_id, v_company_id, v_fund_id, v_folio_no,
                       v_lien, v_dis, v_noc, v_user_id);

        IF v_company_id IS NULL THEN
            p_out_message := 'Folio not found.';
            RETURN;
        END IF;

        -- Block disabled/lien/NOC-issued employees (FSD #359)
        IF v_dis = 'Y' THEN
            p_out_message := 'Your account has been disabled. Loan requests are not available.';
            RETURN;
        END IF;
        IF v_lien = 'Y' THEN
            p_out_message := 'Loan requests are not available for accounts with a lien marking.';
            RETURN;
        END IF;
        IF v_noc = 'Y' THEN
            p_out_message := 'Loan requests are not available for accounts with an issued NOC.';
            RETURN;
        END IF;

        -- Check LOAN feature is ENABLED for this employee (FSD #359)
        DECLARE
            v_access_status VARCHAR2(20);
        BEGIN
            SELECT ACCESS_STATUS INTO v_access_status
              FROM EPF_FEATURE_ACCESS
             WHERE COMPANY_ID   = v_company_id
               AND FOLIO_ID     = p_folio_id
               AND FEATURE_CODE = 'LOAN';
            IF v_access_status != 'ENABLED' THEN
                p_out_message := 'Loan feature is not enabled for your account.';
                RETURN;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Loan feature is not enabled for your account.';
                RETURN;
        END;

        -- Fetch company loan settings for validation
        BEGIN
            SELECT NVL(LOAN_MAX_INSTALMENT_MONTHS, 999),
                   NVL(LOAN_LIMIT_PCT, 100),
                   NVL(LOAN_INTEREST_TYPE, 'FIXED'),
                   NVL(LOAN_INTEREST_RATE, 0)
              INTO v_max_months, v_loan_limit_pct, v_itype, v_irate
              FROM EPF_COMPANY_SETTINGS
             WHERE COMPANY_ID = v_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_max_months     := 999;
                v_loan_limit_pct := 100;
                v_itype          := 'FIXED';
                v_irate          := 0;
        END;

        IF p_instalment_months > v_max_months THEN
            p_out_message := 'Instalment period cannot exceed ' || v_max_months || ' months.';
            RETURN;
        END IF;

        -- Validate amount vs loan limit % of current balance
        -- v_current_bal is fetched from DFN feed; stub = 0 (will be populated by DFN integration)
        IF v_loan_limit_pct < 100 AND v_current_bal > 0 THEN
            IF p_amount > (v_current_bal * v_loan_limit_pct / 100) THEN
                p_out_message := 'Loan amount exceeds the allowed limit ('
                              || v_loan_limit_pct || '% of current balance).';
                RETURN;
            END IF;
        END IF;

        -- Calculate monthly instalment
        v_monthly_inst := ROUND(
            p_amount * (1 + (v_irate / 100)) / GREATEST(p_instalment_months, 1),
            2
        );

        -- Generate loan number
        v_loan_no := 'LN-' || TO_CHAR(SYSDATE,'YYYYMM') || '-'
                  || LPAD(EPF_LOAN_REQ_SEQ.NEXTVAL, 4, '0');

        v_emp_name := GET_EMPLOYEE_NAME(p_folio_id);

        -- We need a maker_ucid for the FK constraint; use system/null when employee creates
        -- Use a sentinel UCID=0 or the employee's own user_company link.
        -- Best practice: employee's own user-company record as maker_ucid
        BEGIN
            SELECT uc.USER_COMPANY_ID INTO v_maker_ucid
              FROM EPF_USER_COMPANIES  uc
             WHERE uc.FOLIO_ID   = p_folio_id
               AND uc.COMPANY_ID = v_company_id
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Fall back to first active maker for this company
                v_maker_ucid := GET_MAKER_UCID_FOR_COMPANY(v_company_id);
        END;

        -- Insert loan request with PENDING_MAKER status
        INSERT INTO EPF_LOAN_REQUESTS (
            COMPANY_ID, FOLIO_ID, LOAN_NO,
            AMOUNT, INTEREST_TYPE, INTEREST_RATE,
            INSTALMENT_MONTHS, MONTHLY_INSTALMENT,
            STATUS_ID, MAKER_UCID, MAKER_DATE,
            CREATED_BY_EMPLOYEE_YN, PAYMENT_MODE,
            AUTHORIZER_COUNT, AUTHORIZER_APPROVED_COUNT
        ) VALUES (
            v_company_id, p_folio_id, v_loan_no,
            p_amount, v_itype, v_irate,
            p_instalment_months, v_monthly_inst,
            EPF_STATUS_PKG.GET_ID('REQUEST','PENDING_MAKER'),
            v_maker_ucid, SYSDATE,
            'Y', p_payment_mode,
            0, 0
        )
        RETURNING LOAN_ID INTO v_loan_id;

        p_out_loan_id := v_loan_id;

        -- FSD narration 3.1 (employee format):
        -- [employee name] (employee): Created loan request on DD-Mon-YY, at HH:MI am
        NARRATE_EMPLOYEE(
            p_company_id  => v_company_id,
            p_user_id     => v_user_id,
            p_action_code => 'EMPLOYEE_CREATE_LOAN',
            p_narration   => v_emp_name || ' (employee): Created loan request on '
                          || TO_CHAR(SYSDATE,'DD-Mon-YY') || ', at '
                          || TO_CHAR(SYSDATE,'HH:MI am'),
            p_ref_type    => 'LOAN',
            p_ref_id      => v_loan_id
        );

        -- Notify Maker that an employee has created a loan request
        v_maker_ucid := GET_MAKER_UCID_FOR_COMPANY(v_company_id);
        IF v_maker_ucid IS NOT NULL THEN
            BEGIN
                SELECT USER_ID INTO v_maker_user_id
                  FROM EPF_USER_COMPANIES WHERE USER_COMPANY_ID = v_maker_ucid;
                NOTIFY_USER_ID(
                    p_company_id => v_company_id,
                    p_user_id    => v_maker_user_id,
                    p_title      => 'New Loan Request from Employee',
                    p_message    => v_emp_name || ' has submitted a loan request (Ref: '
                                 || v_loan_no || ') for PKR '
                                 || TO_CHAR(p_amount,'FM999,999,999.00') || '.',
                    p_ref_type   => 'LOAN',
                    p_ref_id     => v_loan_id
                );
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
        END IF;

        p_out_success := 'Y';
        p_out_message := 'Loan request submitted. Reference No.: ' || v_loan_no;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Unexpected error in CREATE_LOAN_REQUEST: ' || SQLERRM;
    END CREATE_LOAN_REQUEST;

    -- ─────────────────────────────────────────────────────────
    --  CREATE_WITHDRAWAL_REQUEST  –  FSD #365-369
    --  Employee creates withdrawal request → PENDING_MAKER status.
    --  Narration 4.1 (employee format):
    --    [employee name] (employee): Created withdrawal request on
    --    DD-Mon-YY, at HH:MI am
    -- ─────────────────────────────────────────────────────────
    PROCEDURE CREATE_WITHDRAWAL_REQUEST (
        p_folio_id     IN  NUMBER,
        p_amount       IN  NUMBER,    -- NULL when FULL
        p_wd_type      IN  VARCHAR2,
        p_reason       IN  VARCHAR2 DEFAULT NULL,
        p_payment_mode IN  VARCHAR2,
        p_out_success  OUT VARCHAR2,
        p_out_message  OUT VARCHAR2,
        p_out_wd_id    OUT NUMBER
    ) IS
        v_company_id    NUMBER;
        v_fund_id       NUMBER;
        v_folio_no      VARCHAR2(50);
        v_lien          VARCHAR2(1);
        v_dis           VARCHAR2(1);
        v_noc           VARCHAR2(1);
        v_user_id       NUMBER;
        v_wd_no         VARCHAR2(30);
        v_wd_id         NUMBER;
        v_emp_name      VARCHAR2(200);
        v_maker_ucid    NUMBER;
        v_maker_user_id NUMBER;
    BEGIN
        p_out_success := 'N';
        p_out_wd_id   := NULL;

        -- Validation
        IF p_wd_type NOT IN ('PARTIAL','FULL') THEN
            p_out_message := 'Withdrawal type must be PARTIAL or FULL.';
            RETURN;
        END IF;
        IF p_wd_type = 'PARTIAL' AND (p_amount IS NULL OR p_amount <= 0) THEN
            p_out_message := 'Withdrawal amount must be greater than zero for partial withdrawal.';
            RETURN;
        END IF;
        IF p_payment_mode NOT IN ('CHEQUE','ONLINE') THEN
            p_out_message := 'Payment mode must be CHEQUE or ONLINE.';
            RETURN;
        END IF;

        GET_FOLIO_INFO(p_folio_id, v_company_id, v_fund_id, v_folio_no,
                       v_lien, v_dis, v_noc, v_user_id);

        IF v_company_id IS NULL THEN
            p_out_message := 'Folio not found.';
            RETURN;
        END IF;

        IF v_dis = 'Y' THEN
            p_out_message := 'Your account has been disabled. Withdrawal requests are not available.';
            RETURN;
        END IF;
        IF v_lien = 'Y' THEN
            p_out_message := 'Withdrawal requests are not available for accounts with a lien marking.';
            RETURN;
        END IF;

        -- Check WITHDRAWAL feature is ENABLED (FSD #365)
        DECLARE
            v_access_status VARCHAR2(20);
        BEGIN
            SELECT ACCESS_STATUS INTO v_access_status
              FROM EPF_FEATURE_ACCESS
             WHERE COMPANY_ID   = v_company_id
               AND FOLIO_ID     = p_folio_id
               AND FEATURE_CODE = 'WITHDRAWAL';
            IF v_access_status != 'ENABLED' THEN
                p_out_message := 'Withdrawal feature is not enabled for your account.';
                RETURN;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Withdrawal feature is not enabled for your account.';
                RETURN;
        END;

        -- Generate WD number
        v_wd_no := 'WD-' || TO_CHAR(SYSDATE,'YYYYMM') || '-'
                || LPAD(EPF_WD_REQ_SEQ.NEXTVAL, 4, '0');

        v_emp_name := GET_EMPLOYEE_NAME(p_folio_id);

        -- Find employee's own UCID for maker_ucid FK
        BEGIN
            SELECT uc.USER_COMPANY_ID INTO v_maker_ucid
              FROM EPF_USER_COMPANIES  uc
             WHERE uc.FOLIO_ID   = p_folio_id
               AND uc.COMPANY_ID = v_company_id
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_maker_ucid := GET_MAKER_UCID_FOR_COMPANY(v_company_id);
        END;

        -- Insert withdrawal request with PENDING_MAKER status
        INSERT INTO EPF_WITHDRAWAL_REQUESTS (
            COMPANY_ID, FOLIO_ID, WD_NO,
            AMOUNT, WD_TYPE, REASON,
            STATUS_ID, MAKER_UCID, MAKER_DATE,
            CREATED_BY_EMPLOYEE_YN, PAYMENT_MODE,
            AUTHORIZER_COUNT, AUTHORIZER_APPROVED_COUNT
        ) VALUES (
            v_company_id, p_folio_id, v_wd_no,
            CASE WHEN p_wd_type = 'FULL' THEN NULL ELSE p_amount END,
            p_wd_type, p_reason,
            EPF_STATUS_PKG.GET_ID('REQUEST','PENDING_MAKER'),
            v_maker_ucid, SYSDATE,
            'Y', p_payment_mode,
            0, 0
        )
        RETURNING WD_ID INTO v_wd_id;

        p_out_wd_id := v_wd_id;

        -- FSD narration 4.1 (employee format)
        NARRATE_EMPLOYEE(
            p_company_id  => v_company_id,
            p_user_id     => v_user_id,
            p_action_code => 'EMPLOYEE_CREATE_WD',
            p_narration   => v_emp_name || ' (employee): Created withdrawal request on '
                          || TO_CHAR(SYSDATE,'DD-Mon-YY') || ', at '
                          || TO_CHAR(SYSDATE,'HH:MI am'),
            p_ref_type    => 'WITHDRAWAL',
            p_ref_id      => v_wd_id
        );

        -- Notify Maker
        v_maker_ucid := GET_MAKER_UCID_FOR_COMPANY(v_company_id);
        IF v_maker_ucid IS NOT NULL THEN
            BEGIN
                SELECT USER_ID INTO v_maker_user_id
                  FROM EPF_USER_COMPANIES WHERE USER_COMPANY_ID = v_maker_ucid;
                NOTIFY_USER_ID(
                    p_company_id => v_company_id,
                    p_user_id    => v_maker_user_id,
                    p_title      => 'New Withdrawal Request from Employee',
                    p_message    => v_emp_name || ' has submitted a '
                                 || LOWER(p_wd_type) || ' withdrawal request (Ref: '
                                 || v_wd_no || ').',
                    p_ref_type   => 'WITHDRAWAL',
                    p_ref_id     => v_wd_id
                );
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
        END IF;

        p_out_success := 'Y';
        p_out_message := 'Withdrawal request submitted. Reference No.: ' || v_wd_no;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Unexpected error in CREATE_WITHDRAWAL_REQUEST: ' || SQLERRM;
    END CREATE_WITHDRAWAL_REQUEST;

END EPF_EMPLOYEE_PKG;
/

-- ============================================================
-- End of 16_epf_employee_pkg.sql
-- ============================================================
