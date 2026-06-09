-- ============================================================
--  Interactive Report SQL Queries
--  Copy each query into the corresponding APEX IR region
-- ============================================================


/*
══════════════════════════════════════════════════════════════
  IR: AAML MAKER – Client Dashboard  (Page 10)
  Shows all companies managed by the maker with row actions
══════════════════════════════════════════════════════════════
*/
SELECT
    c.COMPANY_ID,
    c.COMPANY_NAME,
    c.COMPANY_CODE,
    c.NTN,
    c.CITY,
    g.GROUP_NAME,
    s.STATUS_NAME,
    s.CSS_CLASS          AS STATUS_CSS,
    s.STATUS_CODE,
    c.CREATED_DATE,
    -- Dynamic row action based on status
    CASE s.STATUS_CODE
        WHEN 'DRAFT'            THEN 'CONTINUE'
        WHEN 'REVERTED'         THEN 'EDIT'
        WHEN 'PENDING_CHECKER'  THEN 'VIEW'
        WHEN 'ACTIVE'           THEN 'MANAGE'
        ELSE                         'VIEW'
    END                  AS ROW_ACTION,
    -- Link for action button
    CASE s.STATUS_CODE
        WHEN 'DRAFT'            THEN APEX_PAGE.GET_URL(p_page=>12, p_items=>'P12_COMPANY_ID', p_values=>c.COMPANY_ID)
        WHEN 'REVERTED'         THEN APEX_PAGE.GET_URL(p_page=>12, p_items=>'P12_COMPANY_ID', p_values=>c.COMPANY_ID)
        WHEN 'PENDING_CHECKER'  THEN APEX_PAGE.GET_URL(p_page=>13, p_items=>'P13_COMPANY_ID', p_values=>c.COMPANY_ID)
        WHEN 'ACTIVE'           THEN APEX_PAGE.GET_URL(p_page=>14, p_items=>'P14_COMPANY_ID', p_values=>c.COMPANY_ID)
        ELSE                         APEX_PAGE.GET_URL(p_page=>13, p_items=>'P13_COMPANY_ID', p_values=>c.COMPANY_ID)
    END                  AS ROW_LINK,
    (SELECT COUNT(*) FROM EPF_USER_COMPANIES uc WHERE uc.COMPANY_ID = c.COMPANY_ID
     AND uc.STATUS_ID != (SELECT STATUS_ID FROM EPF_STATUSES WHERE CATEGORY_CODE='USER_STATUS' AND STATUS_CODE='DELETED' AND ROWNUM=1)
    )                    AS TOTAL_USERS,
    NVL(sub.SUBMISSION_REF_NO, '-') AS SUBMISSION_REF
FROM
    EPF_COMPANIES    c
    LEFT JOIN EPF_STATUSES        s   ON s.STATUS_ID  = c.STATUS_ID
    LEFT JOIN EPF_COMPANY_GROUPS  g   ON g.GROUP_ID   = c.GROUP_ID
    LEFT JOIN EPF_ONBOARDING_SUBMISSIONS sub ON sub.COMPANY_ID = c.COMPANY_ID
WHERE
    c.STATUS_ID != (SELECT STATUS_ID FROM EPF_STATUSES WHERE CATEGORY_CODE='CLIENT_STATUS' AND STATUS_CODE='DELETED' AND ROWNUM=1)
ORDER BY c.CREATED_DATE DESC


/*
══════════════════════════════════════════════════════════════
  IR: AAML CHECKER – Dashboard  (Page 20)
  UNION: new client onboarding + change requests pending review
══════════════════════════════════════════════════════════════
*/
SELECT
    'ONBOARDING'         AS ITEM_TYPE,
    'New Client'         AS ITEM_TYPE_LABEL,
    sub.SUBMISSION_ID    AS ITEM_ID,
    sub.SUBMISSION_REF_NO AS REF_NO,
    c.COMPANY_NAME,
    c.COMPANY_CODE,
    s.STATUS_NAME,
    s.CSS_CLASS          AS STATUS_CSS,
    sub.SUBMITTED_DATE   AS ACTIVITY_DATE,
    sub.SUBMITTED_BY     AS ACTIVITY_BY_ID,
    (SELECT FULL_NAME FROM EPF_USERS WHERE USER_ID = sub.SUBMITTED_BY) AS ACTIVITY_BY_NAME,
    APEX_PAGE.GET_URL(p_page=>22, p_items=>'P22_COMPANY_ID,P22_SUBMISSION_ID',
                      p_values=>c.COMPANY_ID||','||sub.SUBMISSION_ID) AS REVIEW_LINK
