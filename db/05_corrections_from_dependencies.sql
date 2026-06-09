-- ============================================================
--  CORRECTIONS based on Application Dependencies review
--  These fixes resolve the known errors + align all new code
--  with the existing app's actual DB schema and package API.
-- ============================================================

/*
══════════════════════════════════════════════════════════════
  KEY FACTS CONFIRMED FROM DEPENDENCIES.CSV
  ─────────────────────────────────────────────────────────────
  1. EPF_STATUS_PKG.GET_CODE(status_id)  → returns STATUS_CODE
     EPF_STATUS_PKG.GET_ID(category, code) → returns STATUS_ID
     Use these throughout; do NOT invent a GET_STATUS_ID helper.

  2. EPF_USER_COMP_ROLES schema:
       USER_COMPANY_ID  (FK → EPF_USER_COMPANIES.USER_COMPANY_ID)
       ROLE_ID
       IS_ACTIVE  VARCHAR2(1)  -- 'Y'/'N'
     (No separate USER_ID + COMPANY_ID columns)

  3. EPF_ROLES has: ROLE_CODE, ROLE_LEVEL, ROLE_NAME

  4. EPF_V_USER_COMPANIES view columns confirmed:
       USER_COMPANY_ID, USER_ID, COMPANY_ID, COMPANY_NAME,
       EMAIL, STATUS_ID, USER_COMPANY_STATUS, COMPANY_STATUS,
       IS_DEFAULT

  5. EPF_AAML_PKG.CHECKER_APPROVE signature:
       (p_company_id, p_remarks, p_approved_by)

  6. EPF_AAML_PKG.CHECKER_REJECT signature:
       (p_company_id, p_remarks, p_rejected_by)

  7. EPF_AAML_PKG.CHECKER_REVERT signature:
       (p_company_id, p_remarks, p_reverted_by)

  8. EPF_AAML_PKG.SUBMIT_TO_CHECKER signature:
       (p_company_id, p_submitted_by)   -- only 2 params

  9. EPF_AAML_PKG.SAVE_CLIENT is a FUNCTION returning NUMBER
     (company_id) – not a procedure.

  10. EPF_COMPANIES has: IS_PRIMARY, REF_NO, ONBOARDING_DATE
  11. EPF_CLIENT_CHANGE_REQUESTS has: SECTION_CHANGED column
  12. EPF_USERS has: IS_ACTIVE, DESIGNATION, DATE_OF_BIRTH,
      DATE_OF_JOINING, DFN_INVESTOR_ID, FIRST_LOGIN, TOKEN,
      GENDER, MFA_ENABLED, MFA_SECRET, ACCOUNT_LOCKED,
      FAILED_LOGIN_COUNT
  13. EPF_FUNDS has: IS_ACTIVE column
══════════════════════════════════════════════════════════════
*/


-- ── FIX 1: Pages 12 & 13 – DELETE USERS  ────────────────────
-- Problem: References EPF_USERS_ROLES (does not exist).
-- Fix: Use EPF_USER_COMP_ROLES and EPF_USER_COMPANIES;
--      soft-delete by updating STATUS_ID to DELETED status.

-- Replace the PL/SQL block in Page 12 → Process → DELETE USERS:
-- (and identically for Page 13, substituting P13_USER_ID)
/*
DECLARE
    v_deleted_status NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS','DELETED');
BEGIN
    -- Deactivate role assignments
    UPDATE EPF_USER_COMP_ROLES ucr
    SET    ucr.IS_ACTIVE = 'N'
    WHERE  ucr.USER_COMPANY_ID IN (
               SELECT uc.USER_COMPANY_ID
               FROM   EPF_USER_COMPANIES uc
               WHERE  uc.USER_ID MEMBER OF
                      (SELECT APEX_STRING.SPLIT_NUMBERS(:P12_USER_ID,':') FROM DUAL)
               AND    uc.COMPANY_ID = :P12_COMPANY_ID
           );

    -- Soft-delete user_company record
    UPDATE EPF_USER_COMPANIES uc
    SET    uc.STATUS_ID    = v_deleted_status,
           uc.UPDATED_BY   = :APP_USER_ID,
           uc.UPDATED_DATE = SYSDATE
    WHERE  uc.USER_ID MEMBER OF
               (SELECT APEX_STRING.SPLIT_NUMBERS(:P12_USER_ID,':') FROM DUAL)
    AND    uc.COMPANY_ID = :P12_COMPANY_ID;

    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User(s) deactivated.';
EXCEPTION WHEN OTHERS THEN
    APEX_ERROR.ADD_ERROR(
        p_message          => 'Delete failed: '||SQLERRM,
        p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
    );
END;
*/


