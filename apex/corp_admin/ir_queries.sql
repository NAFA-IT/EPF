-- ============================================================
-- FILE: /home/user/EPF/apex/corp_admin/ir_queries.sql
-- EPF PORTAL  –  Corporate Admin Module – IR Queries & LOVs
-- Paste these as APEX Interactive Report / List of Values sources
-- ============================================================

-- ============================================================
-- PAGE 30  –  User Management Interactive Report
-- Region Type: Interactive Report
-- Use as Report SQL Source
-- ============================================================
-- Note: :APP_COMPANY_ID and :APP_USER_COMPANY_ID are APEX binds
-- ============================================================
SELECT
    uc.USER_COMPANY_ID,
    u.USER_ID,
    u.FULL_NAME,
    u.EMAIL,
    u.MOBILE_NO,
    u.EMPLOYEE_CODE,
    r.ROLE_CODE,
    EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID)   AS STATUS_CODE,
    s.STATUS_DISPLAY                         AS STATUS_LABEL,
    u.ACCOUNT_LOCKED,
    u.FAILED_LOGIN_COUNT,
    u.CREATED_DATE,
    uc.CREATED_DATE                          AS ASSIGNED_DATE,
    -- Disable flags for UI rendering
    CASE
        WHEN r.ROLE_CODE IN ('CORP_ADMIN','CORP_AUTHORIZER')
          OR EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'DELETED'
        THEN 'Y' ELSE 'N'
    END AS CHECKBOX_DISABLED_YN,
    CASE
        WHEN r.ROLE_CODE IN ('CORP_ADMIN','CORP_AUTHORIZER')
          OR EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'DELETED'
        THEN 'Y' ELSE 'N'
    END AS EDIT_READONLY_YN,
    -- Status badge CSS class
    CASE EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID)
        WHEN 'ACTIVE'   THEN 'epf-badge-active'
        WHEN 'INACTIVE' THEN 'epf-badge-inactive'
        WHEN 'BLOCKED'  THEN 'epf-badge-blocked'
        WHEN 'DELETED'  THEN 'epf-badge-deleted'
        ELSE 'epf-badge-default'
    END AS STATUS_BADGE_CLASS,
    -- History narration (latest entry)
    (SELECT ACTION_DETAIL
       FROM (SELECT ACTION_DETAIL
               FROM EPF_ACTIVITY_LOGS
              WHERE USER_COMPANY_ID = uc.USER_COMPANY_ID
              ORDER BY ACTION_DATE DESC)
      WHERE ROWNUM = 1
    ) AS LAST_HISTORY_ENTRY
FROM EPF_USER_COMPANIES   uc
JOIN EPF_USERS             u   ON u.USER_ID   = uc.USER_ID
JOIN EPF_USER_COMP_ROLES   ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
JOIN EPF_ROLES             r   ON r.ROLE_ID   = ucr.ROLE_ID
JOIN EPF_STATUSES          s   ON s.STATUS_ID = uc.STATUS_ID
WHERE uc.COMPANY_ID  = :APP_COMPANY_ID
  AND ucr.IS_ACTIVE  = 'Y'
ORDER BY uc.CREATED_DATE DESC
;

-- ============================================================
-- PAGE 30  –  Personal Activity Log Interactive Report (Tab 2)
-- Shows Admin's own activity log for the current company
-- ============================================================
SELECT
    al.LOG_ID,
    al.REF_NO,
    al.ACTION_CODE,
    al.ACTION_DETAIL,
    TO_CHAR(al.ACTION_DATE, 'DD-Mon-YYYY HH:MI AM') AS ACTION_DATE_DISP,
    al.PAGE_NAME,
    al.IP_ADDRESS
FROM EPF_ACTIVITY_LOGS al
WHERE al.USER_COMPANY_ID = :APP_USER_COMPANY_ID
ORDER BY al.ACTION_DATE DESC
;

-- ============================================================
-- LOV: CORP_ROLE_LOV
-- Used on Add User popup – Role dropdown
-- ============================================================
SELECT 'Maker' AS DISPLAY_VALUE,
       'CORP_MAKER' AS RETURN_VALUE
FROM DUAL
UNION ALL
SELECT 'Checker', 'CORP_CHECKER'
FROM DUAL
;

-- ============================================================
-- LOV: CORP_USER_STATUS_LOV
-- Used on Edit User popup – Status dropdown
-- ============================================================
SELECT s.STATUS_DISPLAY AS DISPLAY_VALUE,
       EPF_STATUS_PKG.GET_CODE(s.STATUS_ID) AS RETURN_VALUE
FROM EPF_STATUSES s
WHERE s.STATUS_CATEGORY = 'USER'
  AND EPF_STATUS_PKG.GET_CODE(s.STATUS_ID) IN ('ACTIVE','INACTIVE')
ORDER BY s.STATUS_DISPLAY
;

-- ============================================================
-- PAGE 30 – Edit User Popup: Fetch user data for P30_EDIT_* items
-- Source for Hidden Page Item Computation / PL/SQL Function Body
-- Returns a JSON string; use JS to populate popup fields
-- ============================================================
DECLARE
    v_json CLOB;
BEGIN
    SELECT JSON_OBJECT(
               'fullName'     VALUE u.FULL_NAME,
               'email'        VALUE u.EMAIL,
               'mobileNo'     VALUE u.MOBILE_NO,
               'employeeCode' VALUE u.EMPLOYEE_CODE,
               'roleCode'     VALUE r.ROLE_CODE,
               'statusCode'   VALUE EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID),
               'accountLocked'VALUE u.ACCOUNT_LOCKED,
               'isReadOnly'   VALUE
                   CASE WHEN r.ROLE_CODE IN ('CORP_ADMIN','CORP_AUTHORIZER')
                             OR EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'DELETED'
                        THEN 'Y' ELSE 'N' END
           )
      INTO v_json
      FROM EPF_USER_COMPANIES  uc
      JOIN EPF_USERS            u   ON u.USER_ID = uc.USER_ID
      JOIN EPF_USER_COMP_ROLES  ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
      JOIN EPF_ROLES             r  ON r.ROLE_ID = ucr.ROLE_ID
     WHERE uc.USER_COMPANY_ID = :P30_EDIT_USER_COMPANY_ID
       AND ucr.IS_ACTIVE = 'Y';

    RETURN v_json;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN '{}';
END;

-- ============================================================
-- PAGE 30 – User History Modal: Activity log for selected user
-- ============================================================
SELECT
    al.REF_NO,
    al.ACTION_DETAIL,
    TO_CHAR(al.ACTION_DATE, 'DD-Mon-YYYY HH:MI AM') AS ACTION_DATE_DISP,
    al.ACTION_CODE,
    al.IP_ADDRESS
FROM EPF_ACTIVITY_LOGS al
WHERE al.USER_COMPANY_ID = :P30_HISTORY_USER_COMPANY_ID
ORDER BY al.ACTION_DATE DESC
;

