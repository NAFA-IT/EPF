-- ============================================================
-- FILE: /home/user/EPF/apex/corp_admin/page_processes.sql
-- EPF PORTAL  –  Corporate Admin Module – APEX Page Processes
-- All processes are PL/SQL Anonymous Blocks to be pasted into
-- APEX Application Builder as "Execute PL/SQL Code" processes.
-- ============================================================

-- ============================================================
-- PAGE 30  –  User Management
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: CORP_ADMIN_CREATE_USER
-- When:    On Submit (after validation)
-- Condition: Request = 'CREATE_USER'
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_user_id  NUMBER;
BEGIN
    EPF_CORP_ADMIN_PKG.CREATE_USER(
        p_company_id       => :APP_COMPANY_ID,
        p_created_by_ucid  => :APP_USER_COMPANY_ID,
        p_role_code        => :P30_ROLE_CODE,
        p_full_name        => :P30_FULL_NAME,
        p_email            => :P30_EMAIL,
        p_mobile_no        => :P30_MOBILE_NO,
        p_employee_code    => :P30_EMPLOYEE_CODE,
        p_out_success      => v_success,
        p_out_message      => v_message,
        p_out_user_id      => v_user_id
    );

    IF v_success = 'Y' THEN
        :P30_CREATED_USER_ID := v_user_id;
        :P30_SUCCESS_MSG     := 'User has been created successfully.';
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User has been created successfully.';
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: CORP_ADMIN_UPDATE_USER
-- When:    On Submit (after validation)
-- Condition: Request = 'UPDATE_USER'
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_CORP_ADMIN_PKG.UPDATE_USER(
        p_user_company_id  => :P30_EDIT_USER_COMPANY_ID,
        p_updated_by_ucid  => :APP_USER_COMPANY_ID,
        p_role_code        => :P30_EDIT_ROLE_CODE,
        p_full_name        => :P30_EDIT_FULL_NAME,
        p_mobile_no        => :P30_EDIT_MOBILE_NO,
        p_employee_code    => :P30_EDIT_EMPLOYEE_CODE,
        p_new_status_code  => :P30_EDIT_STATUS_CODE,
        p_out_success      => v_success,
        p_out_message      => v_message
    );

    IF v_success = 'Y' THEN
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User details have been updated successfully.';
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: CORP_ADMIN_DELETE_USERS
-- When:    On Submit (after validation)
-- Condition: Request = 'DELETE_USERS'
-- Item: P30_SELECTED_USER_IDS – colon-separated USER_COMPANY_IDs
--       populated by checkbox selection JavaScript (epfConfirmDelete)
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_count    NUMBER;
BEGIN
    IF :P30_SELECTED_USER_IDS IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one user to delete.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    EPF_CORP_ADMIN_PKG.DELETE_USERS(
        p_user_company_ids => :P30_SELECTED_USER_IDS,
        p_deleted_by_ucid  => :APP_USER_COMPANY_ID,
        p_out_success      => v_success,
        p_out_message      => v_message,
        p_out_count        => v_count
    );

    IF v_success = 'Y' THEN
        :P30_SELECTED_USER_IDS := NULL;   -- clear selection
        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_count || ' user(s) deleted successfully.';
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 9901  –  Forgot Password
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: FORGOT_PASSWORD_SUBMIT
-- When:    On Submit
-- Note:    Always displays success message (per FSD security rule —
--          do not reveal whether email is registered).
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_AUTH_PKG.FORGOT_PASSWORD(
        p_email       => LOWER(TRIM(:P9901_EMAIL)),
        p_ip          => OWA_UTIL.GET_CGI_ENV('REMOTE_ADDR'),
        p_out_success => v_success,
        p_out_message => v_message
    );

    -- Per FSD: always show the same message regardless of outcome
    :P9901_SUCCESS_MSG := 'A password reset link has been sent to your email address. '
                       || 'The link will expire in 2 hours.';
    :P9901_SHOW_SUCCESS := 'Y';
END;

-- ============================================================
-- PAGE 9902  –  Set / Reset Password
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: VALIDATE_RESET_TOKEN
-- When:    Before Header (runs before page renders)
-- Purpose: Validates the token from the URL; sets page items
--          so the page can show valid/expired state.
-- ------------------------------------------------------------
DECLARE
    v_user_id NUMBER;
