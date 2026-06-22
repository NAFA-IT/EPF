-- ============================================================
-- FILE: /home/user/EPF/db/17_epf_util_pkg.sql
-- EPF PORTAL  –  Utility Package
-- Provides shared helper functions/procedures used across all
-- EPF packages and APEX application processes.
-- Depends on: EPF_ACTIVITY_LOG, EPF_COMPANIES, EPF_ROLES,
--             EPF_USER_COMPANIES, EPF_USER_COMP_ROLES
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_UTIL AS

    -- ── Activity Logging ──────────────────────────────────────
    PROCEDURE LOG_ACTIVITY (
        p_user_company_id IN NUMBER   DEFAULT NULL,
        p_role_id         IN NUMBER   DEFAULT NULL,
        p_change_req_id   IN NUMBER   DEFAULT NULL,
        p_category        IN VARCHAR2,
        p_activity_code   IN VARCHAR2,
        p_narration       IN VARCHAR2,
        p_performed_by    IN NUMBER
    );

    -- ── Company Lookups ───────────────────────────────────────
    -- Returns COMPANY_NAME for a given COMPANY_ID
    FUNCTION GET_COMPANY (
        p_company_id IN NUMBER
    ) RETURN VARCHAR2;

    -- Returns COMPANY_CODE for a given COMPANY_ID
    FUNCTION GET_COMPANY_CODE (
        p_company_id IN NUMBER
    ) RETURN VARCHAR2;

    -- ── User-Company Lookups ──────────────────────────────────
    -- Returns USER_COMPANY_ID for a given COMPANY_ID + USER_ID
    FUNCTION GET_USER_COMPANY_ID (
        p_company_id IN NUMBER,
        p_user_id    IN NUMBER
    ) RETURN NUMBER;

    -- Returns all COMPANY_IDs assigned to a user (active only)
    -- as a pipelined table of numbers
    FUNCTION GET_USER_COMPS (
        p_user_id IN NUMBER
    ) RETURN SYS.ODCINUMBERLIST;

    -- ── Role Lookups ──────────────────────────────────────────
    -- Returns all ROLE_IDs for a USER_COMPANY_ID (active only)
    FUNCTION GET_USER_ROLES (
        p_user_company_id IN NUMBER
    ) RETURN SYS.ODCINUMBERLIST;

    -- Returns ROLE_NAME for a given ROLE_ID
    FUNCTION GET_ROLE_NAME (
        p_role_id IN NUMBER
    ) RETURN VARCHAR2;

    -- Returns ROLE_CODE for a given ROLE_ID
    FUNCTION GET_ROLE_CODE (
        p_role_id IN NUMBER
    ) RETURN VARCHAR2;

