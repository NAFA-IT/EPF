-- ============================================================
-- FILE: /home/user/EPF/apex/employee/page_processes.sql
-- EPF PORTAL  –  Employee Self-Service Module – APEX Page Processes
-- All processes are PL/SQL Anonymous Blocks to be pasted into
-- APEX Application Builder as "Execute PL/SQL Code" processes.
-- Binds: :APP_FOLIO_ID (employee's own folio), :APP_USER_ID
-- FSD validations: #346-372
-- Pages: 80 (Dashboard), 81 (Account Statement), 82 (Certificates),
--        83 (Portfolio Reallocation), 84 (Loan Request), 85 (Withdrawal)
-- ============================================================

-- ============================================================
-- PAGE 80  –  Employee Dashboard
-- Items: P80_DATE_FROM, P80_DATE_TO, P80_SEARCH_FLAG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P80_CLEAR_FILTERS
-- When:    On Submit
-- Condition: Request = 'CLEAR_FILTERS'
-- Purpose: Clear date filters and reload dashboard.
-- ------------------------------------------------------------
BEGIN
    :P80_DATE_FROM   := NULL;
    :P80_DATE_TO     := NULL;
    :P80_SEARCH_FLAG := 'N';
END;

-- ------------------------------------------------------------
-- PROCESS: P80_SET_SEARCH_FLAG
-- When:    On Submit
-- Condition: Request = 'SEARCH'
-- Purpose: Validate date filters and set search flag.
-- ------------------------------------------------------------
BEGIN
    -- At least one date must be entered (FSD #347)
    IF :P80_DATE_FROM IS NULL AND :P80_DATE_TO IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please enter at least one date filter.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    -- Disallow future dates (FSD #347)
    IF :P80_DATE_FROM IS NOT NULL AND TO_DATE(:P80_DATE_FROM,'YYYY-MM-DD') > TRUNC(SYSDATE) THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Date From cannot be a future date.',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P80_DATE_FROM'
        );
    END IF;

    IF :P80_DATE_TO IS NOT NULL AND TO_DATE(:P80_DATE_TO,'YYYY-MM-DD') > TRUNC(SYSDATE) THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Date To cannot be a future date.',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P80_DATE_TO'
        );
    END IF;

    :P80_SEARCH_FLAG := 'Y';
END;

-- ============================================================
-- PAGE 81  –  Account Statement
-- Items: P81_PERIOD_TYPE (LAST30/LAST90/INCEPTION/DATE_RANGE),
--        P81_DATE_FROM, P81_DATE_TO, P81_FUND_ID,
--        P81_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P81_VIEW_STATEMENT
-- When:    On Submit
-- Condition: Request = 'VIEW_NOW'
-- Purpose: Validate and set up date range for IR display.
-- ------------------------------------------------------------
DECLARE
    v_period VARCHAR2(20) := :P81_PERIOD_TYPE;
BEGIN
    -- Period type must be selected (FSD #351-352)
    IF v_period IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select a time period.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    -- If DATE_RANGE, both dates required
    IF v_period = 'DATE_RANGE' THEN
        IF :P81_DATE_FROM IS NULL THEN
            APEX_ERROR.ADD_ERROR(p_message => 'Required field',
                p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
                p_page_item_name   => 'P81_DATE_FROM');
        END IF;
        IF :P81_DATE_TO IS NULL THEN
            APEX_ERROR.ADD_ERROR(p_message => 'Required field',
                p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
                p_page_item_name   => 'P81_DATE_TO');
        END IF;
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: P81_REQUEST_ON_EMAIL
-- When:    On Submit
-- Condition: Request = 'REQUEST_ON_EMAIL'
-- Purpose: Send account statement via email #21.
-- ------------------------------------------------------------
DECLARE
    v_success    VARCHAR2(1);
    v_message    VARCHAR2(4000);
    v_period     VARCHAR2(20)  := :P81_PERIOD_TYPE;
    v_date_from  DATE;
    v_date_to    DATE;
BEGIN
    IF v_period IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select a time period before requesting email.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    -- Resolve date range
    CASE v_period
        WHEN 'LAST30'     THEN v_date_from := TRUNC(SYSDATE) - 30;    v_date_to := TRUNC(SYSDATE);
        WHEN 'LAST90'     THEN v_date_from := TRUNC(SYSDATE) - 90;    v_date_to := TRUNC(SYSDATE);
        WHEN 'INCEPTION'  THEN v_date_from := DATE '1900-01-01';       v_date_to := TRUNC(SYSDATE);
        WHEN 'DATE_RANGE' THEN
            IF :P81_DATE_FROM IS NULL OR :P81_DATE_TO IS NULL THEN
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'Please enter both Date From and Date To for date range.',
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
                RETURN;
            END IF;
            v_date_from := TO_DATE(:P81_DATE_FROM, 'YYYY-MM-DD');
            v_date_to   := TO_DATE(:P81_DATE_TO,   'YYYY-MM-DD');
        ELSE
            v_date_from := TRUNC(SYSDATE) - 30;
            v_date_to   := TRUNC(SYSDATE);
    END CASE;

    EPF_EMPLOYEE_PKG.REQUEST_ACCOUNT_STATEMENT_EMAIL(
        p_user_id     => :APP_USER_ID,
        p_folio_id    => :APP_FOLIO_ID,
        p_fund_id     => :P81_FUND_ID,
        p_date_from   => v_date_from,
        p_date_to     => v_date_to,
        p_out_success => v_success,
        p_out_message => v_message
    );

    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    :P81_SUCCESS_MSG := v_message;
END;

-- ============================================================
-- PAGE 82  –  Certificates (Tax Certificate)
-- Items: P82_TAX_YEAR (e.g. '2024-25'),
--        P82_CERT_HTML (CLOB for display region), P82_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P82_GENERATE_CERT
-- When:    On Submit
-- Condition: Request = 'GENERATE_CERT'
-- Purpose: Generate HTML certificate and set display item.
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_html     CLOB;
BEGIN
    IF :P82_TAX_YEAR IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Required field',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P82_TAX_YEAR'
        );
        RETURN;
    END IF;

    EPF_EMPLOYEE_PKG.GENERATE_TAX_CERTIFICATE(
        p_user_id     => :APP_USER_ID,
        p_folio_id    => :APP_FOLIO_ID,
        p_tax_year    => :P82_TAX_YEAR,
        p_out_html    => v_html,
        p_out_success => v_success,
        p_out_message => v_message
    );

    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    :P82_CERT_HTML  := v_html;
    :P82_SUCCESS_MSG := v_message;
END;

-- ============================================================
-- PAGE 83  –  Portfolio Reallocation
-- Items: P83_GROUP_ID, P83_MM_PCT, P83_DEBT_PCT, P83_EQUITY_PCT,
--        P83_TOTAL_PCT (calculated client-side), P83_SUCCESS_MSG
-- FSD #356-358, #372
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P83_VALIDATE_ALLOCATION
-- When:    On Submit
-- Condition: Request = 'UPDATE_ALLOCATION' (after confirm popup)
-- Purpose: Validate and submit portfolio reallocation.
-- ------------------------------------------------------------
DECLARE
    v_success   VARCHAR2(1);
    v_message   VARCHAR2(4000);
    v_mm_pct    NUMBER := TO_NUMBER(NVL(:P83_MM_PCT, '0'));
    v_debt_pct  NUMBER := TO_NUMBER(NVL(:P83_DEBT_PCT, '0'));
    v_eq_pct    NUMBER := TO_NUMBER(NVL(:P83_EQUITY_PCT, '0'));
    v_group_id  NUMBER := TO_NUMBER(:P83_GROUP_ID);
BEGIN
    -- Validate total = 100% (client-side also enforces, but server-side is mandatory)
    IF (v_mm_pct + v_debt_pct + v_eq_pct) != 100 THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Total allocation must equal 100%. Current: '
                               || (v_mm_pct + v_debt_pct + v_eq_pct) || '%.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    EPF_EMPLOYEE_PKG.CREATE_PORTFOLIO_REALLOC(
        p_folio_id    => :APP_FOLIO_ID,
        p_group_id    => v_group_id,
        p_mm_pct      => v_mm_pct,
        p_debt_pct    => v_debt_pct,
        p_equity_pct  => v_eq_pct,
        p_out_success => v_success,
        p_out_message => v_message
    );

    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    :P83_MM_PCT      := NULL;
    :P83_DEBT_PCT    := NULL;
    :P83_EQUITY_PCT  := NULL;
    :P83_SUCCESS_MSG := v_message;
