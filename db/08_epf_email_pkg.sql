-- ============================================================
-- FILE: /home/user/EPF/db/08_epf_email_pkg.sql
-- EPF PORTAL  –  Email Package (Spec + Body)
-- Depends on: EPF_USERS, EPF_EMAIL_LOGS, EPF_API_CONFIG
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_EMAIL_PKG AS
-- ============================================================
--  EPF_EMAIL_PKG  –  All outbound email dispatching
-- ============================================================

    -- Notify new user: welcome + set-password link (single-use)
    PROCEDURE SEND_WELCOME_EMAIL (
        p_user_id  IN NUMBER,
        p_token    IN VARCHAR2
    );

    -- Notify user: password reset link (2-hour expiry)
    PROCEDURE SEND_FORGOT_PWD_EMAIL (
        p_user_id  IN NUMBER,
        p_token    IN VARCHAR2
    );

    -- Send OTP for password change or forgot-password confirmation
    PROCEDURE SEND_OTP_EMAIL (
        p_user_id  IN NUMBER,
        p_otp      IN VARCHAR2,
        p_purpose  IN VARCHAR2   -- 'PWD_CHANGE' | 'FORGOT_PWD' | 'LOGIN_MFA'
    );

    -- Notify user that their account has been unblocked
    PROCEDURE SEND_UNBLOCK_EMAIL (
        p_user_id          IN NUMBER,
        p_unblocked_by_name IN VARCHAR2
    );

    -- Notify user that their account has been deactivated
    PROCEDURE SEND_DEACTIVATE_EMAIL (
        p_user_id  IN NUMBER
    );

    -- Notify user that their password was changed successfully
    PROCEDURE SEND_PWD_CHANGED_EMAIL (
        p_user_id  IN NUMBER
    );

