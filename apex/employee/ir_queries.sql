-- ============================================================
-- FILE: /home/user/EPF/apex/employee/ir_queries.sql
-- EPF PORTAL  –  Employee Module – IR / Report Queries
-- Paste as "Source SQL" in APEX Interactive Report regions.
-- Binds: :APP_FOLIO_ID (employee's own folio)
--        :APP_USER_ID, :APP_COMPANY_ID
--        :P80_DATE_FROM, :P80_DATE_TO (dashboard filters)
--        :P81_PERIOD_TYPE, :P81_DATE_FROM, :P81_DATE_TO
-- FSD validations: #346-372
-- ============================================================

-- ============================================================
-- PAGE 80  –  Employee Dashboard: Fund Overview Table
-- Columns: Sub-Funds (MM/Debt/Equity/Total), Units, NAV,
--          Current Balance, Net Investment, Profit/(Loss)
-- FSD #348
-- ============================================================
SELECT
    f.FUND_NAME,
    NVL(ffm.SUBFUND_CODE, 'TOTAL')       AS SUBFUND_NAME,
    NVL(ffm.UNITS, 0)                    AS UNITS,
    NVL(ffm.LATEST_NAV, 0)              AS NAV,
    ROUND(NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0), 2) AS CURRENT_BALANCE,
    NVL(ffm.NET_INVESTMENT, 0)           AS NET_INVESTMENT,
    ROUND(
        NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0)
      - NVL(ffm.NET_INVESTMENT,0),
    2) AS PROFIT_LOSS
FROM EPF_FOLIO_FUND_MAPPING ffm
JOIN EPF_FUNDS              f   ON f.FUND_ID = ffm.FUND_ID
WHERE ffm.FOLIO_ID = :APP_FOLIO_ID
  AND (
       :P80_DATE_FROM IS NULL
    OR ffm.EFFECTIVE_DATE >= TO_DATE(:P80_DATE_FROM, 'YYYY-MM-DD')
  )
  AND (
       :P80_DATE_TO IS NULL
    OR ffm.EFFECTIVE_DATE <= TO_DATE(:P80_DATE_TO, 'YYYY-MM-DD')
  )
UNION ALL
-- Totals row
SELECT
    f2.FUND_NAME       AS FUND_NAME,
    'Total'            AS SUBFUND_NAME,
    SUM(NVL(ffm2.UNITS, 0)),
    NULL               AS NAV,
    SUM(ROUND(NVL(ffm2.UNITS,0) * NVL(ffm2.LATEST_NAV,0), 2)),
    SUM(NVL(ffm2.NET_INVESTMENT,0)),
    SUM(ROUND(NVL(ffm2.UNITS,0) * NVL(ffm2.LATEST_NAV,0) - NVL(ffm2.NET_INVESTMENT,0), 2))
FROM EPF_FOLIO_FUND_MAPPING ffm2
JOIN EPF_FUNDS              f2   ON f2.FUND_ID = ffm2.FUND_ID
WHERE ffm2.FOLIO_ID = :APP_FOLIO_ID
  AND (
       :P80_DATE_FROM IS NULL
    OR ffm2.EFFECTIVE_DATE >= TO_DATE(:P80_DATE_FROM, 'YYYY-MM-DD')
  )
  AND (
       :P80_DATE_TO IS NULL
    OR ffm2.EFFECTIVE_DATE <= TO_DATE(:P80_DATE_TO, 'YYYY-MM-DD')
  )
GROUP BY f2.FUND_NAME
ORDER BY 1, CASE SUBFUND_NAME WHEN 'Total' THEN 'ZZZ' ELSE SUBFUND_NAME END;

-- ============================================================
-- PAGE 80  –  Dashboard Pie Chart Data (JSON for Chart.js)
-- Used in an APEX Classic Report with Format = JSON or
-- in a Chart.js initialization script.
-- FSD #349
-- ============================================================
SELECT
    ffm.SUBFUND_CODE                          AS LABEL,
    ROUND(NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0), 2) AS VALUE,
    NVL(ffm.UNITS, 0)                         AS UNITS,
    ROUND(
        (NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0))
      / NULLIF(SUM(NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0))
                OVER (PARTITION BY ffm.FOLIO_ID), 0)
      * 100, 1
    ) AS PERCENTAGE
