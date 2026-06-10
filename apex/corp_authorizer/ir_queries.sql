-- ============================================================
-- FILE: /home/user/EPF/apex/corp_authorizer/ir_queries.sql
-- EPF PORTAL  –  Corporate Authorizer Module – IR Queries
-- These SQL statements are pasted into APEX Interactive Reports
-- as the "Source SQL" for each report region.
-- Binds: :APP_COMPANY_ID, :APP_USER_COMPANY_ID
-- FSD validations: #336-345
-- ============================================================

-- ============================================================
-- PAGE 71  –  Authorize Contribution Uploads IR
-- Filters: STATUS_CODE = 'PENDING_AUTHORIZER'
--          AND this authorizer has NOT yet decided.
-- Columns: Batch No, Ref Range, Created By, Date, Fund,
--          Total Amount, Total Employees, Status,
--          Approvals Progress (X of Y), Checkbox select.
-- ============================================================
SELECT
    cb.BATCH_ID,
    cb.BATCH_NO,
    ( SELECT MIN(CONCAT('CB-', TO_CHAR(ROW_ID)))
        FROM EPF_CONTRIB_BATCH_ROWS r2
       WHERE r2.BATCH_ID = cb.BATCH_ID ) AS REF_RANGE_FROM,
    cb.CONTRIBUTION_MONTH,
    f.FUND_NAME,
    cb.TOTAL_AMOUNT,
    cb.TOTAL_EMPLOYEES,
    cb.MAKER_DATE                         AS CREATED_DATE,
    u_mk.FULL_NAME                        AS CREATED_BY,
    EPF_STATUS_PKG.GET_CODE(cb.STATUS_ID) AS STATUS_CODE,
    'Pending at Authorizer'               AS STATUS_DISPLAY,
    -- Per-authorizer decisions sub-query
    ( SELECT LISTAGG(u2.FULL_NAME
                  || ': ' || INITCAP(LOWER(d2.DECISION)),
                  '; ')
               WITHIN GROUP (ORDER BY d2.DECISION_DATE)
        FROM EPF_AUTHORIZER_DECISIONS d2
        JOIN EPF_USER_COMPANIES       uc2 ON uc2.USER_COMPANY_ID = d2.AUTHORIZER_UCID
        JOIN EPF_USERS                u2  ON u2.USER_ID          = uc2.USER_ID
       WHERE d2.REQUEST_TYPE = 'CONTRIB'
         AND d2.REQUEST_ID   = cb.BATCH_ID
    ) AS DECISIONS_SUMMARY,
    cb.AUTHORIZER_APPROVED_COUNT          AS APPROVALS_RECEIVED,
    cb.AUTHORIZER_COUNT                   AS APPROVALS_REQUIRED
FROM EPF_CONTRIB_BATCHES    cb
JOIN EPF_FUNDS              f    ON f.FUND_ID      = cb.FUND_ID
JOIN EPF_USER_COMPANIES     uc_m ON uc_m.USER_COMPANY_ID = cb.MAKER_UCID
JOIN EPF_USERS              u_mk ON u_mk.USER_ID   = uc_m.USER_ID
WHERE cb.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(cb.STATUS_ID) = 'PENDING_AUTHORIZER'
  -- Only show requests where THIS authorizer hasn't decided yet
  AND NOT EXISTS (
      SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
       WHERE d.REQUEST_TYPE    = 'CONTRIB'
         AND d.REQUEST_ID      = cb.BATCH_ID
         AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
  )
ORDER BY cb.MAKER_DATE DESC;

-- ============================================================
-- PAGE 72  –  Authorize Loan Requests IR
-- ============================================================
SELECT
    lr.LOAN_ID,
    lr.LOAN_NO,
    f.FOLIO_NUMBER,
    fn.FUND_NAME,
    u_emp.FULL_NAME                        AS EMPLOYEE_NAME,
    u_emp.CNIC                             AS CNIC,
    lr.AMOUNT,
    lr.INTEREST_TYPE,
    lr.INTEREST_RATE,
    lr.INSTALMENT_MONTHS,
    lr.MONTHLY_INSTALMENT,
    lr.MAKER_DATE                          AS CREATED_DATE,
    u_mk.FULL_NAME                         AS CREATED_BY,
    EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)  AS STATUS_CODE,
    ( SELECT LISTAGG(u2.FULL_NAME || ': ' || INITCAP(LOWER(d2.DECISION)), '; ')
               WITHIN GROUP (ORDER BY d2.DECISION_DATE)
        FROM EPF_AUTHORIZER_DECISIONS d2
        JOIN EPF_USER_COMPANIES uc2 ON uc2.USER_COMPANY_ID = d2.AUTHORIZER_UCID
        JOIN EPF_USERS          u2  ON u2.USER_ID          = uc2.USER_ID
       WHERE d2.REQUEST_TYPE = 'LOAN' AND d2.REQUEST_ID = lr.LOAN_ID
    ) AS DECISIONS_SUMMARY,
    lr.AUTHORIZER_APPROVED_COUNT           AS APPROVALS_RECEIVED,
    lr.AUTHORIZER_COUNT                    AS APPROVALS_REQUIRED