-- ── FIX 2: Page 11 – Search Results: u2.folio invalid  ──────
-- Problem: EPF_USERS has no FOLIO column.
-- Fix: Reference EPF_FOLIOS via EPF_USER_COMPANIES.FOLIO_ID.

-- Corrected subquery for user_count / emp_count:
/*
-- Non-employee user count (no folio linked)
(SELECT COUNT(*)
 FROM   EPF_USER_COMPANIES uc2
 JOIN   EPF_STATUSES       st2 ON st2.STATUS_ID = uc2.STATUS_ID
 WHERE  uc2.COMPANY_ID = c.COMPANY_ID
 AND    st2.STATUS_CODE != 'DELETED'
 AND    uc2.FOLIO_ID IS NULL) AS user_count,

-- Employee count (has a folio)
(SELECT COUNT(*)
 FROM   EPF_USER_COMPANIES uc2
 JOIN   EPF_STATUSES       st2 ON st2.STATUS_ID = uc2.STATUS_ID
 WHERE  uc2.COMPANY_ID = c.COMPANY_ID
 AND    st2.STATUS_CODE != 'DELETED'
 AND    uc2.FOLIO_ID IS NOT NULL) AS emp_count,
*/


-- ── FIX 3: Page 9999 – Clear Open Sessions  ─────────────────
-- Problem: References apex_240200.WWV_FLOW_SESSIONS$ (workspace-specific table).
-- Fix: Use APEX_SESSION.DELETE_SESSION (public API).

/*
DECLARE
    v_username VARCHAR2(500) := :P9999_USERNAME;
BEGIN
    IF v_username IS NOT NULL THEN
        FOR s IN (
            SELECT s.session_id
            FROM   apex_workspace_sessions s
            WHERE  UPPER(s.user_name) = UPPER(v_username)
        ) LOOP
            APEX_SESSION.DELETE_SESSION(p_session_id => s.session_id);
        END LOOP;
    END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END;
*/


-- ── FIX 4: EPF_SAVE_CLIENT – wrong args to SAVE_CLIENT  ────
-- Problem: Calling EPF_AAML_PKG.SAVE_CLIENT with old/different
--          param list causing PLS-00306.
-- Fix: Add the SAVE_CLIENT FUNCTION to EPF_AAML_PKG with exactly
--      the parameters expected by the existing APEX process.
-- See: 06_epf_aaml_pkg_addons.sql for the full function body.


-- ── FIX 5: EPF_USER_COMP_ROLES usage throughout  ────────────
-- All new code must join via USER_COMPANY_ID, not USER_ID+COMPANY_ID:
-- CORRECT:
--   JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
-- WRONG (old pattern):
--   JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_ID = uc.USER_ID AND ucr.COMPANY_ID = uc.COMPANY_ID


-- ── FIX 6: Status lookups – use EPF_STATUS_PKG  ──────────────
-- CORRECT:
--   WHERE EPF_STATUS_PKG.GET_CODE(c.STATUS_ID) = 'ACTIVE'
--   WHERE c.STATUS_ID = EPF_STATUS_PKG.GET_ID('CLIENT_STATUS','DRAFT')
-- WRONG (invented helper):
--   WHERE c.STATUS_ID = GET_STATUS_ID('CLIENT_STATUS','DRAFT')
