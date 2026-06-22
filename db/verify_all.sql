-- ============================================================
-- FILE: /home/user/EPF/db/verify_all.sql
-- EPF PORTAL  –  Post-install verification
-- Run after all install scripts to confirm every DB object
-- is present and VALID.  Reports any missing or invalid items.
-- ============================================================

SET LINESIZE 120
SET PAGESIZE 200
SET FEEDBACK OFF
SET HEADING ON

PROMPT ============================================================
PROMPT EPF PORTAL  –  DB Object Verification
PROMPT ============================================================

-- ── 1. Packages (spec + body must both be VALID) ─────────────
PROMPT
PROMPT [PACKAGES]
SELECT OBJECT_NAME,
       OBJECT_TYPE,
       STATUS,
       CASE WHEN STATUS = 'VALID' THEN 'OK' ELSE '*** INVALID ***' END AS RESULT
  FROM USER_OBJECTS
 WHERE OBJECT_TYPE IN ('PACKAGE','PACKAGE BODY')
   AND OBJECT_NAME IN (
       'UC_CRYPTO',
       'EPF_STATUS_PKG',
       'EPF_AAML_PKG',
       'EPF_EMP_SYNC_PKG',
       'EPF_CORP_ADMIN_PKG',
       'EPF_EMAIL_PKG',
       'EPF_CORP_TXN_PKG',
       'EPF_AUTHORIZER_PKG',
       'EPF_EMPLOYEE_PKG',
       'EPF_UTIL',
       'EPF_PKG_AUTH',
       'EPF_CORP_PKG'
   )
 ORDER BY OBJECT_NAME, OBJECT_TYPE;

-- ── 2. Sequences ──────────────────────────────────────────────
PROMPT
PROMPT [SEQUENCES]
SELECT SEQUENCE_NAME,
       'OK' AS RESULT
  FROM USER_SEQUENCES
 WHERE SEQUENCE_NAME IN (
       'EPF_CONTRIB_BATCH_SEQ',
       'EPF_LOAN_REQ_SEQ',
       'EPF_WD_REQ_SEQ',
       'EPF_LIEN_REQ_SEQ',
       'EPF_NOC_REQ_SEQ'
 )
 ORDER BY SEQUENCE_NAME;

-- ── 3. Tables ─────────────────────────────────────────────────
PROMPT
PROMPT [TABLES]
SELECT TABLE_NAME,
       'OK' AS RESULT
  FROM USER_TABLES
 WHERE TABLE_NAME IN (
       'EPF_NOTIFICATIONS',
       'EPF_CONTRIB_BATCHES',
       'EPF_CONTRIB_BATCH_ROWS',
       'EPF_LOAN_REQUESTS',
       'EPF_LOAN_SCHEDULE',
       'EPF_WITHDRAWAL_REQUESTS',
       'EPF_LIEN_REQUESTS',
       'EPF_NOC_REQUESTS',
       'EPF_EMP_DISABLE_REQUESTS',
       'EPF_FEATURE_ACCESS',
       'EPF_REALLOC_GROUPS',
       'EPF_REALLOC_GROUP_MEMBERS',
       'EPF_ACTIVITY_LOG',
       'EPF_EMAIL_LOGS',
       'EPF_AUTHORIZER_DECISIONS'
 )
 ORDER BY TABLE_NAME;

-- ── 4. Key columns added by patch scripts ─────────────────────
PROMPT
PROMPT [PATCHED COLUMNS]
SELECT TABLE_NAME, COLUMN_NAME,
       CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE '*** MISSING ***' END AS RESULT
  FROM USER_TAB_COLUMNS
 WHERE (TABLE_NAME = 'EPF_FOLIOS'          AND COLUMN_NAME IN ('LIEN_MARKED','IS_DISABLED','NOC_ISSUED'))
    OR (TABLE_NAME = 'EPF_COMPANY_SETTINGS' AND COLUMN_NAME IN ('LOAN_INTEREST_TYPE','LOAN_INTEREST_RATE',
                                                                  'LOAN_LIMIT_PCT','LOAN_MAX_INSTALMENT_MONTHS',
                                                                  'FLOATING_RATE_TENURE'))
    OR (TABLE_NAME = 'EPF_USERS'            AND COLUMN_NAME IN ('FIRST_LOGIN','FORCE_PWD_CHANGE',
                                                                  'PASSWORD_HASH','PASSWORD_SALT'))
 GROUP BY TABLE_NAME, COLUMN_NAME
 ORDER BY TABLE_NAME, COLUMN_NAME;

-- ── 5. Invalid objects (anything invalid in schema) ───────────
PROMPT
PROMPT [INVALID OBJECTS IN SCHEMA]
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
  FROM USER_OBJECTS
 WHERE STATUS != 'VALID'
   AND OBJECT_TYPE NOT IN ('UNDEFINED')
 ORDER BY OBJECT_TYPE, OBJECT_NAME;

-- ── 6. Compile errors for any invalid package ─────────────────
PROMPT
PROMPT [COMPILE ERRORS]
SELECT NAME, TYPE, LINE, POSITION, TEXT
  FROM USER_ERRORS
 WHERE NAME IN (
       'UC_CRYPTO',
       'EPF_STATUS_PKG',
       'EPF_AAML_PKG',
       'EPF_EMP_SYNC_PKG',
       'EPF_CORP_ADMIN_PKG',
       'EPF_EMAIL_PKG',
       'EPF_CORP_TXN_PKG',
       'EPF_AUTHORIZER_PKG',
       'EPF_EMPLOYEE_PKG',
       'EPF_UTIL',
       'EPF_PKG_AUTH',
       'EPF_CORP_PKG'
 )
 ORDER BY NAME, TYPE, LINE, POSITION;

-- ── 7. REQUEST workflow statuses seeded ──────────────────────
PROMPT
PROMPT [REQUEST STATUSES]
SELECT STATUS_CODE, STATUS_DISPLAY,
       CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE '*** MISSING ***' END AS RESULT
  FROM EPF_STATUSES
 WHERE CATEGORY_CODE = 'REQUEST'
   AND STATUS_CODE IN ('PENDING_CHECKER','PENDING_AUTHORIZER','AUTHORIZED','REJECTED')
 GROUP BY STATUS_CODE, STATUS_DISPLAY
 ORDER BY STATUS_CODE;

PROMPT
PROMPT ============================================================
PROMPT Verification complete.  Any rows above marked '*** ...' need attention.
PROMPT ============================================================
SET FEEDBACK ON