END EPF_EMAIL_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_EMAIL_PKG AS
-- ============================================================
--  EPF_EMAIL_PKG  –  Body
-- ============================================================

    -- ─────────────────────────────────────────────────────────
    --  PRIVATE: Log an outbound email (autonomous transaction)
    -- ─────────────────────────────────────────────────────────
    PROCEDURE LOG_EMAIL (
        p_user_id      IN NUMBER,
        p_email        IN VARCHAR2,
        p_subject      IN VARCHAR2,
        p_body_summary IN VARCHAR2,
        p_type         IN VARCHAR2,
        p_status       IN VARCHAR2 DEFAULT 'SENT',
        p_error_msg    IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO EPF_EMAIL_LOGS (
            USER_ID, RECIPIENT_EMAIL, SUBJECT, BODY_SUMMARY,
            EMAIL_TYPE, STATUS, ERROR_MSG, SENT_DATE
        ) VALUES (
            p_user_id, p_email, p_subject, p_body_summary,
            p_type, p_status, p_error_msg, SYSDATE
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Never let logging break the caller
            ROLLBACK;
    END LOG_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  PRIVATE: Fetch configured base URL (EPF_API_CONFIG)
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_BASE_URL RETURN VARCHAR2 IS
        v_url VARCHAR2(500);
    BEGIN
        BEGIN
            SELECT CONFIG_VALUE
              INTO v_url
              FROM EPF_API_CONFIG
             WHERE CONFIG_KEY = 'APP_BASE_URL'
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_url := 'https://epf.alfalahinvestments.com';
        END;
        RETURN RTRIM(v_url, '/');
    END GET_BASE_URL;

    -- ─────────────────────────────────────────────────────────
    --  PRIVATE: Standard HTML wrapper for email body
    -- ─────────────────────────────────────────────────────────
    FUNCTION BUILD_EMAIL_HTML (
        p_content IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN
            '<html><body style="margin:0;padding:0;background:#f0f2f5;font-family:Arial,sans-serif;color:#333">'
         || '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:32px 0">'
         || '<tr><td align="center">'
         || '<table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:8px;'
         || 'overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08)">'
         -- Header
         || '<tr><td style="background:#003087;padding:24px 32px;text-align:center">'
         || '<h2 style="color:#fff;margin:0;font-size:22px;letter-spacing:0.5px">EPF Platform</h2>'
         || '<p style="color:#cce5ff;margin:4px 0 0;font-size:13px">Alfalah Investments</p>'
         || '</td></tr>'
         -- Body content
         || '<tr><td style="padding:32px">' || p_content || '</td></tr>'
         -- Footer
         || '<tr><td style="background:#f5f5f5;padding:16px 32px;text-align:center;'
         || 'font-size:11px;color:#999;border-top:1px solid #e0e0e0">'
         || 'This is a system-generated email. Please do not reply.<br/>'
         || '&copy; ' || TO_CHAR(SYSDATE,'YYYY') || ' Alfalah Investments Management Limited. All rights reserved.'
         || '</td></tr>'
         || '</table>'
         || '</td></tr></table>'
         || '</body></html>';
    END BUILD_EMAIL_HTML;

    -- ─────────────────────────────────────────────────────────
    --  PRIVATE: Build a styled button link
    -- ─────────────────────────────────────────────────────────
    FUNCTION BUTTON_LINK (
        p_label IN VARCHAR2,
        p_url   IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN
            '<div style="text-align:center;margin:28px 0">'
         || '<a href="' || p_url || '" '
         || 'style="background:#003087;color:#fff;text-decoration:none;'
         || 'padding:14px 36px;border-radius:4px;font-size:15px;font-weight:bold;'
         || 'display:inline-block;letter-spacing:0.3px">'
         || p_label
         || '</a></div>';
    END BUTTON_LINK;

    -- ─────────────────────────────────────────────────────────
    --  PRIVATE: Fetch user EMAIL + FULL_NAME
    -- ─────────────────────────────────────────────────────────
    PROCEDURE GET_USER_INFO (
        p_user_id   IN  NUMBER,
        p_email     OUT VARCHAR2,
        p_fullname  OUT VARCHAR2
    ) IS
    BEGIN
        SELECT EMAIL, FULL_NAME
          INTO p_email, p_fullname
          FROM EPF_USERS
         WHERE USER_ID = p_user_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_email    := NULL;
            p_fullname := 'User';
    END GET_USER_INFO;

    -- ═══════════════════════════════════════════════════════════
    --  PUBLIC PROCEDURES
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────
    --  SEND_WELCOME_EMAIL
    --  Sent when Admin creates a new user.
    --  Token is single-use (expires on click).
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_WELCOME_EMAIL (
        p_user_id IN NUMBER,
        p_token   IN VARCHAR2
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_url      VARCHAR2(1000);
        v_err      VARCHAR2(4000);
        v_mail_id  NUMBER;
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_url     := GET_BASE_URL() || '/f?p=EPF:9902:::::P9902_TOKEN:' || p_token;
        v_subject := 'Welcome to EPF Platform – Set Your Password';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Your EPF Platform account has been created. '
         || 'Please click the button below to set your password.</p>'
         || '<p style="line-height:1.7;color:#e65100;font-size:13px">'
         || '<strong>Important:</strong> This link will expire once used.</p>'
         || BUTTON_LINK('Set My Password', v_url)
         || '<p style="margin-top:24px;font-size:13px;color:#555">'
         || 'Your registered email: <strong>' || v_email || '</strong></p>'
         || '<p style="font-size:13px;color:#555">'
         || 'If you did not request this account, please contact '
         || '<a href="mailto:support@alfalahinvestments.com" style="color:#003087">'
         || 'support@alfalahinvestments.com</a> immediately.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to      => v_email,
                p_from    => 'noreply@alfalahinvestments.com',
                p_subj    => v_subject,
                p_body    => 'Dear ' || v_name || ', Your EPF Platform account has been created. '
                          || 'Please visit this link to set your password: ' || v_url,
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Welcome email with set-password link sent.', 'WELCOME');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send welcome email.', 'WELCOME', 'FAILED', v_err);
        END;
    END SEND_WELCOME_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_FORGOT_PWD_EMAIL
    --  Reset link with 2-hour expiry.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_FORGOT_PWD_EMAIL (
        p_user_id IN NUMBER,
        p_token   IN VARCHAR2
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_url      VARCHAR2(1000);
        v_err      VARCHAR2(4000);
        v_mail_id  NUMBER;
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_url     := GET_BASE_URL() || '/f?p=EPF:9902:::::P9902_TOKEN:' || p_token;
        v_subject := 'EPF Platform – Password Reset Request';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">A password reset request was received for your EPF Platform account. '
         || 'Click the button below to reset your password.</p>'
         || '<p style="line-height:1.7;color:#e65100;font-size:13px">'
         || '<strong>Important:</strong> This link will expire in <strong>2 hours</strong>.</p>'
         || BUTTON_LINK('Reset My Password', v_url)
         || '<p style="font-size:13px;color:#555;margin-top:24px">'
         || 'If you did not request a password reset, please ignore this email. '
         || 'Your password will not be changed.</p>'
         || '<p style="font-size:13px;color:#999">This link is valid for one-time use only.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Reset your password here: ' || v_url
                            || ' (expires in 2 hours).',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Forgot password reset link sent.', 'FORGOT_PWD');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send forgot password email.', 'FORGOT_PWD', 'FAILED', v_err);
        END;
    END SEND_FORGOT_PWD_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_OTP_EMAIL
    --  Sends 6-digit OTP. Valid 5 minutes.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_OTP_EMAIL (
        p_user_id IN NUMBER,
        p_otp     IN VARCHAR2,
        p_purpose IN VARCHAR2
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_mail_id  NUMBER;
        v_purpose_label VARCHAR2(100);
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_purpose_label := CASE p_purpose
            WHEN 'PWD_CHANGE'  THEN 'Change Password'
            WHEN 'FORGOT_PWD'  THEN 'Password Reset'
            WHEN 'LOGIN_MFA'   THEN 'Login Verification'
            ELSE p_purpose
        END;

        v_subject := 'EPF Platform – OTP for ' || v_purpose_label;

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Your One-Time Password (OTP) for '
         || '<strong>' || v_purpose_label || '</strong> is:</p>'
         || '<div style="text-align:center;margin:28px 0">'
         || '<span style="font-size:42px;font-weight:bold;letter-spacing:12px;'
         || 'color:#003087;background:#e8f0fe;padding:16px 28px;border-radius:8px;'
         || 'display:inline-block;font-family:''Courier New'',monospace">'
         || p_otp
         || '</span></div>'
         || '<p style="text-align:center;color:#e65100;font-size:13px">'
         || '<strong>This OTP is valid for 5 minutes only.</strong></p>'
         || '<p style="font-size:13px;color:#555;margin-top:16px">'
         || 'Do not share this OTP with anyone. '
         || 'Alfalah Investments staff will never ask for your OTP.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your OTP for ' || v_purpose_label
                            || ' is: ' || p_otp || ' (valid for 5 minutes). '
                            || 'Do not share this with anyone.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'OTP email sent for purpose: ' || p_purpose, 'OTP_' || p_purpose);
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send OTP email.', 'OTP_' || p_purpose, 'FAILED', v_err);
        END;
    END SEND_OTP_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_UNBLOCK_EMAIL
    --  Notify user that Admin has unblocked their account.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_UNBLOCK_EMAIL (
        p_user_id           IN NUMBER,
        p_unblocked_by_name IN VARCHAR2
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_mail_id  NUMBER;
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_subject := 'EPF Platform – Your Account Has Been Unblocked';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Your EPF Platform account has been unblocked by '
         || '<strong>' || p_unblocked_by_name || '</strong>.</p>'
         || '<p style="line-height:1.7">You can now log in using your registered email address '
         || '<strong>' || v_email || '</strong>.</p>'
         || '<div style="background:#e8f5e9;border-left:4px solid #43a047;padding:14px 18px;'
         || 'border-radius:4px;margin:20px 0">'
         || '<p style="margin:0;font-size:13px;color:#2e7d32">'
         || 'Your account is now active. If you experience any issues logging in, '
         || 'please contact your Corporate Administrator.</p>'
         || '</div>'
         || '<p style="font-size:13px;color:#555">If you did not expect this notification, '
         || 'please contact <a href="mailto:support@alfalahinvestments.com" style="color:#003087">'
         || 'support@alfalahinvestments.com</a> immediately.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your EPF Platform account has been unblocked by '
                            || p_unblocked_by_name || '. You can now log in.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Account unblocked notification sent.', 'UNBLOCK');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send unblock email.', 'UNBLOCK', 'FAILED', v_err);
        END;
    END SEND_UNBLOCK_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_DEACTIVATE_EMAIL
    --  Notify user that their account has been deactivated.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_DEACTIVATE_EMAIL (
        p_user_id IN NUMBER
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_mail_id  NUMBER;
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_subject := 'EPF Platform – Your Account Has Been Deactivated';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Your EPF Platform account has been deactivated. '
         || 'You will no longer be able to log in to the platform.</p>'
         || '<div style="background:#fff3e0;border-left:4px solid #ef6c00;padding:14px 18px;'
         || 'border-radius:4px;margin:20px 0">'
         || '<p style="margin:0;font-size:13px;color:#e65100">'
         || 'If you believe this was done in error, please contact your '
         || 'Corporate Administrator immediately.</p>'
         || '</div>'
         || '<p style="font-size:13px;color:#555">For further assistance, please contact '
         || '<a href="mailto:support@alfalahinvestments.com" style="color:#003087">'
         || 'support@alfalahinvestments.com</a>.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your EPF Platform account has been deactivated. '
                            || 'Please contact your Corporate Administrator if this is in error.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Deactivation notification sent.', 'DEACTIVATE');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send deactivation email.', 'DEACTIVATE', 'FAILED', v_err);
        END;
    END SEND_DEACTIVATE_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_PWD_CHANGED_EMAIL
    --  Confirmation that password was changed successfully.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_PWD_CHANGED_EMAIL (
        p_user_id IN NUMBER
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_mail_id  NUMBER;
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_subject := 'EPF Platform – Password Changed Successfully';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Your EPF Platform account password has been changed successfully.</p>'
         || '<p style="font-size:13px;color:#555">Date &amp; Time: '
         || '<strong>' || TO_CHAR(SYSDATE, 'DD-Mon-YYYY HH:MI:SS AM') || '</strong></p>'
         || '<div style="background:#fff3e0;border-left:4px solid #ef6c00;padding:14px 18px;'
         || 'border-radius:4px;margin:20px 0">'
         || '<p style="margin:0;font-size:13px;color:#e65100">'
         || '<strong>Did not change your password?</strong> If you did not make this change, '
         || 'please contact <a href="mailto:support@alfalahinvestments.com" style="color:#e65100">'
         || 'support@alfalahinvestments.com</a> immediately and reset your password using '
         || 'the Forgot Password feature.</p>'
         || '</div>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your EPF Platform password was changed on '
                            || TO_CHAR(SYSDATE,'DD-Mon-YYYY HH:MI AM') || '. '
                            || 'If you did not do this, contact support immediately.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Password changed confirmation sent.', 'PWD_CHANGED');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send password changed email.', 'PWD_CHANGED', 'FAILED', v_err);
        END;
    END SEND_PWD_CHANGED_EMAIL;

END EPF_EMAIL_PKG;
/

-- ============================================================
-- End of 08_epf_email_pkg.sql
-- ============================================================
