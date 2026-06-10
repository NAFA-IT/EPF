-- ============================================================
-- FILE: /home/user/EPF/apex/corp_maker_checker/ir_queries.sql
-- EPF PORTAL  –  Corporate Maker / Checker Module – IR Queries & LOVs
-- Paste these as APEX Interactive Report / List of Values sources.
-- Binds: :APP_COMPANY_ID, :APP_USER_COMPANY_ID, :APP_USER_ID.
-- Status codes resolved via EPF_STATUS_PKG only — never hardcoded.
-- Employee Name/CNIC resolved from EPF_USER_COMPANIES.FOLIO_ID.
-- ============================================================

-- ============================================================
-- VIEW ALL CONTRIBUTION UPLOADS  (FSD #255–#258)
-- One row per batch row, with batch summary columns repeated.
-- Use Control Break on BATCH_NO for the Collapse/Expand batches.
-- ============================================================
SELECT
    b.BATCH_ID,
    b.BATCH_NO,
    r.ROW_ID                                AS REF_NO,
    r.EMPLOYEE_NAME                         AS NAME,
    r.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    fu.FUND_NAME                            AS FUND,
    r.EMPLOYER_AMOUNT                       AS EMPLOYER_CONTRIBUTION,
    r.EMPLOYEE_AMOUNT                       AS EMPLOYEE_CONTRIBUTION,
    r.TOTAL_AMOUNT                          AS TOTAL_CONTRIBUTION,
    -- Batch summary (FSD #257)
    b.TOTAL_AMOUNT                          AS BATCH_TOTAL_AMOUNT,
    b.TOTAL_EMPLOYEES                       AS BATCH_TOTAL_EMPLOYEES,
    b.VARIANCE_AMOUNT_PCT,
    b.VARIANCE_EMPLOYEE_PCT,
    r.IS_DUPLICATE,
    EPF_STATUS_PKG.GET_CODE(b.STATUS_ID)    AS STATUS_CODE,
    s.STATUS_DISPLAY                        AS STATUS_LABEL,
    -- Status badge class per FSD #255–#258 styling
    CASE EPF_STATUS_PKG.GET_CODE(b.STATUS_ID)
        WHEN 'PENDING_CHECKER'    THEN 'epf-badge-pending-checker'
        WHEN 'PENDING_AUTHORIZER' THEN 'epf-badge-pending-auth'
        WHEN 'AUTHORIZED'         THEN 'epf-badge-completed'
        WHEN 'REJECTED'           THEN 'epf-badge-rejected'
        ELSE 'epf-badge-default'
    END                                     AS STATUS_BADGE_CLASS,
    TO_CHAR(b.MAKER_DATE, 'DD-Mon-YY')      AS CREATED_ON,
    b.CHECKER_REMARKS
FROM EPF_CONTRIB_BATCHES   b
JOIN EPF_CONTRIB_BATCH_ROWS r  ON r.BATCH_ID  = b.BATCH_ID
JOIN EPF_STATUSES           s  ON s.STATUS_ID = b.STATUS_ID
LEFT JOIN EPF_FOLIOS        f  ON f.FOLIO_ID  = r.FOLIO_ID
LEFT JOIN EPF_FUNDS         fu ON fu.FUND_ID  = b.FUND_ID
WHERE b.COMPANY_ID = :APP_COMPANY_ID
ORDER BY b.MAKER_DATE DESC, b.BATCH_ID DESC, r.ROW_ID
;

-- ============================================================
-- VIEW ALL LOAN REQUESTS  (FSD #259–#262)
-- Incl. Amount Repaid, Outstanding, Authorized On, Repaid On.
-- ============================================================
SELECT
    l.LOAN_ID,
    l.LOAN_NO                               AS REF_NO,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = l.FOLIO_ID)        AS FUND,
    l.AMOUNT_REPAID,
    l.OUTSTANDING,
    l.AMOUNT + ROUND(l.AMOUNT * l.INTEREST_RATE / 100, 2)
                                            AS TOTAL_REPAYABLE,
    l.AMOUNT                                AS LOAN_AMOUNT,
    ROUND(l.AMOUNT * l.INTEREST_RATE / 100, 2)
                                            AS INTEREST_AMOUNT,
    l.MONTHLY_INSTALMENT,
    l.INSTALMENT_MONTHS                     AS INSTALMENT_PERIOD,
    TO_CHAR(l.AUTHORIZED_DATE, 'DD-Mon-YY') AS AUTHORIZED_ON,
    (SELECT TO_CHAR(MAX(ls.DUE_DATE), 'DD-Mon-YY')
       FROM EPF_LOAN_SCHEDULE ls
      WHERE ls.LOAN_ID = l.LOAN_ID AND ls.PAID_YN = 'Y'
     HAVING COUNT(*) = l.INSTALMENT_MONTHS) AS REPAID_ON,
    EPF_STATUS_PKG.GET_CODE(l.STATUS_ID)    AS STATUS_CODE,
    s.STATUS_DISPLAY                        AS STATUS_LABEL,
    CASE EPF_STATUS_PKG.GET_CODE(l.STATUS_ID)
        WHEN 'PENDING_CHECKER'    THEN 'epf-badge-pending-checker'
        WHEN 'PENDING_AUTHORIZER' THEN 'epf-badge-pending-auth'
        WHEN 'AUTHORIZED'         THEN 'epf-badge-completed'
        WHEN 'REJECTED'           THEN 'epf-badge-rejected'
        ELSE 'epf-badge-default'
    END                                     AS STATUS_BADGE_CLASS,
    l.CHECKER_REMARKS
FROM EPF_LOAN_REQUESTS  l
JOIN EPF_STATUSES       s  ON s.STATUS_ID = l.STATUS_ID
JOIN EPF_FOLIOS         f  ON f.FOLIO_ID  = l.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = l.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE l.COMPANY_ID = :APP_COMPANY_ID
ORDER BY l.MAKER_DATE DESC
;

-- ============================================================
-- VIEW ALL WITHDRAWAL REQUESTS  (FSD #263–#265)
-- ============================================================
SELECT
    w.WD_ID,
    w.WD_NO                                 AS REF_NO,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = w.FOLIO_ID)        AS FUND,
    CASE WHEN w.WD_TYPE = 'FULL'
         THEN 'Full Withdrawal'
         ELSE TO_CHAR(w.AMOUNT, 'FM999G999G999G990D00') END
                                            AS WITHDRAWAL_AMOUNT,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = w.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING,
    EPF_STATUS_PKG.GET_CODE(w.STATUS_ID)    AS STATUS_CODE,
    s.STATUS_DISPLAY                        AS STATUS_LABEL,
    CASE EPF_STATUS_PKG.GET_CODE(w.STATUS_ID)
        WHEN 'PENDING_CHECKER'    THEN 'epf-badge-pending-checker'
        WHEN 'PENDING_AUTHORIZER' THEN 'epf-badge-pending-auth'
        WHEN 'AUTHORIZED'         THEN 'epf-badge-completed'
        WHEN 'REJECTED'           THEN 'epf-badge-rejected'
        ELSE 'epf-badge-default'
    END                                     AS STATUS_BADGE_CLASS,
    w.CHECKER_REMARKS
FROM EPF_WITHDRAWAL_REQUESTS w
JOIN EPF_STATUSES            s ON s.STATUS_ID = w.STATUS_ID
JOIN EPF_FOLIOS              f ON f.FOLIO_ID  = w.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = w.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE w.COMPANY_ID = :APP_COMPANY_ID
ORDER BY w.MAKER_DATE DESC
;

-- ============================================================
-- VIEW ALL LIEN REQUESTS  (FSD #266–#268)
-- Combined status: '[Lien Marking|Lien Unmarking] [Pending|Completed|Rejected]'
-- ============================================================
SELECT
    lr.LIEN_ID,
    lr.LIEN_NO                              AS REF_NO,
    lr.REQUEST_TYPE,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = lr.FOLIO_ID)       AS FUND,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = lr.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING,
    CASE lr.REQUEST_TYPE WHEN 'MARK' THEN 'Lien Marking' ELSE 'Lien Unmarking' END
        || ' ' ||
    CASE EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)
        WHEN 'AUTHORIZED' THEN 'Completed'
        WHEN 'REJECTED'   THEN 'Rejected'
        ELSE 'Pending'
    END                                     AS STATUS_LABEL,
    EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)   AS STATUS_CODE,
    CASE EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)
        WHEN 'PENDING_CHECKER'    THEN 'epf-badge-pending-checker'
        WHEN 'PENDING_AUTHORIZER' THEN 'epf-badge-pending-auth'
        WHEN 'AUTHORIZED'         THEN 'epf-badge-completed'
        WHEN 'REJECTED'           THEN 'epf-badge-rejected'
        ELSE 'epf-badge-default'
    END                                     AS STATUS_BADGE_CLASS,
    lr.CHECKER_REMARKS