BEGIN
    v_user_id := EPF_AUTH_PKG.VALIDATE_RESET_TOKEN(:P9902_TOKEN);

    IF v_user_id = 0 OR v_user_id IS NULL THEN
        :P9902_TOKEN_VALID := 'N';
        :P9902_ERROR_MSG   := 'This link to reset your password has expired or is invalid. '
                           || 'Please use the Forgot Password feature again.';
        :P9902_USER_ID     := NULL;
    ELSE
        :P9902_TOKEN_VALID := 'Y';
        :P9902_ERROR_MSG   := NULL;
        :P9902_USER_ID     := v_user_id;
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: SET_NEW_PASSWORD
-- When:    On Submit
-- Condition: Request = 'SUBMIT_NEW_PASSWORD' AND P9902_TOKEN_VALID = 'Y'
-- ------------------------------------------------------------
DECLARE
    v_success   VARCHAR2(1);
    v_message   VARCHAR2(4000);
    v_otp_sent  VARCHAR2(1);
BEGIN
    -- Guard: token must still be valid
    IF NVL(:P9902_TOKEN_VALID, 'N') != 'Y' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Invalid or expired session. Please request a new reset link.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    EPF_AUTH_PKG.SET_NEW_PASSWORD_REQUEST(
        p_user_id          => :P9902_USER_ID,
        p_new_password     => :P9902_NEW_PASSWORD,
        p_confirm_password => :P9902_CONFIRM_PASSWORD,
        p_out_success      => v_success,
        p_out_message      => v_message,
        p_out_otp_sent     => v_otp_sent
    );

    IF v_success = 'Y' THEN
        :P9902_OTP_SENT  := 'Y';
        :P9902_STEP      := '2';     -- advance UI to OTP entry step
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: CONFIRM_OTP_RESET_PWD
-- When:    On Submit
-- Condition: Request = 'CONFIRM_OTP_RESET'
-- Note:    This process also applies the new password hash.
--          P9902_NEW_PASSWORD must still be in session.
-- ------------------------------------------------------------
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_salt    VARCHAR2(200);
    v_hash    VARCHAR2(256);
BEGIN
    -- First confirm the OTP (validates attempt count, expiry, locking)
    EPF_AUTH_PKG.CONFIRM_OTP_AND_SET_PASSWORD(
        p_user_id     => :P9902_USER_ID,
        p_otp         => :P9902_OTP,
        p_token       => :P9902_TOKEN,
        p_out_success => v_success,
        p_out_message => v_message
    );

    IF v_success = 'Y' THEN
        -- Apply the new password (hash + save)
        -- EPF_AUTH_PKG.APPLY_NEW_PASSWORD is an internal utility
        -- exposed here; a direct UPDATE using the private helper is
        -- called via a wrapper below to keep PL/SQL encapsulated.
        DECLARE
            v_new_salt VARCHAR2(200);
            v_new_hash VARCHAR2(256);
        BEGIN
            -- Re-hash using the raw password captured in session item
            -- The password was already strength-validated in SET_NEW_PASSWORD_REQUEST
            v_new_salt := RAWTOHEX(DBMS_CRYPTO.RANDOMBYTES(32));
            v_new_hash := RAWTOHEX(
                              DBMS_CRYPTO.HASH(
                                  src => UTL_RAW.CAST_TO_RAW(:P9902_NEW_PASSWORD || v_new_salt),
                                  typ => DBMS_CRYPTO.HASH_SH512
                              )
                          );

            UPDATE EPF_USERS
               SET PASSWORD_HASH      = v_new_hash,
                   PASSWORD_SALT      = v_new_salt,
                   FORCE_PWD_CHANGE   = 'N',
                   FAILED_LOGIN_COUNT = 0,
                   ACCOUNT_LOCKED     = 'N'
             WHERE USER_ID = :P9902_USER_ID;
            COMMIT;
        END;

        -- Clear sensitive session items
        :P9902_NEW_PASSWORD     := NULL;
        :P9902_CONFIRM_PASSWORD := NULL;
        :P9902_OTP              := NULL;

        :P9902_SUCCESS_MSG := 'Your password has been updated successfully. '
                           || 'You will be redirected to the login page.';
        :P9902_SHOW_SUCCESS := 'Y';

        -- Redirect to login after short delay (handled by JS on page)
        APEX_UTIL.REDIRECT_URL(
            APEX_PAGE.GET_URL(
                p_page        => 101,
                p_clear_cache => '101'
            )
        );
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- PAGE 9903  –  Change Password (Modal Dialog)
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: CHANGE_PASSWORD_REQUEST
-- When:    On Submit
-- Condition: Request = 'CHANGE_PWD_REQUEST'
-- ------------------------------------------------------------
DECLARE
    v_success   VARCHAR2(1);
    v_message   VARCHAR2(4000);
    v_otp_sent  VARCHAR2(1);