FROM EPF_FOLIO_FUND_MAPPING ffm
WHERE ffm.FOLIO_ID = :APP_FOLIO_ID
  AND ffm.SUBFUND_CODE IS NOT NULL
  AND (
       :P80_DATE_FROM IS NULL
    OR ffm.EFFECTIVE_DATE >= TO_DATE(:P80_DATE_FROM, 'YYYY-MM-DD')
  )
  AND (
       :P80_DATE_TO IS NULL
    OR ffm.EFFECTIVE_DATE <= TO_DATE(:P80_DATE_TO, 'YYYY-MM-DD')
  )
ORDER BY ffm.SUBFUND_CODE;

-- ============================================================
-- PAGE 81  –  Account Statement Table
-- Columns: Date, Transaction, Amount, NAV, Units,
--          Employer Contribution, Employee Contribution,
--          Profit, Loan Repayment, Withdrawal, Loan Outstanding
-- FSD #352
-- ============================================================
-- Date range is resolved here using same CASE logic as in pkg
WITH date_range AS (
    SELECT
        CASE :P81_PERIOD_TYPE
            WHEN 'LAST30'     THEN TRUNC(SYSDATE) - 30
            WHEN 'LAST90'     THEN TRUNC(SYSDATE) - 90
            WHEN 'INCEPTION'  THEN DATE '1900-01-01'
            WHEN 'DATE_RANGE' THEN TO_DATE(:P81_DATE_FROM,'YYYY-MM-DD')
            ELSE TRUNC(SYSDATE) - 30
        END AS D_FROM,
        CASE :P81_PERIOD_TYPE
            WHEN 'DATE_RANGE' THEN TO_DATE(:P81_DATE_TO,'YYYY-MM-DD')
            ELSE TRUNC(SYSDATE)
        END AS D_TO
      FROM DUAL
)
SELECT
    'Contribution'              AS TRANSACTION_TYPE,
    cb.MAKER_DATE               AS TXN_DATE,
    cbr.TOTAL_AMOUNT            AS AMOUNT,
    NULL                        AS NAV,
    NULL                        AS UNITS,
    cbr.EMPLOYER_AMOUNT         AS EMPLOYER_CONTRIBUTION,
    cbr.EMPLOYEE_AMOUNT         AS EMPLOYEE_CONTRIBUTION,
    0                           AS PROFIT,
    0                           AS LOAN_REPAYMENT,
    0                           AS WITHDRAWAL,
    NULL                        AS LOAN_OUTSTANDING,
    cb.BATCH_NO                 AS REF_NO
FROM EPF_CONTRIB_BATCH_ROWS cbr
JOIN EPF_CONTRIB_BATCHES    cb  ON cb.BATCH_ID = cbr.BATCH_ID
CROSS JOIN date_range dr
WHERE cbr.FOLIO_ID   = :APP_FOLIO_ID
  AND EPF_STATUS_PKG.GET_CODE(cb.STATUS_ID) IN ('AUTHORIZED','COMPLETED')
  AND TRUNC(cb.MAKER_DATE) BETWEEN dr.D_FROM AND dr.D_TO

UNION ALL

SELECT
    'Loan Repayment',
    ls.DUE_DATE,
    ls.TOTAL_DUE,
    NULL,
    NULL,
    ls.PRINCIPAL, ls.INTEREST,
    0,
    ls.TOTAL_DUE,
    0,
    lr.OUTSTANDING,
    lr.LOAN_NO
FROM EPF_LOAN_SCHEDULE   ls
JOIN EPF_LOAN_REQUESTS   lr  ON lr.LOAN_ID = ls.LOAN_ID
CROSS JOIN date_range dr
WHERE lr.FOLIO_ID   = :APP_FOLIO_ID
  AND ls.PAID_YN    = 'Y'
  AND TRUNC(ls.DUE_DATE) BETWEEN dr.D_FROM AND dr.D_TO