FROM EPF_LIEN_REQUESTS  lr
JOIN EPF_FOLIOS         f  ON f.FOLIO_ID = lr.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = lr.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE lr.COMPANY_ID = :APP_COMPANY_ID
ORDER BY lr.MAKER_DATE DESC
;

-- ============================================================
-- VIEW ALL NOC REQUESTS  (FSD #269–#271)
-- ============================================================
SELECT
    n.NOC_ID,
    n.NOC_NO                                AS REF_NO,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = n.FOLIO_ID)        AS FUND,
    TO_CHAR(n.MAKER_DATE, 'DD-Mon-YY')      AS CREATED_ON,
    TO_CHAR(n.ISSUED_DATE, 'DD-Mon-YY')     AS NOC_ISSUED_ON,
    EPF_STATUS_PKG.GET_CODE(n.STATUS_ID)    AS STATUS_CODE,
    s.STATUS_DISPLAY                        AS STATUS_LABEL,
    CASE EPF_STATUS_PKG.GET_CODE(n.STATUS_ID)
        WHEN 'PENDING_CHECKER'    THEN 'epf-badge-pending-checker'
        WHEN 'PENDING_AUTHORIZER' THEN 'epf-badge-pending-auth'
        WHEN 'AUTHORIZED'         THEN 'epf-badge-completed'
        WHEN 'REJECTED'           THEN 'epf-badge-rejected'
        ELSE 'epf-badge-default'
    END                                     AS STATUS_BADGE_CLASS,
    n.CHECKER_REMARKS