FROM
    EPF_ONBOARDING_SUBMISSIONS sub
    JOIN EPF_COMPANIES c ON c.COMPANY_ID = sub.COMPANY_ID
    JOIN EPF_STATUSES  s ON s.STATUS_ID  = sub.STATUS_ID
WHERE
    s.STATUS_CODE = 'PENDING_CHECKER'

UNION ALL

SELECT
    'CHANGE_REQUEST'     AS ITEM_TYPE,
    'Change Request'     AS ITEM_TYPE_LABEL,
    cr.CHANGE_REQ_ID     AS ITEM_ID,
    cr.CHANGE_REQ_REF_NO AS REF_NO,
    c.COMPANY_NAME,
    c.COMPANY_CODE,
    s.STATUS_NAME,
    s.CSS_CLASS          AS STATUS_CSS,
    cr.MAKER_RESUBMIT_DATE AS ACTIVITY_DATE,
    cr.CREATED_BY        AS ACTIVITY_BY_ID,
    (SELECT FULL_NAME FROM EPF_USERS WHERE USER_ID = cr.CREATED_BY) AS ACTIVITY_BY_NAME,
    APEX_PAGE.GET_URL(p_page=>23, p_items=>'P23_CHANGE_REQ_ID',
                      p_values=>cr.CHANGE_REQ_ID) AS REVIEW_LINK
FROM
    EPF_CLIENT_CHANGE_REQUESTS cr
    JOIN EPF_COMPANIES c ON c.COMPANY_ID = cr.COMPANY_ID
    JOIN EPF_STATUSES  s ON s.STATUS_ID  = cr.STATUS_ID
WHERE
    s.STATUS_CODE = 'PENDING_CHECKER'

ORDER BY ACTIVITY_DATE DESC


/*
══════════════════════════════════════════════════════════════
  IR: ONBOARDING WIZARD – TAB 2 Users Report
  Excludes EMPLOYEE role (added by sync) and DELETED users
══════════════════════════════════════════════════════════════
*/
SELECT
    uc.USER_COMPANY_ID,
    u.USER_ID,
    u.FULL_NAME,
    u.EMAIL,
    u.CNIC,
    u.MOBILE_NO,
    r.ROLE_NAME,
    s.STATUS_NAME,
    s.CSS_CLASS     AS STATUS_CSS,
    uc.CREATED_DATE,
    APEX_PAGE.GET_URL(p_page=>:APP_PAGE_ID,
                      p_items=>'P_USER_COMPANY_ID',
                      p_values=>uc.USER_COMPANY_ID) AS EDIT_LINK
FROM
    EPF_USER_COMPANIES  uc
    JOIN EPF_USERS       u  ON u.USER_ID   = uc.USER_ID
    JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_ID = uc.USER_ID AND ucr.COMPANY_ID = uc.COMPANY_ID
    JOIN EPF_ROLES       r  ON r.ROLE_ID   = ucr.ROLE_ID
    JOIN EPF_STATUSES    s  ON s.STATUS_ID = uc.STATUS_ID
WHERE
    uc.COMPANY_ID = :P_COMPANY_ID
    AND ucr.ROLE_ID != 9      -- exclude EMPLOYEE (managed by sync)
    AND s.STATUS_CODE != 'DELETED'
ORDER BY r.ROLE_ID, u.FULL_NAME


/*
══════════════════════════════════════════════════════════════
  IR: ONBOARDING WIZARD – TAB 3 Authorizer Groups Report
══════════════════════════════════════════════════════════════
*/
SELECT
    ag.GROUP_ID,
    ag.GROUP_NAME,
    ag.MIN_APPROVALS,
    COUNT(agm.USER_ID)  AS MEMBER_COUNT,
    LISTAGG(u.FULL_NAME, ', ') WITHIN GROUP (ORDER BY u.FULL_NAME) AS MEMBER_NAMES,
    ag.CREATED_DATE,
    APEX_PAGE.GET_URL(p_page=>:APP_PAGE_ID,
                      p_items=>'P_AUTH_GROUP_ID',
                      p_values=>ag.GROUP_ID) AS EDIT_LINK
