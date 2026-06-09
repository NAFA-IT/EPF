-- ============================================================
--  APEX AJAX Processes  (Application Process type)
--  These are called by apex.server.process() from JavaScript.
--  Register each in: Shared Components → Application Processes
--  On Demand = Yes
-- ============================================================


/*
══════════════════════════════════════════════════════════════
  AJAX PROCESS: CHECKER_APPROVE_AJAX
  Called by: epfConfirmApprove() for ONBOARDING items
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_company_id NUMBER  := TO_NUMBER(APEX_APPLICATION.G_X01);
    v_remarks    VARCHAR2(2000) := APEX_APPLICATION.G_X02;
    v_success    VARCHAR2(1);
    v_message    VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.CHECKER_APPROVE(
        p_company_id  => v_company_id,
        p_checker_id  => :APP_USER_ID,
        p_remarks     => v_remarks,
        p_out_success => v_success,
        p_out_message => v_message
    );
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('success', v_success);
    APEX_JSON.WRITE('message', v_message);
    APEX_JSON.CLOSE_OBJECT;
END;


/*
══════════════════════════════════════════════════════════════
  AJAX PROCESS: CHECKER_REVERT_AJAX
  Called by: epfConfirmRevert() for ONBOARDING items
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_company_id NUMBER  := TO_NUMBER(APEX_APPLICATION.G_X01);
    v_remarks    VARCHAR2(2000) := APEX_APPLICATION.G_X02;
    v_success    VARCHAR2(1);
    v_message    VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.CHECKER_REVERT(
        p_company_id     => v_company_id,
        p_checker_id     => :APP_USER_ID,
        p_revert_remarks => v_remarks,
        p_out_success    => v_success,
        p_out_message    => v_message
    );
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('success', v_success);
    APEX_JSON.WRITE('message', v_message);
    APEX_JSON.CLOSE_OBJECT;
END;


/*
══════════════════════════════════════════════════════════════
  AJAX PROCESS: CR_CHECKER_APPROVE_AJAX
  Called by: epfConfirmApprove() for CHANGE_REQUEST items
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_cr_id   NUMBER  := TO_NUMBER(APEX_APPLICATION.G_X01);
    v_remarks VARCHAR2(2000) := APEX_APPLICATION.G_X02;
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.CR_CHECKER_APPROVE(
        p_change_req_id => v_cr_id,
        p_checker_id    => :APP_USER_ID,
        p_remarks       => v_remarks,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('success', v_success);
    APEX_JSON.WRITE('message', v_message);
    APEX_JSON.CLOSE_OBJECT;
END;


/*
══════════════════════════════════════════════════════════════
  AJAX PROCESS: CR_CHECKER_REVERT_AJAX
  Called by: epfConfirmRevert() for CHANGE_REQUEST items
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_cr_id   NUMBER  := TO_NUMBER(APEX_APPLICATION.G_X01);
    v_remarks VARCHAR2(2000) := APEX_APPLICATION.G_X02;
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.CR_CHECKER_REVERT(
        p_change_req_id  => v_cr_id,
        p_checker_id     => :APP_USER_ID,
        p_revert_remarks => v_remarks,
        p_out_success    => v_success,
        p_out_message    => v_message
    );
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('success', v_success);
    APEX_JSON.WRITE('message', v_message);
    APEX_JSON.CLOSE_OBJECT;
END;


/*
══════════════════════════════════════════════════════════════
  AJAX PROCESS: LOAD_GROUP_AJAX
  Called by: epfOpenGroupModal() when editing an existing group
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_group_id NUMBER := TO_NUMBER(APEX_APPLICATION.G_X01);
    v_name     VARCHAR2(200);
    v_min_appr NUMBER;
BEGIN
    SELECT GROUP_NAME, MIN_APPROVALS INTO v_name, v_min_appr
    FROM   EPF_AUTHORIZER_GROUPS
    WHERE  GROUP_ID = v_group_id;

    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('group_name',    v_name);
    APEX_JSON.WRITE('min_approvals', v_min_appr);
    APEX_JSON.OPEN_ARRAY('member_ids');
    FOR r IN (SELECT USER_ID FROM EPF_AUTHORIZER_GROUP_MEMBERS WHERE GROUP_ID = v_group_id ORDER BY USER_ID)
    LOOP
        APEX_JSON.WRITE(r.USER_ID);
    END LOOP;
    APEX_JSON.CLOSE_ARRAY;
    APEX_JSON.CLOSE_OBJECT;
EXCEPTION WHEN OTHERS THEN
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('error', SQLERRM);
    APEX_JSON.CLOSE_OBJECT;
END;


/*
══════════════════════════════════════════════════════════════
  Before-Header Process: LOAD_CHECKER_STATS
  Place on Checker Dashboard page (Page 20)
  Sets substitution items: STAT_NEW_CLIENTS, STAT_CHANGE_REQS,
                           STAT_REVERTED, STAT_TOTAL_PENDING
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_new_clients  NUMBER;
    v_change_reqs  NUMBER;
    v_reverted     NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_new_clients
    FROM   EPF_ONBOARDING_SUBMISSIONS sub
    JOIN   EPF_STATUSES s ON s.STATUS_ID = sub.STATUS_ID
    WHERE  s.STATUS_CODE = 'PENDING_CHECKER';

    SELECT COUNT(*) INTO v_change_reqs
    FROM   EPF_CLIENT_CHANGE_REQUESTS cr
    JOIN   EPF_STATUSES s ON s.STATUS_ID = cr.STATUS_ID
    WHERE  s.STATUS_CODE = 'PENDING_CHECKER';

    SELECT COUNT(*) INTO v_reverted
    FROM   EPF_CLIENT_CHANGE_REQUESTS cr
    JOIN   EPF_STATUSES s ON s.STATUS_ID = cr.STATUS_ID
    WHERE  s.STATUS_CODE = 'REVERTED'
    AND    TRUNC(cr.REVERTED_DATE,'MM') = TRUNC(SYSDATE,'MM');

    :STAT_NEW_CLIENTS  := v_new_clients;
    :STAT_CHANGE_REQS  := v_change_reqs;
    :STAT_REVERTED     := v_reverted;
    :STAT_TOTAL_PENDING:= v_new_clients + v_change_reqs;
END;


/*
══════════════════════════════════════════════════════════════
  Before-Header Process: LOAD_CR_FORM_DATA  (Page 15/30)
  Loads current live values for the Change Request form
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_comp   EPF_COMPANIES%ROWTYPE;
    v_sett   EPF_COMPANY_SETTINGS%ROWTYPE;
    v_cr_id  NUMBER;
    v_ref    VARCHAR2(30);
BEGIN
    SELECT * INTO v_comp FROM EPF_COMPANIES WHERE COMPANY_ID = :P_COMPANY_ID;
    SELECT * INTO v_sett FROM EPF_COMPANY_SETTINGS WHERE COMPANY_ID = :P_COMPANY_ID;

    :P_CURR_COMPANY_NAME  := v_comp.COMPANY_NAME;
    :P_CURR_COMPANY_CODE  := v_comp.COMPANY_CODE;
    :P_CURR_NTN           := v_comp.NTN;
    :P_CURR_ADDRESS       := v_comp.ADDRESS;
    :P_CURR_CITY          := v_comp.CITY;
    :P_CURR_CONTACT_EMAIL := v_comp.CONTACT_EMAIL;
    :P_CURR_CONTACT_PHONE := v_comp.CONTACT_PHONE;
    :P_CURR_CONTRIB_PCT   := v_sett.CONTRIBUTION_PCT;
    :P_CURR_EMPLOYER_PCT  := v_sett.EMPLOYER_PCT;
    :P_CURR_VESTING_MONTHS:= v_sett.VESTING_MONTHS;
    :P_CURR_MIN_CONTRIB   := v_sett.MIN_CONTRIBUTION;
    :P_CURR_MAX_CONTRIB   := v_sett.MAX_CONTRIBUTION;

    -- Init/get CR
    EPF_AAML_PKG.BEGIN_CHANGE_REQUEST(:P_COMPANY_ID, :APP_USER_ID, v_cr_id, v_ref);
    :P_CHANGE_REQ_ID    := v_cr_id;
    :P_CR_REF_NO        := v_ref;
    :P_CR_STARTED_DATE  := TO_CHAR(SYSDATE,'DD-Mon-YYYY');

    SELECT s.STATUS_NAME INTO :P_CR_STATUS_NAME
    FROM   EPF_CLIENT_CHANGE_REQUESTS cr
    JOIN   EPF_STATUSES s ON s.STATUS_ID = cr.STATUS_ID
    WHERE  cr.CHANGE_REQ_ID = v_cr_id;
END;