END;

-- ============================================================
-- PAGE 84  –  Create Loan Request (3-Step Wizard)
-- Steps: Step 1 (P84_STEP=1: Create), Step 2 (Review),
--        Step 3 (Finish)
-- Items: P84_STEP, P84_AMOUNT, P84_INSTALMENT_MONTHS,
--        P84_PAYMENT_MODE (CHEQUE/ONLINE),
--        P84_LOAN_ID (set on submit), P84_LOAN_NO,
--        P84_SUBMIT_DATE, P84_FINISH_MSG
-- FSD #359-364
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P84_STEP1_NEXT
-- When:    On Submit
-- Condition: Request = 'STEP1_NEXT'  (Step 1 → Step 2)
-- Purpose: Validate Step 1 fields; advance to review.
-- ------------------------------------------------------------
BEGIN
    -- Validate loan amount (FSD #361)
    IF :P84_AMOUNT IS NULL OR TO_NUMBER(:P84_AMOUNT) <= 0 THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Required field',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P84_AMOUNT'
        );
    END IF;

    -- Validate instalment months
    IF :P84_INSTALMENT_MONTHS IS NULL OR TO_NUMBER(:P84_INSTALMENT_MONTHS) <= 0 THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Required field',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P84_INSTALMENT_MONTHS'
        );
    END IF;

    -- Validate payment mode
    IF :P84_PAYMENT_MODE IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Required field',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P84_PAYMENT_MODE'
        );
    END IF;

    :P84_STEP := '2';
