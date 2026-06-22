-- ============================================================
-- FILE: /home/user/EPF/db/20_epf_views.sql
-- EPF PORTAL  –  Application Views
-- Creates views used by APEX pages and session-management
-- application processes.
-- Depends on: EPF_COMPANIES, EPF_USER_COMPANIES,
--             EPF_USER_COMP_ROLES, EPF_ROLES, EPF_STATUS_PKG
-- ============================================================

-- ── EPF_V_USER_COMPANIES ──────────────────────────────────────
--  Used by:
--    - EPF_POST_AUTH (authentication scheme post-login procedure)
--    - SET_SESSION_DETAILS (application process, BEFORE_HEADER)
--    - Page 100 (company/role selector)
--  Columns confirmed in 05_corrections_from_dependencies.sql:
--    USER_COMPANY_ID, USER_ID, COMPANY_ID, COMPANY_NAME, EMAIL,
--    STATUS_ID, USER_COMPANY_STATUS, COMPANY_STATUS, IS_DEFAULT
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW EPF_V_USER_COMPANIES AS
SELECT
    uc.USER_COMPANY_ID,
    uc.USER_ID,
    uc.COMPANY_ID,
    c.COMPANY_NAME,
    c.COMPANY_CODE,
    u.EMAIL,
    uc.STATUS_ID,
    EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID)  AS USER_COMPANY_STATUS,
    EPF_STATUS_PKG.GET_CODE(c.STATUS_ID)   AS COMPANY_STATUS,
    NVL(uc.IS_DEFAULT, 'N')                AS IS_DEFAULT
  FROM EPF_USER_COMPANIES uc
  JOIN EPF_COMPANIES       c  ON c.COMPANY_ID = uc.COMPANY_ID
  JOIN EPF_USERS           u  ON u.USER_ID    = uc.USER_ID;
/

-- ── EPF_V_USER_ROLES ─────────────────────────────────────────
--  Flat view of every active role assignment with role details.
--  Used by authorization schemes and role-selection pages.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW EPF_V_USER_ROLES AS
SELECT
    ucr.USER_COMPANY_ID,
    uc.USER_ID,
    uc.COMPANY_ID,
    ucr.ROLE_ID,
    r.ROLE_CODE,
    r.ROLE_NAME,
    r.ROLE_LEVEL,
    ucr.IS_ACTIVE
  FROM EPF_USER_COMP_ROLES ucr
  JOIN EPF_USER_COMPANIES  uc  ON uc.USER_COMPANY_ID = ucr.USER_COMPANY_ID
  JOIN EPF_ROLES            r  ON r.ROLE_ID           = ucr.ROLE_ID
 WHERE ucr.IS_ACTIVE = 'Y';
/

-- ============================================================
-- End of 20_epf_views.sql
-- ============================================================