FROM EPF_NOC_REQUESTS   n
JOIN EPF_STATUSES       s ON s.STATUS_ID = n.STATUS_ID
JOIN EPF_FOLIOS         f ON f.FOLIO_ID  = n.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = n.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE n.COMPANY_ID = :APP_COMPANY_ID
ORDER BY n.MAKER_DATE DESC
;

-- ============================================================
-- PAGE 50 – CHECK CONTRIBUTION UPLOADS  (FSD #296–#299)
-- Same columns as View All, but only PENDING_CHECKER batches,
-- with batch-level checkbox.
-- ============================================================
SELECT
    b.BATCH_ID,
    b.BATCH_NO,
    r.ROW_ID                                AS REF_NO,
    r.EMPLOYEE_NAME                         AS NAME,
    r.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    fu.FUND_NAME                            AS FUND,
    r.EMPLOYER_AMOUNT                       AS EMPLOYER_CONTRIBUTION,
    r.EMPLOYEE_AMOUNT                       AS EMPLOYEE_CONTRIBUTION,
    r.TOTAL_AMOUNT                          AS TOTAL_CONTRIBUTION,
    b.TOTAL_AMOUNT                          AS BATCH_TOTAL_AMOUNT,
    b.TOTAL_EMPLOYEES                       AS BATCH_TOTAL_EMPLOYEES,
    b.VARIANCE_AMOUNT_PCT,
    b.VARIANCE_EMPLOYEE_PCT,
    r.IS_DUPLICATE
FROM EPF_CONTRIB_BATCHES    b
JOIN EPF_CONTRIB_BATCH_ROWS r  ON r.BATCH_ID = b.BATCH_ID
LEFT JOIN EPF_FOLIOS        f  ON f.FOLIO_ID = r.FOLIO_ID
LEFT JOIN EPF_FUNDS         fu ON fu.FUND_ID = b.FUND_ID
WHERE b.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(b.STATUS_ID) = 'PENDING_CHECKER'
ORDER BY b.MAKER_DATE, b.BATCH_ID, r.ROW_ID
;

-- ============================================================
-- PAGE 51 – CHECK LOAN REQUESTS  (FSD #300–#304)
-- Per FSD #301: NO Amount Repaid / Outstanding / Authorized On /
-- Repaid On columns; Status column replaced by Instalment
-- Schedule 'View' button column.
-- ============================================================
SELECT
    l.LOAN_ID,
    l.LOAN_NO                               AS REF_NO,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = l.FOLIO_ID)        AS FUND,
    l.AMOUNT + ROUND(l.AMOUNT * l.INTEREST_RATE / 100, 2)
                                            AS TOTAL_REPAYABLE,
    l.AMOUNT                                AS LOAN_AMOUNT,
    ROUND(l.AMOUNT * l.INTEREST_RATE / 100, 2)
                                            AS INTEREST_AMOUNT,
    l.MONTHLY_INSTALMENT,
    l.INSTALMENT_MONTHS                     AS INSTALMENT_PERIOD,
    -- Instalment Schedule View button (FSD #301/#303)
    '<button type="button" class="epf-btn-link epf-view-schedule" data-loan-id="'
        || l.LOAN_ID || '">View</button>'   AS INSTALMENT_SCHEDULE
FROM EPF_LOAN_REQUESTS  l
JOIN EPF_FOLIOS         f ON f.FOLIO_ID = l.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = l.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE l.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'PENDING_CHECKER'
ORDER BY l.MAKER_DATE
;

-- ============================================================
-- PAGE 51 – Instalment Schedule popup query  (FSD #232, #303)
-- ============================================================
SELECT
    ls.INSTALMENT_NO,
    ls.TOTAL_DUE         AS INSTALMENT_AMOUNT,
    ls.PRINCIPAL         AS LOAN_AMOUNT,
    ls.INTEREST          AS INTEREST_AMOUNT,
    TO_CHAR(ls.DUE_DATE, 'DD-Mon-YY') AS DUE_DATE
FROM EPF_LOAN_SCHEDULE ls
WHERE ls.LOAN_ID = :P51_VIEW_LOAN_ID
ORDER BY ls.INSTALMENT_NO
;

-- ============================================================
-- PAGE 52 – CHECK WITHDRAWAL REQUESTS  (FSD #305–#308)
-- Same as View All but no Status column; PENDING_CHECKER only.
-- ============================================================
SELECT
    w.WD_ID,
    w.WD_NO                                 AS REF_NO,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = w.FOLIO_ID)        AS FUND,
    CASE WHEN w.WD_TYPE = 'FULL'
         THEN 'Full Withdrawal'
         ELSE TO_CHAR(w.AMOUNT, 'FM999G999G999G990D00') END
                                            AS WITHDRAWAL_AMOUNT,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = w.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING
FROM EPF_WITHDRAWAL_REQUESTS w
JOIN EPF_FOLIOS              f ON f.FOLIO_ID = w.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = w.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE w.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(w.STATUS_ID) = 'PENDING_CHECKER'
ORDER BY w.MAKER_DATE
;

-- ============================================================
-- PAGE 53 – CHECK LIEN REQUESTS  (FSD #309–#313)
-- :P53_TOGGLE = 'MARK' | 'UNMARK'  (Lien Marking / Unmarking toggle)
-- Status column shows the request type label (FSD #310).
-- ============================================================
SELECT
    lr.LIEN_ID,
    lr.LIEN_NO                              AS REF_NO,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = lr.FOLIO_ID)       AS FUND,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = lr.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING,
    CASE lr.REQUEST_TYPE
        WHEN 'MARK' THEN 'Lien Marking Request'
        ELSE 'Lien Unmarking Request'
    END                                     AS REQUEST_STATUS
FROM EPF_LIEN_REQUESTS  lr
JOIN EPF_FOLIOS         f ON f.FOLIO_ID = lr.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = lr.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE lr.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID) = 'PENDING_CHECKER'
  AND lr.REQUEST_TYPE = NVL(:P53_TOGGLE, 'MARK')
ORDER BY lr.MAKER_DATE
;

-- ============================================================
-- PAGE 54 – CHECK NOC REQUESTS  (FSD #314–#315)
-- Columns per #315: Checkbox, Name, CNIC/NICOP, Folio, Fund,
-- Loan Outstanding, Lien Status, Current Balance.
-- ============================================================
SELECT
    n.NOC_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = n.FOLIO_ID)        AS FUND,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = n.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING,
    CASE NVL(f.LIEN_MARKED, 'N')
        WHEN 'Y' THEN 'Lien Marked' ELSE 'Lien Unmarked'
    END                                     AS LIEN_STATUS
FROM EPF_NOC_REQUESTS   n
JOIN EPF_FOLIOS         f ON f.FOLIO_ID = n.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = n.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE n.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(n.STATUS_ID) = 'PENDING_CHECKER'
ORDER BY n.MAKER_DATE
;

-- ============================================================
-- PAGE 55 – CHECK DISABLED EMPLOYEES  (FSD #318–#319)
-- Columns per #319: Checkbox, Name, CNIC/NICOP, Folio, Fund,
-- NOC Issued (Yes), Current Balance.
-- ============================================================
SELECT
    dr.REQ_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = dr.FOLIO_ID)       AS FUND,
    'Yes'                                   AS NOC_ISSUED
FROM EPF_EMP_DISABLE_REQUESTS dr
JOIN EPF_FOLIOS               f ON f.FOLIO_ID = dr.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES  uc ON uc.FOLIO_ID = dr.FOLIO_ID
LEFT JOIN EPF_USERS           u  ON u.USER_ID   = uc.USER_ID
WHERE dr.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(dr.STATUS_ID) = 'PENDING_CHECKER'
ORDER BY dr.MAKER_DATE
;

-- ============================================================
-- PAGE 45 – DISABLE EMPLOYEES (Maker)  (FSD #273–#275)
-- Only employees whose NOC has been issued (#275).  Checkboxes
-- disabled for rows already Pending at Checker (#274).
-- ============================================================
SELECT
    f.FOLIO_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = f.FOLIO_ID)        AS FUND,
    CASE WHEN EXISTS (
             SELECT 1 FROM EPF_EMP_DISABLE_REQUESTS dr
              WHERE dr.FOLIO_ID = f.FOLIO_ID
                AND EPF_STATUS_PKG.GET_CODE(dr.STATUS_ID) = 'PENDING_CHECKER')
         THEN 'Pending at Checker' ELSE 'Active'
    END                                     AS STATUS_LABEL,
    CASE WHEN EXISTS (
             SELECT 1 FROM EPF_EMP_DISABLE_REQUESTS dr
              WHERE dr.FOLIO_ID = f.FOLIO_ID
                AND EPF_STATUS_PKG.GET_CODE(dr.STATUS_ID) = 'PENDING_CHECKER')
         THEN 'Y' ELSE 'N'
    END                                     AS CHECKBOX_DISABLED_YN
FROM EPF_FOLIOS f
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE f.COMPANY_ID = :APP_COMPANY_ID
  AND NVL(f.NOC_ISSUED, 'N')  = 'Y'
  AND NVL(f.IS_DISABLED, 'N') = 'N'
ORDER BY u.FULL_NAME
;

-- ============================================================
-- PAGE 43 – LIEN MARK / UNMARK page query  (FSD #239–#242)
-- :P43_TOGGLE = 'MARKED' | 'UNMARKED'
-- ============================================================
SELECT
    f.FOLIO_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = f.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING,
    CASE NVL(f.LIEN_MARKED, 'N')
        WHEN 'Y' THEN 'Lien Marked' ELSE 'Lien Unmarked'
    END                                     AS LIEN_STATUS,
    -- Disable checkbox if a lien request is already pending
    CASE WHEN EXISTS (
             SELECT 1 FROM EPF_LIEN_REQUESTS lr
              WHERE lr.FOLIO_ID = f.FOLIO_ID
                AND EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)
                        IN ('PENDING_CHECKER','PENDING_AUTHORIZER'))
         THEN 'Y' ELSE 'N'
    END                                     AS CHECKBOX_DISABLED_YN
FROM EPF_FOLIOS f
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE f.COMPANY_ID = :APP_COMPANY_ID
  AND NVL(f.IS_DISABLED, 'N') = 'N'
  AND NVL(f.LIEN_MARKED, 'N') = CASE NVL(:P43_TOGGLE, 'MARKED')
                                     WHEN 'MARKED' THEN 'Y' ELSE 'N' END
ORDER BY u.FULL_NAME
;

-- ============================================================
-- PAGE 44 – NOC ISSUANCE page query  (FSD #251–#252)
-- Issue NOC button + checkbox disabled for outstanding loans.
-- ============================================================
SELECT
    f.FOLIO_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT NVL(SUM(l.OUTSTANDING), 0)
       FROM EPF_LOAN_REQUESTS l
      WHERE l.FOLIO_ID = f.FOLIO_ID
        AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED')
                                            AS LOAN_OUTSTANDING,
    CASE NVL(f.LIEN_MARKED, 'N')
        WHEN 'Y' THEN 'Lien Marked' ELSE 'Lien Unmarked'
    END                                     AS LIEN_STATUS,
    CASE WHEN (SELECT NVL(SUM(l.OUTSTANDING), 0)
                 FROM EPF_LOAN_REQUESTS l
                WHERE l.FOLIO_ID = f.FOLIO_ID
                  AND EPF_STATUS_PKG.GET_CODE(l.STATUS_ID) = 'AUTHORIZED') > 0
           OR NVL(f.LIEN_MARKED, 'N') = 'Y'
         THEN 'Y' ELSE 'N'
    END                                     AS CHECKBOX_DISABLED_YN
FROM EPF_FOLIOS f
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE f.COMPANY_ID = :APP_COMPANY_ID
  AND NVL(f.NOC_ISSUED, 'N')  = 'N'
  AND NVL(f.IS_DISABLED, 'N') = 'N'
ORDER BY u.FULL_NAME
;

-- ============================================================
-- PAGE 60 – FEATURE ACCESS: Pending Requests section
-- (FSD #325/#329)  :P60_FEATURE_CODE = 'LOAN' | 'WITHDRAWAL'
-- :P60_REQUEST_TYPE_FILTER = 'ALL' | 'PENDING_ADDITION' | 'PENDING_DELETION'
-- ============================================================
SELECT
    fa.ACCESS_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = fa.FOLIO_ID)       AS FUND,
    INITCAP(REPLACE(fa.ACCESS_STATUS, '_', ' '))
                                            AS FEATURE_STATUS
FROM EPF_FEATURE_ACCESS fa
JOIN EPF_FOLIOS         f ON f.FOLIO_ID = fa.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = fa.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE fa.COMPANY_ID   = :APP_COMPANY_ID
  AND fa.FEATURE_CODE = :P60_FEATURE_CODE
  AND fa.ACCESS_STATUS IN ('PENDING_ADDITION', 'PENDING_DELETION')
  AND (NVL(:P60_REQUEST_TYPE_FILTER, 'ALL') = 'ALL'
       OR fa.ACCESS_STATUS = :P60_REQUEST_TYPE_FILTER)
ORDER BY fa.MAKER_DATE
;

-- ============================================================
-- PAGE 60 – FEATURE ACCESS: List of Added Employees (view-only)
-- (FSD #327/#331) Pending rows greyed out with hover tooltip.
-- ============================================================
SELECT
    fa.ACCESS_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING m
       JOIN EPF_FUNDS fn ON fn.FUND_ID = m.FUND_ID
      WHERE m.FOLIO_ID = fa.FOLIO_ID)       AS FUND,
    INITCAP(REPLACE(fa.ACCESS_STATUS, '_', ' '))
                                            AS FEATURE_STATUS,
    CASE WHEN fa.ACCESS_STATUS != 'ENABLED' THEN 'epf-row-greyed' END
                                            AS ROW_CSS_CLASS,
    CASE fa.ACCESS_STATUS
        WHEN 'PENDING_ADDITION' THEN 'Addition request is pending at Checker'
        WHEN 'PENDING_DELETION' THEN 'Deletion request is pending at Checker'
    END                                     AS HOVER_TEXT
FROM EPF_FEATURE_ACCESS fa
JOIN EPF_FOLIOS         f ON f.FOLIO_ID = fa.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = fa.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE fa.COMPANY_ID   = :APP_COMPANY_ID
  AND fa.FEATURE_CODE = :P60_FEATURE_CODE
ORDER BY u.FULL_NAME
;

-- ============================================================
-- PAGE 60 – REALLOC GROUPS query  (FSD #287, #332–#333)
-- Includes pending-edit values (strikethrough red old / green new)
-- ============================================================
SELECT
    g.GROUP_ID,
    g.GROUP_NAME,
    g.MM_LIMIT,
    g.DEBT_LIMIT,
    g.EQUITY_LIMIT,
    g.IS_DEFAULT,
    EPF_STATUS_PKG.GET_CODE(g.STATUS_ID)    AS STATUS_CODE,
    CASE WHEN EPF_STATUS_PKG.GET_CODE(g.STATUS_ID) = 'PENDING_CHECKER'
         THEN 'Y' ELSE 'N' END              AS PENDING_AT_CHECKER_YN,
    -- Pending new values from the edit JSON (FSD #324 strike-old / green-new)
    JSON_VALUE(g.PENDING_CHANGES_JSON, '$.group_name')   AS NEW_GROUP_NAME,
    JSON_VALUE(g.PENDING_CHANGES_JSON, '$.mm_limit')     AS NEW_MM_LIMIT,
    JSON_VALUE(g.PENDING_CHANGES_JSON, '$.debt_limit')   AS NEW_DEBT_LIMIT,
    JSON_VALUE(g.PENDING_CHANGES_JSON, '$.equity_limit') AS NEW_EQUITY_LIMIT,
    (SELECT COUNT(*) FROM EPF_REALLOC_GROUP_MEMBERS m
      WHERE m.GROUP_ID = g.GROUP_ID)        AS MEMBER_COUNT
FROM EPF_REALLOC_GROUPS g
WHERE g.COMPANY_ID = :APP_COMPANY_ID
ORDER BY g.IS_DEFAULT DESC, g.GROUP_ID
;

-- ============================================================
-- PAGE 60 – REALLOC GROUP MEMBERS query  (FSD #333)
-- ============================================================
SELECT
    m.MEMBER_ID,
    m.GROUP_ID,
    u.FULL_NAME                             AS NAME,
    u.CNIC                                  AS CNIC_NICOP,
    f.FOLIO_NUMBER                          AS FOLIO,
    (SELECT MIN(fn.FUND_NAME)
       FROM EPF_FOLIO_FUND_MAPPING fm
       JOIN EPF_FUNDS fn ON fn.FUND_ID = fm.FUND_ID
      WHERE fm.FOLIO_ID = m.FOLIO_ID)       AS FUND,
    INITCAP(REPLACE(m.ACCESS_STATUS, '_', ' '))
                                            AS FEATURE_STATUS,
    CASE WHEN m.ACCESS_STATUS != 'ENABLED' THEN 'epf-row-greyed' END
                                            AS ROW_CSS_CLASS
FROM EPF_REALLOC_GROUP_MEMBERS m
JOIN EPF_FOLIOS f ON f.FOLIO_ID = m.FOLIO_ID
LEFT JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = m.FOLIO_ID
LEFT JOIN EPF_USERS          u  ON u.USER_ID   = uc.USER_ID
WHERE m.GROUP_ID = :P60_GROUP_ID
ORDER BY u.FULL_NAME
;

-- ============================================================
-- NOTIFICATIONS query (bell icon / alerts panel)
-- ============================================================
SELECT
    n.NOTIFICATION_ID,
    n.TITLE,
    n.MESSAGE,
    n.REF_TYPE,
    n.REF_ID,
    n.IS_READ,
    TO_CHAR(n.CREATED_DATE, 'DD-Mon-YY HH:MI am') AS CREATED_DISP
FROM EPF_NOTIFICATIONS n
WHERE n.COMPANY_ID = :APP_COMPANY_ID
  AND n.USER_ID    = :APP_USER_ID
ORDER BY n.CREATED_DATE DESC
;

-- ============================================================
-- LOV: REQUEST_TYPE_LOV (advanced search filter)
-- ============================================================
SELECT 'Contribution Uploads' AS DISPLAY_VALUE, 'CONTRIB'    AS RETURN_VALUE FROM DUAL UNION ALL
SELECT 'Loan Requests',                          'LOAN'                      FROM DUAL UNION ALL
SELECT 'Withdrawal Requests',                    'WITHDRAWAL'                FROM DUAL UNION ALL
SELECT 'Lien Requests',                          'LIEN'                      FROM DUAL UNION ALL
SELECT 'NOC Requests',                           'NOC'                       FROM DUAL
;

-- ============================================================
-- LOV: REQUEST_STATUS_LOV (status filter; codes from EPF_STATUSES)
-- ============================================================
SELECT s.STATUS_DISPLAY                     AS DISPLAY_VALUE,
       EPF_STATUS_PKG.GET_CODE(s.STATUS_ID) AS RETURN_VALUE
FROM EPF_STATUSES s
WHERE s.CATEGORY_CODE = 'REQUEST'
  AND EPF_STATUS_PKG.GET_CODE(s.STATUS_ID)
          IN ('PENDING_CHECKER','PENDING_AUTHORIZER','AUTHORIZED','REJECTED')
ORDER BY s.STATUS_DISPLAY
;

-- ============================================================
-- LOV: PENDING_REQUEST_TYPE_LOV (Settings Pending Requests dropdown,
-- FSD #325/#329: All / Pending Deletion / Pending Addition)
-- ============================================================
SELECT 'All'              AS DISPLAY_VALUE, 'ALL'              AS RETURN_VALUE FROM DUAL UNION ALL
SELECT 'Pending Deletion',                  'PENDING_DELETION'                 FROM DUAL UNION ALL
SELECT 'Pending Addition',                  'PENDING_ADDITION'                 FROM DUAL
;

-- ============================================================
-- End of ir_queries.sql
-- ============================================================
