-- ============================================================
-- FILE: /home/user/EPF/db/17_epf_util_pkg.sql
-- EPF PORTAL  –  Utility Package
-- Provides shared helper procedures used across EPF packages.
-- Depends on: EPF_ACTIVITY_LOG table
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_UTIL AS

    -- Log an activity entry into EPF_ACTIVITY_LOG
    PROCEDURE LOG_ACTIVITY (
        p_user_company_id IN NUMBER   DEFAULT NULL,
        p_role_id         IN NUMBER   DEFAULT NULL,
        p_change_req_id   IN NUMBER   DEFAULT NULL,
        p_category        IN VARCHAR2,
        p_activity_code   IN VARCHAR2,
        p_narration       IN VARCHAR2,
        p_performed_by    IN NUMBER
    );

END EPF_UTIL;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_UTIL AS

    -- ─────────────────────────────────────────────────────────────
    --  LOG_ACTIVITY
    --  Inserts a row into EPF_ACTIVITY_LOG.
    --  Parameter mapping:
    --    p_category      → ENTITY_TYPE
    --    p_change_req_id → ENTITY_ID
    --    p_activity_code → ACTION_CODE
    --    p_narration     → REMARKS
    --    p_performed_by  → PERFORMED_BY
    --    SYSDATE         → PERFORMED_DATE
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
        WHEN OTHERS THEN
            ROLLBACK;
    END LOG_ACTIVITY;

END EPF_UTIL;
/

-- ============================================================
-- End of 17_epf_util_pkg.sql
-- ============================================================