END EPF_UTIL;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_UTIL AS

    -- ─────────────────────────────────────────────────────────────
    --  LOG_ACTIVITY  –  AUTONOMOUS insert into EPF_ACTIVITY_LOG
    --  Column mapping:
    --    p_category      → ENTITY_TYPE
    --    p_change_req_id → ENTITY_ID
    --    p_activity_code → ACTION_CODE
    --    p_narration     → REMARKS
    --    p_performed_by  → PERFORMED_BY
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE LOG_ACTIVITY (
        p_user_company_id IN NUMBER   DEFAULT NULL,
        p_role_id         IN NUMBER   DEFAULT NULL,
        p_change_req_id   IN NUMBER   DEFAULT NULL,
        p_category        IN VARCHAR2,
        p_activity_code   IN VARCHAR2,
        p_narration       IN VARCHAR2,
        p_performed_by    IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO EPF_ACTIVITY_LOG (
            ENTITY_TYPE,
            ENTITY_ID,
            ACTION_CODE,
            REMARKS,
            PERFORMED_BY,
            PERFORMED_DATE
        ) VALUES (
            p_category,
            p_change_req_id,
            p_activity_code,
            p_narration,
            p_performed_by,
            SYSDATE
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END LOG_ACTIVITY;

    -- ─────────────────────────────────────────────────────────────
    --  GET_COMPANY  –  COMPANY_NAME for a COMPANY_ID
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_COMPANY (
        p_company_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name EPF_COMPANIES.COMPANY_NAME%TYPE;
    BEGIN
        SELECT COMPANY_NAME
          INTO v_name
          FROM EPF_COMPANIES
         WHERE COMPANY_ID = p_company_id;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_COMPANY;

    -- ─────────────────────────────────────────────────────────────
    --  GET_COMPANY_CODE  –  COMPANY_CODE for a COMPANY_ID
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_COMPANY_CODE (
        p_company_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_code EPF_COMPANIES.COMPANY_CODE%TYPE;
    BEGIN
        SELECT COMPANY_CODE
          INTO v_code
          FROM EPF_COMPANIES
         WHERE COMPANY_ID = p_company_id;
        RETURN v_code;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_COMPANY_CODE;

    -- ─────────────────────────────────────────────────────────────
    --  GET_USER_COMPANY_ID  –  USER_COMPANY_ID for company+user
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_USER_COMPANY_ID (
        p_company_id IN NUMBER,
        p_user_id    IN NUMBER
    ) RETURN NUMBER IS
        v_ucid EPF_USER_COMPANIES.USER_COMPANY_ID%TYPE;
    BEGIN
        SELECT USER_COMPANY_ID
          INTO v_ucid
          FROM EPF_USER_COMPANIES
         WHERE COMPANY_ID = p_company_id
           AND USER_ID    = p_user_id
           AND ROWNUM     = 1;
        RETURN v_ucid;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_USER_COMPANY_ID;

    -- ─────────────────────────────────────────────────────────────
    --  GET_USER_COMPS  –  all COMPANY_IDs for a user (active)
    --  Returns a NUMBER collection usable with TABLE().
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_USER_COMPS (
        p_user_id IN NUMBER
    ) RETURN SYS.ODCINUMBERLIST IS
        v_result SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST();
    BEGIN
        SELECT uc.COMPANY_ID
          BULK COLLECT INTO v_result
          FROM EPF_USER_COMPANIES uc
         WHERE uc.USER_ID   = p_user_id
           AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE';
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN RETURN SYS.ODCINUMBERLIST();
    END GET_USER_COMPS;

    -- ─────────────────────────────────────────────────────────────
    --  GET_USER_ROLES  –  all ROLE_IDs for a USER_COMPANY_ID
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_USER_ROLES (
        p_user_company_id IN NUMBER
    ) RETURN SYS.ODCINUMBERLIST IS
        v_result SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST();
    BEGIN
        SELECT ucr.ROLE_ID
          BULK COLLECT INTO v_result
          FROM EPF_USER_COMP_ROLES ucr
         WHERE ucr.USER_COMPANY_ID = p_user_company_id
           AND ucr.IS_ACTIVE       = 'Y';
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN RETURN SYS.ODCINUMBERLIST();
    END GET_USER_ROLES;

    -- ─────────────────────────────────────────────────────────────
    --  GET_ROLE_NAME  –  display name for a ROLE_ID
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_ROLE_NAME (
        p_role_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name EPF_ROLES.ROLE_NAME%TYPE;
    BEGIN
        SELECT ROLE_NAME
          INTO v_name
          FROM EPF_ROLES
         WHERE ROLE_ID = p_role_id;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_ROLE_NAME;

    -- ─────────────────────────────────────────────────────────────
    --  GET_ROLE_CODE  –  ROLE_CODE for a ROLE_ID
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_ROLE_CODE (
        p_role_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_code EPF_ROLES.ROLE_CODE%TYPE;
    BEGIN
        SELECT ROLE_CODE
          INTO v_code
          FROM EPF_ROLES
         WHERE ROLE_ID = p_role_id;
        RETURN v_code;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_ROLE_CODE;

END EPF_UTIL;
/

-- ============================================================
-- End of 17_epf_util_pkg.sql
-- ============================================================
