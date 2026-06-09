-- ============================================================
--  APEX Page Processes  –  paste each block into the
--  corresponding APEX page's "Processing" section
-- ============================================================

/*
══════════════════════════════════════════════════════════════
  PAGE: ONBOARDING WIZARD – TAB 3  (Authorizer Groups)
  Process Name: SAVE_AUTHORIZER_GROUP
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_SAVE_GROUP]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.SAVE_AUTHORIZER_GROUP(
        p_group_id        => :P_AUTH_GROUP_ID,        -- hidden item, NULL on new
        p_company_id      => :P_COMPANY_ID,
        p_group_name      => :P_GROUP_NAME,
        p_min_approvals   => :P_MIN_APPROVALS,
        p_member_user_ids => :P_MEMBER_USER_IDS,      -- colon-separated (shuttle)
        p_performed_by    => :APP_USER_ID,
        p_out_group_id    => :P_AUTH_GROUP_ID,
        p_out_success     => v_success,
        p_out_message     => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
    END IF;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: ONBOARDING WIZARD – SUBMIT TO CHECKER
  Process Name: SUBMIT_TO_CHECKER
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_SUBMIT_CHECKER]
  After: Redirect to Maker Client Dashboard (Page 10)
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.SUBMIT_TO_CHECKER(
        p_company_id  => :P_COMPANY_ID,
        p_user_id     => :APP_USER_ID,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 10));
    END IF;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML CHECKER – APPROVE CLIENT
  Process Name: CHECKER_APPROVE
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_APPROVE]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.CHECKER_APPROVE(
        p_company_id  => :P_COMPANY_ID,
        p_checker_id  => :APP_USER_ID,
        p_remarks     => :P_CHECKER_REMARKS,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
        APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
    END IF;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML CHECKER – REVERT CLIENT
  Process Name: CHECKER_REVERT
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_REVERT]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    -- Client-side check already enforced, but double-guard here
    IF :P_REVERT_REMARKS IS NULL OR TRIM(:P_REVERT_REMARKS) IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Revert remarks are mandatory.',
            p_associated_item  => 'P_REVERT_REMARKS',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
        RETURN;
    END IF;

    EPF_AAML_PKG.CHECKER_REVERT(
        p_company_id     => :P_COMPANY_ID,
        p_checker_id     => :APP_USER_ID,
        p_revert_remarks => :P_REVERT_REMARKS,
        p_out_success    => v_success,
        p_out_message    => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
        APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
    END IF;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML CHECKER – APPROVE CHANGE REQUEST
  Process Name: CR_CHECKER_APPROVE
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_CR_APPROVE]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.CR_CHECKER_APPROVE(
        p_change_req_id => :P_CHANGE_REQ_ID,
        p_checker_id    => :APP_USER_ID,
        p_remarks       => :P_CHECKER_REMARKS,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
        APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 21));
    END IF;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML MAKER – BEGIN CHANGE REQUEST
  Process Name: BEGIN_CHANGE_REQUEST
  Type: PL/SQL Anonymous Block
  When: On Load / Before Header  OR  button action "Start CR"
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_cr_id   NUMBER;
    v_ref_no  VARCHAR2(30);
BEGIN
    EPF_AAML_PKG.BEGIN_CHANGE_REQUEST(
        p_company_id        => :P_COMPANY_ID,
        p_user_id           => :APP_USER_ID,
        p_out_change_req_id => v_cr_id,
        p_out_ref_no        => v_ref_no
    );
    :P_CHANGE_REQ_ID  := v_cr_id;
    :P_CR_REF_NO      := v_ref_no;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML MAKER – SAVE CR SECTION (ACCOUNT)
  Process Name: SAVE_CR_SECTION_ACCOUNT
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_SAVE_ACCOUNT_SECTION]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_json  CLOB;
BEGIN
    -- Build JSON from form fields
    v_json := JSON_OBJECT(
        'company_name'  VALUE :P_CR_COMPANY_NAME,
        'company_code'  VALUE :P_CR_COMPANY_CODE,
        'ntn'           VALUE :P_CR_NTN,
        'address'       VALUE :P_CR_ADDRESS,
        'city'          VALUE :P_CR_CITY,
        'contact_email' VALUE :P_CR_CONTACT_EMAIL,
        'contact_phone' VALUE :P_CR_CONTACT_PHONE
    );
    EPF_AAML_PKG.SAVE_CR_SECTION(
        p_change_req_id   => :P_CHANGE_REQ_ID,
        p_section_code    => 'ACCOUNT',
        p_new_values_json => v_json,
        p_change_summary  => :P_ACCOUNT_CHANGE_SUMMARY,
        p_user_id         => :APP_USER_ID
    );
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'Account section changes saved.';
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML MAKER – SAVE CR SECTION (SETTINGS)
  Process Name: SAVE_CR_SECTION_SETTINGS
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_SAVE_SETTINGS_SECTION]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_json  CLOB;
BEGIN
    v_json := JSON_OBJECT(
        'contribution_pct' VALUE TO_NUMBER(:P_CR_CONTRIB_PCT),
        'employer_pct'     VALUE TO_NUMBER(:P_CR_EMPLOYER_PCT),
        'vesting_months'   VALUE TO_NUMBER(:P_CR_VESTING_MONTHS),
        'min_contribution' VALUE TO_NUMBER(:P_CR_MIN_CONTRIB),
        'max_contribution' VALUE TO_NUMBER(:P_CR_MAX_CONTRIB)
    );
    EPF_AAML_PKG.SAVE_CR_SECTION(
        p_change_req_id   => :P_CHANGE_REQ_ID,
        p_section_code    => 'SETTINGS',
        p_new_values_json => v_json,
        p_change_summary  => :P_SETTINGS_CHANGE_SUMMARY,
        p_user_id         => :APP_USER_ID
    );
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'Settings section changes saved.';
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML MAKER – SUBMIT CR TO CHECKER
  Process Name: SUBMIT_CR_TO_CHECKER
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_SUBMIT_CR]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.SUBMIT_CR_TO_CHECKER(
        p_change_req_id => :P_CHANGE_REQ_ID,
        p_user_id       => :APP_USER_ID,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
        APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 10));
    END IF;
END;


/*
══════════════════════════════════════════════════════════════
  PAGE: AAML CHECKER – REVERT CHANGE REQUEST
  Process Name: CR_CHECKER_REVERT
  Type: PL/SQL Anonymous Block
  When: On Submit [Button = BTN_CR_REVERT]
══════════════════════════════════════════════════════════════
*/
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    IF :P_REVERT_REMARKS IS NULL OR TRIM(:P_REVERT_REMARKS) IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Revert remarks are mandatory.',
            p_associated_item  => 'P_REVERT_REMARKS',
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
        RETURN;
    END IF;

    EPF_AAML_PKG.CR_CHECKER_REVERT(
        p_change_req_id  => :P_CHANGE_REQ_ID,
        p_checker_id     => :APP_USER_ID,
        p_revert_remarks => :P_REVERT_REMARKS,
        p_out_success    => v_success,
        p_out_message    => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_WITH_FIELD_AND_NOTIF
        );
    ELSE
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
        APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
    END IF;
END;