FROM
    EPF_AUTHORIZER_GROUPS        ag
    LEFT JOIN EPF_AUTHORIZER_GROUP_MEMBERS agm ON agm.GROUP_ID = ag.GROUP_ID
    LEFT JOIN EPF_USERS                     u  ON u.USER_ID    = agm.USER_ID
WHERE
    ag.COMPANY_ID = :P_COMPANY_ID
GROUP BY
    ag.GROUP_ID, ag.GROUP_NAME, ag.MIN_APPROVALS, ag.CREATED_DATE
ORDER BY ag.GROUP_NAME


/*
══════════════════════════════════════════════════════════════
  IR: ONBOARDING WIZARD – TAB 4 Employee Staging Summary
══════════════════════════════════════════════════════════════
*/
SELECT
    s.STAGING_ID,
    s.FOLIO_NUMBER,
    s.FULL_NAME,
    s.EMAIL,
    s.CNIC,
    s.MOBILE_NO,
    s.FUND_CODES,
    s.PROCESS_STATUS,
    s.BATCH_DATE,
    s.PROCESSED_DATE,
    s.PROCESS_MESSAGE
FROM
    EPF_EMP_API_STAGING s
WHERE
    s.COMPANY_ID = :P_COMPANY_ID
    AND s.BATCH_DATE = (
        SELECT MAX(BATCH_DATE) FROM EPF_EMP_API_STAGING
        WHERE COMPANY_ID = :P_COMPANY_ID
    )
ORDER BY s.PROCESS_STATUS, s.FULL_NAME


/*
══════════════════════════════════════════════════════════════
  IR: AAML MAKER – Change Request History  (Page 14)
══════════════════════════════════════════════════════════════
*/
SELECT
    cr.CHANGE_REQ_ID,
    cr.CHANGE_REQ_REF_NO,
    s.STATUS_NAME,
    s.CSS_CLASS     AS STATUS_CSS,
    cr.CREATED_DATE AS RAISED_DATE,
    cr.MAKER_RESUBMIT_DATE,
    cr.CHECKED_DATE,
    (SELECT FULL_NAME FROM EPF_USERS WHERE USER_ID = cr.CHECKER_ID) AS CHECKER_NAME,
    cr.CHECKER_REMARKS,
    cr.REVERT_REMARKS,
    cr.AAML_APPLIED_DATE,
    APEX_PAGE.GET_URL(p_page=>30, p_items=>'P30_CHANGE_REQ_ID',
                      p_values=>cr.CHANGE_REQ_ID) AS DETAIL_LINK
FROM
    EPF_CLIENT_CHANGE_REQUESTS cr
    JOIN EPF_STATUSES s ON s.STATUS_ID = cr.STATUS_ID
WHERE
    cr.COMPANY_ID = :P_COMPANY_ID
ORDER BY cr.CREATED_DATE DESC


/*
══════════════════════════════════════════════════════════════
  LOV: Authorizer Group Member Selector (for shuttle)
  Use as Left / Available list in Shuttle item P_MEMBER_USER_IDS
══════════════════════════════════════════════════════════════
*/
SELECT u.FULL_NAME || ' (' || r.ROLE_NAME || ')' AS D,
       u.USER_ID                                  AS R
FROM   EPF_USER_COMPANIES  uc
JOIN   EPF_USERS            u  ON u.USER_ID   = uc.USER_ID
JOIN   EPF_USER_COMP_ROLES  ucr ON ucr.USER_ID = uc.USER_ID AND ucr.COMPANY_ID = uc.COMPANY_ID
JOIN   EPF_ROLES            r  ON r.ROLE_ID   = ucr.ROLE_ID
WHERE  uc.COMPANY_ID = :P_COMPANY_ID
AND    ucr.ROLE_ID IN (5, 8)    -- Corp Admin, Corp Authorizer
AND    uc.STATUS_ID != (SELECT STATUS_ID FROM EPF_STATUSES WHERE CATEGORY_CODE='USER_STATUS' AND STATUS_CODE='DELETED' AND ROWNUM=1)
ORDER BY u.FULL_NAME