UNION ALL

SELECT
    'Withdrawal',
    wr.MAKER_DATE,
    NVL(wr.AMOUNT, 0),
    NULL, NULL,
    0, 0, 0, 0,
    NVL(wr.AMOUNT, 0),
    NULL,
    wr.WD_NO
FROM EPF_WITHDRAWAL_REQUESTS wr
CROSS JOIN date_range dr
WHERE wr.FOLIO_ID  = :APP_FOLIO_ID
  AND EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID) IN ('AUTHORIZED','COMPLETED')
  AND TRUNC(wr.MAKER_DATE) BETWEEN dr.D_FROM AND dr.D_TO

ORDER BY TXN_DATE ASC, REF_NO;

-- ============================================================
-- PAGE 82  –  Certificates: Fiscal Year LOV
-- Used in the Tax Year dropdown (FSD #354).
-- Lists fiscal years from 2021-22 to the last completed fiscal
-- year (July to June in Pakistan). Derived dynamically.
-- ============================================================
SELECT
    TO_CHAR(yr - 1) || '-' || SUBSTR(TO_CHAR(yr),3,2) AS D,
    TO_CHAR(yr - 1) || '-' || SUBSTR(TO_CHAR(yr),3,2) AS R
FROM (
    SELECT LEVEL + 2020 AS yr
      FROM DUAL
   CONNECT BY LEVEL <=
       CASE WHEN TO_NUMBER(TO_CHAR(SYSDATE,'MM')) >= 7
            THEN TO_NUMBER(TO_CHAR(SYSDATE,'YYYY')) - 2020
            ELSE TO_NUMBER(TO_CHAR(SYSDATE,'YYYY')) - 2021
       END
)
ORDER BY yr DESC;

-- ============================================================
-- PAGE 83  –  Portfolio Reallocation: Current Allocation
-- Shows Current Value (PKR) and Current Allocation (%)
-- FSD #357
-- ============================================================
SELECT
    ffm.SUBFUND_CODE                            AS SUBFUND_NAME,
    ROUND(NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0), 2) AS CURRENT_VALUE_PKR,
    ROUND(
        (NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0))
      / NULLIF(SUM(NVL(ffm.UNITS,0) * NVL(ffm.LATEST_NAV,0))
                OVER (PARTITION BY ffm.FOLIO_ID), 0)
      * 100, 2
    ) AS CURRENT_ALLOCATION_PCT,
    -- Group max limits for display
    rg.MM_LIMIT     AS MAX_MM_PCT,
    rg.DEBT_LIMIT   AS MAX_DEBT_PCT,
    rg.EQUITY_LIMIT AS MAX_EQUITY_PCT,
    rg.GROUP_NAME
FROM EPF_FOLIO_FUND_MAPPING  ffm
JOIN EPF_REALLOC_GROUP_MEMBERS rgm ON rgm.FOLIO_ID = ffm.FOLIO_ID
JOIN EPF_REALLOC_GROUPS        rg  ON rg.GROUP_ID  = rgm.GROUP_ID
WHERE ffm.FOLIO_ID   = :APP_FOLIO_ID
  AND rgm.ACCESS_STATUS = 'ENABLED'
  AND ffm.SUBFUND_CODE IS NOT NULL
ORDER BY ffm.SUBFUND_CODE;

-- ============================================================
-- PAGE 84 / 85  –  Employee Loan/Withdrawal History
-- View employee's own requests (read-only).
-- FSD #259-265 equivalent for employee view.
-- ============================================================