BEGIN
    EPF_AUTH_PKG.CHANGE_PASSWORD(
        p_user_id          => :APP_USER_ID,
        p_current_password => :P9903_CURRENT_PASSWORD,
        p_new_password     => :P9903_NEW_PASSWORD,
        p_confirm_password => :P9903_CONFIRM_PASSWORD,
        p_out_success      => v_success,
        p_out_message      => v_message,
        p_out_otp_sent     => v_otp_sent
    );

    IF v_success = 'Y' THEN
        :P9903_OTP_SENT := 'Y';
        :P9903_STEP     := '2';   -- advance UI to OTP step
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ------------------------------------------------------------
-- PROCESS: CONFIRM_OTP_CHANGE_PWD
-- When:    On Submit
-- Condition: Request = 'CONFIRM_OTP_CHANGE'
-- Note:    Applies new password hash after OTP validation.
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    -- Validate OTP and mark used
    EPF_AUTH_PKG.CONFIRM_OTP_CHANGE_PASSWORD(
        p_user_id     => :APP_USER_ID,
        p_otp         => :P9903_OTP,
        p_out_success => v_success,
        p_out_message => v_message
    );

    IF v_success = 'Y' THEN
        -- Apply the new password hash (same inline pattern as reset flow)
        DECLARE
            v_new_salt VARCHAR2(200);
            v_new_hash VARCHAR2(256);
        BEGIN
            v_new_salt := RAWTOHEX(DBMS_CRYPTO.RANDOMBYTES(32));
            v_new_hash := RAWTOHEX(
                              DBMS_CRYPTO.HASH(
                                  src => UTL_RAW.CAST_TO_RAW(:P9903_NEW_PASSWORD || v_new_salt),
                                  typ => DBMS_CRYPTO.HASH_SH512
                              )
                          );

            UPDATE EPF_USERS
               SET PASSWORD_HASH    = v_new_hash,
                   PASSWORD_SALT    = v_new_salt,
                   FORCE_PWD_CHANGE = 'N'
             WHERE USER_ID = :APP_USER_ID;
            COMMIT;
        END;

        -- Clear sensitive session items
        :P9903_CURRENT_PASSWORD := NULL;
        :P9903_NEW_PASSWORD     := NULL;
        :P9903_CONFIRM_PASSWORD := NULL;
        :P9903_OTP              := NULL;

        APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'Password changed successfully.';

        -- Close modal and refresh parent page
        APEX_JAVASCRIPT.ADD_ONLOAD_CODE(
            p_code => 'apex.navigation.dialog.close(true);'
        );
    ELSE
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
    END IF;
END;

-- ============================================================
-- APPLICATION PROCESS: RESEND_OTP_AJAX
-- Type:    On Demand (Application Process)
-- Name:    RESEND_OTP_AJAX
-- Returns: JSON {success, message, resend_count}
-- Called via: apex.server.process('RESEND_OTP_AJAX', ...)
-- Required page items in request:
--   x01 = purpose  ('PWD_CHANGE' | 'FORGOT_PWD')
--   x02 = user_id  (NUMBER — for forgot-pwd flow where APP_USER_ID may be 0)
-- ============================================================
DECLARE
    v_success    VARCHAR2(1);
    v_message    VARCHAR2(4000);
    v_user_id    NUMBER;
    v_purpose    VARCHAR2(30);
    v_resend_cnt NUMBER;
BEGIN
    v_purpose := APEX_APPLICATION.G_X01;
    v_user_id := CASE
                     WHEN APEX_APPLICATION.G_X02 IS NOT NULL
                          AND APEX_APPLICATION.G_X02 != '0'
                     THEN TO_NUMBER(APEX_APPLICATION.G_X02)
                     ELSE :APP_USER_ID
                 END;

    EPF_AUTH_PKG.RESEND_OTP(
        p_user_id     => v_user_id,
        p_purpose     => v_purpose,
        p_out_success => v_success,
        p_out_message => v_message
    );

    -- Fetch updated resend count for UI display
    BEGIN
        SELECT RESEND_COUNT
          INTO v_resend_cnt
          FROM EPF_OTP_REQUESTS
         WHERE USER_ID  = v_user_id
           AND PURPOSE  = v_purpose
           AND USED_YN  = 'N'
         ORDER BY CREATED_DATE DESC
         FETCH FIRST 1 ROW ONLY;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN v_resend_cnt := 4;
    END;

    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('success',      v_success);
    APEX_JSON.WRITE('message',      v_message);
    APEX_JSON.WRITE('resend_count', v_resend_cnt);
    APEX_JSON.WRITE('resend_remaining', GREATEST(0, 4 - v_resend_cnt));
    APEX_JSON.CLOSE_OBJECT;
END;

-- ============================================================
-- End of page_processes.sql
-- ============================================================