FROM EPF_LOAN_REQUESTS       lr
JOIN EPF_FOLIOS              f    ON f.FOLIO_ID    = lr.FOLIO_ID
JOIN EPF_FUNDS               fn   ON fn.FUND_ID    = f.FUND_ID
JOIN EPF_EMPLOYEES           emp  ON emp.EMPLOYEE_ID = f.EMPLOYEE_ID
JOIN EPF_USERS               u_emp ON u_emp.USER_ID = emp.USER_ID
JOIN EPF_USER_COMPANIES      uc_m ON uc_m.USER_COMPANY_ID = lr.MAKER_UCID
JOIN EPF_USERS               u_mk ON u_mk.USER_ID  = uc_m.USER_ID
WHERE lr.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID) = 'PENDING_AUTHORIZER'
  AND NOT EXISTS (
      SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
       WHERE d.REQUEST_TYPE = 'LOAN' AND d.REQUEST_ID = lr.LOAN_ID
         AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
  )
ORDER BY lr.MAKER_DATE DESC;

-- ============================================================
-- PAGE 73  –  Authorize Withdrawal Requests IR
-- ============================================================
SELECT
    wr.WD_ID,
    wr.WD_NO,
    f.FOLIO_NUMBER,
    fn.FUND_NAME,
    u_emp.FULL_NAME                        AS EMPLOYEE_NAME,
    u_emp.CNIC                             AS CNIC,
    NVL(wr.AMOUNT, 0)                      AS AMOUNT,
    wr.WD_TYPE,
    wr.MAKER_DATE                          AS CREATED_DATE,
    u_mk.FULL_NAME                         AS CREATED_BY,
    EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID)  AS STATUS_CODE,
    ( SELECT LISTAGG(u2.FULL_NAME || ': ' || INITCAP(LOWER(d2.DECISION)), '; ')
               WITHIN GROUP (ORDER BY d2.DECISION_DATE)
        FROM EPF_AUTHORIZER_DECISIONS d2
        JOIN EPF_USER_COMPANIES uc2 ON uc2.USER_COMPANY_ID = d2.AUTHORIZER_UCID
        JOIN EPF_USERS          u2  ON u2.USER_ID          = uc2.USER_ID
       WHERE d2.REQUEST_TYPE = 'WITHDRAWAL' AND d2.REQUEST_ID = wr.WD_ID
    ) AS DECISIONS_SUMMARY,
    wr.AUTHORIZER_APPROVED_COUNT           AS APPROVALS_RECEIVED,
    wr.AUTHORIZER_COUNT                    AS APPROVALS_REQUIRED
FROM EPF_WITHDRAWAL_REQUESTS wr
JOIN EPF_FOLIOS              f    ON f.FOLIO_ID    = wr.FOLIO_ID
JOIN EPF_FUNDS               fn   ON fn.FUND_ID    = f.FUND_ID
JOIN EPF_EMPLOYEES           emp  ON emp.EMPLOYEE_ID = f.EMPLOYEE_ID
JOIN EPF_USERS               u_emp ON u_emp.USER_ID = emp.USER_ID
JOIN EPF_USER_COMPANIES      uc_m ON uc_m.USER_COMPANY_ID = wr.MAKER_UCID
JOIN EPF_USERS               u_mk ON u_mk.USER_ID  = uc_m.USER_ID
WHERE wr.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID) = 'PENDING_AUTHORIZER'
  AND NOT EXISTS (
      SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
       WHERE d.REQUEST_TYPE = 'WITHDRAWAL' AND d.REQUEST_ID = wr.WD_ID
         AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
  )
ORDER BY wr.MAKER_DATE DESC;