END;

-- ------------------------------------------------------------
-- PROCESS: P84_STEP2_BACK
-- When:    On Submit
-- Condition: Request = 'STEP2_BACK'  (Step 2 → Step 1)
-- ------------------------------------------------------------
BEGIN
    :P84_STEP := '1';
END;

-- ------------------------------------------------------------
-- PROCESS: P84_STEP2_SUBMIT
-- When:    On Submit
-- Condition: Request = 'STEP2_NEXT'  (Step 2 → Submit → Step 3)
-- Purpose: Create loan request; advance to finish.
-- ------------------------------------------------------------
DECLARE
    v_success   VARCHAR2(1);
    v_message   VARCHAR2(4000);
    v_loan_id   NUMBER;
BEGIN
    EPF_EMPLOYEE_PKG.CREATE_LOAN_REQUEST(
        p_folio_id          => :APP_FOLIO_ID,
        p_amount            => TO_NUMBER(:P84_AMOUNT),
        p_instalment_months => TO_NUMBER(:P84_INSTALMENT_MONTHS),
        p_payment_mode      => :P84_PAYMENT_MODE,
        p_out_success       => v_success,
        p_out_message       => v_message,
        p_out_loan_id       => v_loan_id
    );

    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    :P84_LOAN_ID     := v_loan_id;
    :P84_SUBMIT_DATE := TO_CHAR(SYSDATE, 'DD-Mon-YYYY HH:MI:SS AM');

    -- Fetch reference number for display on Finish page (FSD #364)
    BEGIN
        SELECT LOAN_NO INTO :P84_LOAN_NO
          FROM EPF_LOAN_REQUESTS WHERE LOAN_ID = v_loan_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN :P84_LOAN_NO := 'N/A';
    END;

    :P84_FINISH_MSG := 'Loan request has been submitted.';
    :P84_STEP       := '3';
END;

-- ------------------------------------------------------------
-- PROCESS: P84_FINISH
-- When:    On Submit
-- Condition: Request = 'FINISH'  (Step 3 → Dashboard)
-- Purpose: Reset wizard and redirect to Dashboard.
-- ------------------------------------------------------------
BEGIN
    :P84_STEP               := '1';
    :P84_AMOUNT             := NULL;
    :P84_INSTALMENT_MONTHS  := NULL;
    :P84_PAYMENT_MODE       := 'ONLINE';
    :P84_LOAN_ID            := NULL;
    :P84_LOAN_NO            := NULL;
    :P84_SUBMIT_DATE        := NULL;
    -- Redirect to Employee Dashboard (page 80)
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 80));
END;