-- Loan History
SELECT
    lr.LOAN_NO                             AS REF_NO,
    lr.AMOUNT,
    lr.INTEREST_TYPE,
    lr.INTEREST_RATE,
    lr.INSTALMENT_MONTHS,
    lr.MONTHLY_INSTALMENT,
    lr.AMOUNT_REPAID,
    lr.OUTSTANDING,
    lr.MAKER_DATE                          AS REQUEST_DATE,
    EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)  AS STATUS_CODE,
    CASE EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)
        WHEN 'PENDING_MAKER'       THEN 'Pending at Maker'
        WHEN 'PENDING_CHECKER'     THEN 'Pending at Checker'
        WHEN 'PENDING_AUTHORIZER'  THEN 'Pending at Authorizer'
        WHEN 'AUTHORIZED'          THEN 'Authorized'
        WHEN 'COMPLETED'           THEN 'Completed'
        WHEN 'REJECTED'            THEN 'Rejected'
        ELSE EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID)
    END AS STATUS_DISPLAY
FROM EPF_LOAN_REQUESTS lr
WHERE lr.FOLIO_ID              = :APP_FOLIO_ID
  AND lr.CREATED_BY_EMPLOYEE_YN = 'Y'
ORDER BY lr.MAKER_DATE DESC;

-- Withdrawal History
SELECT
    wr.WD_NO                               AS REF_NO,
    NVL(wr.AMOUNT, 0)                      AS AMOUNT,
    wr.WD_TYPE,
    wr.MAKER_DATE                          AS REQUEST_DATE,
    EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID)  AS STATUS_CODE,
    CASE EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID)
        WHEN 'PENDING_MAKER'       THEN 'Pending at Maker'
        WHEN 'PENDING_CHECKER'     THEN 'Pending at Checker'
        WHEN 'PENDING_AUTHORIZER'  THEN 'Pending at Authorizer'
        WHEN 'AUTHORIZED'          THEN 'Authorized'
        WHEN 'COMPLETED'           THEN 'Completed'
        WHEN 'REJECTED'            THEN 'Rejected'
        ELSE EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID)
    END AS STATUS_DISPLAY
FROM EPF_WITHDRAWAL_REQUESTS wr
WHERE wr.FOLIO_ID              = :APP_FOLIO_ID
  AND wr.CREATED_BY_EMPLOYEE_YN = 'Y'
ORDER BY wr.MAKER_DATE DESC;

-- ============================================================
-- PAGE 84 Step 2  –  Loan Instalment Schedule Preview
-- Generated at review step from EPF_COMPANY_SETTINGS formula.
-- Bind: :P84_AMOUNT, :P84_INSTALMENT_MONTHS, :APP_COMPANY_ID
-- FSD #363
-- ============================================================
WITH loan_params AS (
    SELECT TO_NUMBER(:P84_AMOUNT)            AS LOAN_AMT,
           TO_NUMBER(:P84_INSTALMENT_MONTHS) AS MONTHS,
           NVL(cs.LOAN_INTEREST_RATE, 0)     AS IRATE
      FROM EPF_COMPANY_SETTINGS cs
     WHERE cs.COMPANY_ID = :APP_COMPANY_ID
),
schedule AS (
    SELECT lp.LOAN_AMT,
           lp.MONTHS,
           lp.IRATE,
           lp.LOAN_AMT / GREATEST(lp.MONTHS,1)            AS PRINCIPAL_PER_INST,
           ROUND(lp.LOAN_AMT * (lp.IRATE/100), 2)         AS TOTAL_INTEREST,
           ROUND(lp.LOAN_AMT * (1 + lp.IRATE/100)
                / GREATEST(lp.MONTHS,1), 2)               AS MONTHLY_INST,
           LEVEL                                           AS INST_NO,
           ADD_MONTHS(TRUNC(SYSDATE), LEVEL)               AS DUE_DATE
      FROM loan_params lp
   CONNECT BY LEVEL <= lp.MONTHS
)
SELECT
    INST_NO          AS INSTALMENT,
    TO_CHAR(DUE_DATE,'DD-Mon-YYYY') AS DUE_DATE,
    ROUND(PRINCIPAL_PER_INST, 2)    AS PRINCIPAL,
    ROUND(TOTAL_INTEREST / MONTHS, 2) AS INTEREST,
    MONTHLY_INST                    AS TOTAL_DUE
FROM schedule
ORDER BY INST_NO;

-- ============================================================
-- END of employee/ir_queries.sql
-- ============================================================