-- ============================================================
-- PAGE 74  –  Authorize Lien Requests IR
-- ============================================================
SELECT
    lr.LIEN_ID,
    lr.LIEN_NO,
    f.FOLIO_NUMBER,
    fn.FUND_NAME,
    u_emp.FULL_NAME                        AS EMPLOYEE_NAME,
    u_emp.CNIC                             AS CNIC,
    lr.REQUEST_TYPE                        AS LIEN_TYPE,
    NVL(f.LIEN_MARKED,'N')                 AS CURRENT_LIEN_STATUS,
    lr.MAKER_DATE                          AS CREATED_DATE,
    u_mk.FULL_NAME                         AS CREATED_BY,
    EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)  AS STATUS_CODE,
    ( SELECT LISTAGG(u2.FULL_NAME || ': ' || INITCAP(LOWER(d2.DECISION)), '; ')
               WITHIN GROUP (ORDER BY d2.DECISION_DATE)
        FROM EPF_AUTHORIZER_DECISIONS d2
        JOIN EPF_USER_COMPANIES uc2 ON uc2.USER_COMPANY_ID = d2.AUTHORIZER_UCID
        JOIN EPF_USERS          u2  ON u2.USER_ID          = uc2.USER_ID
       WHERE d2.REQUEST_TYPE = 'LIEN' AND d2.REQUEST_ID = lr.LIEN_ID
    ) AS DECISIONS_SUMMARY,
    lr.AUTHORIZER_APPROVED_COUNT           AS APPROVALS_RECEIVED,
    lr.AUTHORIZER_COUNT                    AS APPROVALS_REQUIRED
FROM EPF_LIEN_REQUESTS       lr
JOIN EPF_FOLIOS              f    ON f.FOLIO_ID    = lr.FOLIO_ID
JOIN EPF_FUNDS               fn   ON fn.FUND_ID    = f.FUND_ID
JOIN EPF_EMPLOYEES           emp  ON emp.EMPLOYEE_ID = f.EMPLOYEE_ID
JOIN EPF_USERS               u_emp ON u_emp.USER_ID = emp.USER_ID
JOIN EPF_USER_COMPANIES      uc_m ON uc_m.USER_COMPANY_ID = lr.MAKER_UCID
JOIN EPF_USERS               u_mk ON u_mk.USER_ID  = uc_m.USER_ID
WHERE lr.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID) = 'PENDING_AUTHORIZER'
  AND NOT EXISTS (
      SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
       WHERE d.REQUEST_TYPE = 'LIEN' AND d.REQUEST_ID = lr.LIEN_ID
         AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
  )
ORDER BY lr.MAKER_DATE DESC;

-- ============================================================
-- PAGE 75  –  Authorize NOC Requests IR
-- ============================================================
SELECT
    nr.NOC_ID,
    nr.NOC_NO,
    f.FOLIO_NUMBER,
    fn.FUND_NAME,
    u_emp.FULL_NAME                        AS EMPLOYEE_NAME,
    u_emp.CNIC                             AS CNIC,
    NVL(f.LIEN_MARKED,'N')                 AS LIEN_STATUS,
    nr.MAKER_DATE                          AS CREATED_DATE,
    u_mk.FULL_NAME                         AS CREATED_BY,
    EPF_STATUS_PKG.GET_CODE(nr.STATUS_ID)  AS STATUS_CODE,
    ( SELECT LISTAGG(u2.FULL_NAME || ': ' || INITCAP(LOWER(d2.DECISION)), '; ')
               WITHIN GROUP (ORDER BY d2.DECISION_DATE)
        FROM EPF_AUTHORIZER_DECISIONS d2
        JOIN EPF_USER_COMPANIES uc2 ON uc2.USER_COMPANY_ID = d2.AUTHORIZER_UCID
        JOIN EPF_USERS          u2  ON u2.USER_ID          = uc2.USER_ID
       WHERE d2.REQUEST_TYPE = 'NOC' AND d2.REQUEST_ID = nr.NOC_ID
    ) AS DECISIONS_SUMMARY,
    nr.AUTHORIZER_APPROVED_COUNT           AS APPROVALS_RECEIVED,
    nr.AUTHORIZER_COUNT                    AS APPROVALS_REQUIRED