-- ============================================================
-- PAGE 85  –  Create Withdrawal Request (3-Step Wizard)
-- Items: P85_STEP, P85_AMOUNT, P85_WD_TYPE (PARTIAL/FULL),
--        P85_FULL_FLAG (Y/N checkbox), P85_PAYMENT_MODE,
--        P85_WD_ID, P85_WD_NO, P85_SUBMIT_DATE, P85_FINISH_MSG
-- FSD #365-369
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P85_STEP1_NEXT
-- When:    On Submit
-- Condition: Request = 'STEP1_NEXT'
-- ------------------------------------------------------------
BEGIN
    -- Mode required
    IF :P85_PAYMENT_MODE IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Required field',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
            p_page_item_name   => 'P85_PAYMENT_MODE'
        );
    END IF;

    -- Amount required unless Full Withdrawal checkbox checked (FSD #367)
    IF NVL(:P85_FULL_FLAG,'N') = 'N' THEN
        IF :P85_AMOUNT IS NULL OR TO_NUMBER(:P85_AMOUNT) <= 0 THEN
            APEX_ERROR.ADD_ERROR(
                p_message          => 'Required field',
                p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIFICATION,
                p_page_item_name   => 'P85_AMOUNT'
            );
        END IF;
        :P85_WD_TYPE := 'PARTIAL';
    ELSE
        :P85_WD_TYPE := 'FULL';
        :P85_AMOUNT  := NULL;
    END IF;

    :P85_STEP := '2';
END;

-- ------------------------------------------------------------
-- PROCESS: P85_STEP2_BACK
-- When:    On Submit
-- Condition: Request = 'STEP2_BACK'
-- ------------------------------------------------------------
BEGIN
    :P85_STEP := '1';
END;

-- ------------------------------------------------------------
-- PROCESS: P85_STEP2_SUBMIT
-- When:    On Submit
-- Condition: Request = 'STEP2_NEXT'
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_wd_id    NUMBER;
BEGIN
    EPF_EMPLOYEE_PKG.CREATE_WITHDRAWAL_REQUEST(
        p_folio_id     => :APP_FOLIO_ID,
        p_amount       => CASE WHEN :P85_WD_TYPE = 'FULL' THEN NULL
                               ELSE TO_NUMBER(:P85_AMOUNT) END,
        p_wd_type      => :P85_WD_TYPE,
        p_reason       => NULL,
        p_payment_mode => :P85_PAYMENT_MODE,
        p_out_success  => v_success,
        p_out_message  => v_message,
        p_out_wd_id    => v_wd_id
    );

    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    :P85_WD_ID       := v_wd_id;
    :P85_SUBMIT_DATE := TO_CHAR(SYSDATE, 'DD-Mon-YYYY HH:MI:SS AM');

    BEGIN
        SELECT WD_NO INTO :P85_WD_NO
          FROM EPF_WITHDRAWAL_REQUESTS WHERE WD_ID = v_wd_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN :P85_WD_NO := 'N/A';
    END;

    :P85_FINISH_MSG := 'Withdrawal request has been submitted.';
    :P85_STEP       := '3';
END;

-- ------------------------------------------------------------
-- PROCESS: P85_FINISH
-- When:    On Submit
-- Condition: Request = 'FINISH'
-- ------------------------------------------------------------
BEGIN
    :P85_STEP         := '1';
    :P85_AMOUNT       := NULL;
    :P85_WD_TYPE      := NULL;
    :P85_FULL_FLAG    := 'N';
    :P85_PAYMENT_MODE := 'ONLINE';
    :P85_WD_ID        := NULL;
    :P85_WD_NO        := NULL;
    :P85_SUBMIT_DATE  := NULL;
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 80));
END;

-- ============================================================
-- END of employee/page_processes.sql
-- ============================================================