FROM EPF_NOC_REQUESTS        nr
JOIN EPF_FOLIOS              f    ON f.FOLIO_ID    = nr.FOLIO_ID
JOIN EPF_FUNDS               fn   ON fn.FUND_ID    = f.FUND_ID
JOIN EPF_EMPLOYEES           emp  ON emp.EMPLOYEE_ID = f.EMPLOYEE_ID
JOIN EPF_USERS               u_emp ON u_emp.USER_ID = emp.USER_ID
JOIN EPF_USER_COMPANIES      uc_m ON uc_m.USER_COMPANY_ID = nr.MAKER_UCID
JOIN EPF_USERS               u_mk ON u_mk.USER_ID  = uc_m.USER_ID
WHERE nr.COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(nr.STATUS_ID) = 'PENDING_AUTHORIZER'
  AND NOT EXISTS (
      SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
       WHERE d.REQUEST_TYPE = 'NOC' AND d.REQUEST_ID = nr.NOC_ID
         AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
  )
ORDER BY nr.MAKER_DATE DESC;

-- ============================================================
-- PAGE 76  –  Authorizer Settings: Loan Settings View
-- Shows current vs pending settings in a single row.
-- Used to render the strikethrough-red / green diff view.
-- ============================================================
SELECT
    cs.COMPANY_ID,
    -- Current (live) settings
    cs.LOAN_INTEREST_TYPE          AS CURRENT_INTEREST_TYPE,
    cs.LOAN_INTEREST_RATE          AS CURRENT_INTEREST_RATE,
    cs.LOAN_LIMIT_PCT              AS CURRENT_LOAN_LIMIT_PCT,
    cs.LOAN_MAX_INSTALMENT_MONTHS  AS CURRENT_MAX_MONTHS,
    cs.FLOATING_RATE_TENURE        AS CURRENT_FRT,
    -- Pending (proposed) settings
    cs.PENDING_INTEREST_TYPE       AS PENDING_INTEREST_TYPE,
    cs.PENDING_INTEREST_RATE       AS PENDING_INTEREST_RATE,
    cs.PENDING_LOAN_LIMIT_PCT      AS PENDING_LOAN_LIMIT_PCT,
    cs.PENDING_MAX_INSTALMENT_MONTHS AS PENDING_MAX_MONTHS,
    cs.PENDING_FLOATING_RATE_TENURE  AS PENDING_FRT,
    -- Workflow metadata
    cs.LOAN_SETTINGS_STATUS        AS SETTINGS_STATUS,
    cs.LOAN_SETTINGS_MAKER_DATE    AS MAKER_DATE,
    u_mk.FULL_NAME                 AS MAKER_NAME,
    -- Change indicator: Y if there are pending changes to authorize
    CASE WHEN cs.LOAN_SETTINGS_STATUS = 'PENDING_AUTHORIZER' THEN 'Y' ELSE 'N' END AS HAS_PENDING
FROM EPF_COMPANY_SETTINGS    cs
LEFT JOIN EPF_USER_COMPANIES uc_m ON uc_m.USER_COMPANY_ID = cs.LOAN_SETTINGS_MAKER_UCID
LEFT JOIN EPF_USERS          u_mk ON u_mk.USER_ID = uc_m.USER_ID
WHERE cs.COMPANY_ID = :APP_COMPANY_ID;

-- ============================================================
-- LOV: Authorizer Decision (APPROVE / REJECT)
-- Used on all authorize pages for the decision radio group.
-- ============================================================
SELECT 'Approve' AS D, 'APPROVE' AS R FROM DUAL
UNION ALL
SELECT 'Reject',        'REJECT'       FROM DUAL;

-- ============================================================
-- Sub-query: Who has decided per request (for status popup)
-- Used as an inline query or separate IR region on detail popup.
-- Bind: :P7X_REQUEST_TYPE, :P7X_REQUEST_ID
-- ============================================================
SELECT
    u.FULL_NAME          AS AUTHORIZER_NAME,
    u.EMAIL              AS AUTHORIZER_EMAIL,
    NVL(d.DECISION,'PENDING') AS DECISION,
    d.DECISION_DATE,
    d.REMARKS
FROM EPF_USER_COMPANIES  uc
JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
JOIN EPF_USERS           u   ON u.USER_ID           = uc.USER_ID
LEFT JOIN EPF_AUTHORIZER_DECISIONS d
    ON d.AUTHORIZER_UCID = uc.USER_COMPANY_ID
   AND d.REQUEST_TYPE    = :P7X_REQUEST_TYPE
   AND d.REQUEST_ID      = :P7X_REQUEST_ID
WHERE uc.COMPANY_ID = :APP_COMPANY_ID
  AND ucr.IS_ACTIVE  = 'Y'
  AND r.ROLE_CODE    = 'CORP_AUTHORIZER'
  AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE'
ORDER BY uc.USER_COMPANY_ID;

-- ============================================================
-- END of corp_authorizer/ir_queries.sql
-- ============================================================
