-- ============================================================
-- FILE: /home/user/EPF/db/14_epf_email_pkg_addons.sql
-- EPF PORTAL  –  Email Package (Full Rewrite – Spec + Body)
-- Adds 6 new procedures to EPF_EMAIL_PKG while preserving all
-- original 6 procedures verbatim from db/08_epf_email_pkg.sql.
-- New procedures implement FSD email scenarios #8, #9, #16, #19,
-- #20, #21.
-- Run after: 08_epf_email_pkg.sql (replaces it as canonical).
-- Depends on: EPF_USERS, EPF_EMAIL_LOGS, EPF_API_CONFIG
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_EMAIL_PKG AS
-- ============================================================
--  EPF_EMAIL_PKG  –  All outbound email dispatching
--  Version 2: includes original 6 procedures + 6 new ones.
-- ============================================================

    -- ── Original procedures (preserved verbatim from db/08) ───

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
        p_user_id           IN NUMBER,
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

    -- ── New procedures (FSD email scenarios #8, #9, #16, #19, #20, #21)

    -- Email #8: Unsuccessful login attempt (FSD scenario 8)
    PROCEDURE SEND_UNSUCCESSFUL_LOGIN_EMAIL (
        p_user_id  IN NUMBER
    );

    -- Email #9: Successful login notification (FSD scenario 9)
    PROCEDURE SEND_SUCCESSFUL_LOGIN_EMAIL (
        p_user_id  IN NUMBER
    );

    -- Email #16: Task rejected — sent to Maker/AAML Maker (FSD scenario 16)
    PROCEDURE SEND_TASK_REJECTED_EMAIL (
        p_maker_user_id    IN NUMBER,
        p_request_type     IN VARCHAR2,   -- e.g. 'Contribution Upload', 'Loan'
        p_ref_no           IN VARCHAR2,
        p_remarks          IN VARCHAR2,
        p_rejected_by_name IN VARCHAR2    -- '[user role and user name]'
    );

    -- Email #19: Request pending approval — sent to Checker/Authorizer (FSD scenario 19)
    PROCEDURE SEND_REQUEST_PENDING_EMAIL (
        p_approver_user_id  IN NUMBER,
        p_request_type      IN VARCHAR2,
        p_ref_no            IN VARCHAR2,
        p_created_by        IN VARCHAR2,
        p_created_on        IN DATE DEFAULT SYSDATE
    );

    -- Email #20: Request completed — sent to request creator (FSD scenario 20)
    PROCEDURE SEND_REQUEST_COMPLETED_EMAIL (
        p_maker_user_id  IN NUMBER,
        p_request_type   IN VARCHAR2,
        p_ref_no         IN VARCHAR2,
        p_created_on     IN DATE DEFAULT SYSDATE
    );

    -- Email #21: Account Statement email to employee (FSD scenario 21)
    PROCEDURE SEND_ACCOUNT_STATEMENT_EMAIL (
        p_employee_user_id  IN NUMBER,
        p_folio             IN VARCHAR2,
        p_fund_name         IN VARCHAR2,
        p_date_from         IN DATE,
        p_date_to           IN DATE,
        p_attachment        IN BLOB DEFAULT NULL
    );

END EPF_EMAIL_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_EMAIL_PKG AS
-- ============================================================
--  EPF_EMAIL_PKG  –  Body (Version 2)
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
    --  PUBLIC PROCEDURES  –  ORIGINAL 6 (verbatim from db/08)
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

        DECLARE v_mail_id NUMBER;
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

        DECLARE v_mail_id NUMBER;
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

        DECLARE v_mail_id NUMBER;
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

        DECLARE v_mail_id NUMBER;
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

        DECLARE v_mail_id NUMBER;
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

        DECLARE v_mail_id NUMBER;
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

    -- ═══════════════════════════════════════════════════════════
    --  PUBLIC PROCEDURES  –  NEW 6 (FSD scenarios #8, #9, #16, #19, #20, #21)
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────
    --  SEND_UNSUCCESSFUL_LOGIN_EMAIL  –  FSD email scenario #8
    --  Subject: Unsuccessful Login Attempt on EPF Platform
    --  Trigger: incorrect password login attempt
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_UNSUCCESSFUL_LOGIN_EMAIL (
        p_user_id  IN NUMBER
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_subject := 'Unsuccessful Login Attempt on EPF Platform';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Your attempt to log onto the Dedicated Employee Pension Fund (EPF) '
         || 'Platform has been unsuccessful.</p>'
         || '<p style="line-height:1.7">If you have forgotten your password, please use the '
         || '<strong>Forgot Password</strong> feature on the login page to set a new one.</p>'
         || '<div style="background:#fff3e0;border-left:4px solid #ef6c00;padding:14px 18px;'
         || 'border-radius:4px;margin:20px 0">'
         || '<p style="margin:0;font-size:13px;color:#e65100">'
         || 'If you did not attempt to log in, please contact your Corporate Administrator '
         || 'or Alfalah Investments immediately.</p>'
         || '</div>';

        v_body := BUILD_EMAIL_HTML(v_content);

        DECLARE v_mail_id NUMBER;
        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your attempt to log onto the EPF Platform '
                            || 'has been unsuccessful. Use Forgot Password if needed.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Unsuccessful login attempt notification sent.', 'LOGIN_FAIL');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send unsuccessful login email.', 'LOGIN_FAIL', 'FAILED', v_err);
        END;
    END SEND_UNSUCCESSFUL_LOGIN_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_SUCCESSFUL_LOGIN_EMAIL  –  FSD email scenario #9
    --  Subject: Successful Login on EPF Platform
    --  Trigger: every successful login
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_SUCCESSFUL_LOGIN_EMAIL (
        p_user_id  IN NUMBER
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_ts       VARCHAR2(30);
    BEGIN
        GET_USER_INFO(p_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_ts      := TO_CHAR(SYSDATE, 'HH:MI:SS AM');
        v_subject := 'Successful Login on EPF Platform';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">You have successfully logged onto the Dedicated Employee '
         || 'Pension Fund (EPF) Platform at <strong>' || v_ts || '</strong> on '
         || '<strong>' || TO_CHAR(SYSDATE,'DD-Mon-YYYY') || '</strong>.</p>'
         || '<div style="background:#e8f5e9;border-left:4px solid #43a047;padding:14px 18px;'
         || 'border-radius:4px;margin:20px 0">'
         || '<p style="margin:0;font-size:13px;color:#2e7d32">'
         || 'If you did not perform this login, please change your password immediately '
         || 'using the Change Password feature, or contact support.</p>'
         || '</div>';

        v_body := BUILD_EMAIL_HTML(v_content);

        DECLARE v_mail_id NUMBER;
        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', You have successfully logged onto the EPF Platform at '
                            || v_ts || ' on ' || TO_CHAR(SYSDATE,'DD-Mon-YYYY') || '.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_user_id, v_email, v_subject,
                      'Successful login notification sent.', 'LOGIN_OK');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_user_id, v_email, v_subject,
                          'Failed to send successful login email.', 'LOGIN_OK', 'FAILED', v_err);
        END;
    END SEND_SUCCESSFUL_LOGIN_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_TASK_REJECTED_EMAIL  –  FSD email scenario #16
    --  Subject: [Request Type] Request is Rejected
    --  Recipient: Maker (or AAML Maker) who created the request
    --  Trigger: any request rejected by any user
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_TASK_REJECTED_EMAIL (
        p_maker_user_id    IN NUMBER,
        p_request_type     IN VARCHAR2,
        p_ref_no           IN VARCHAR2,
        p_remarks          IN VARCHAR2,
        p_rejected_by_name IN VARCHAR2
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_ts       VARCHAR2(30);
    BEGIN
        GET_USER_INFO(p_maker_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_ts      := TO_CHAR(SYSDATE, 'HH:MI:SS AM');
        v_subject := p_request_type || ' Request is Rejected';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">A request you created has been rejected by '
         || '<strong>' || p_rejected_by_name || '</strong> at '
         || '<strong>' || v_ts || '</strong> on '
         || '<strong>' || TO_CHAR(SYSDATE,'DD-Mon-YYYY') || '</strong>.</p>'
         || '<table style="width:100%;border-collapse:collapse;margin:16px 0">'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0;width:40%">Request Type</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_request_type || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Reference No.</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_ref_no || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Remarks</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">'
         || NVL(p_remarks, '(no remarks)') || '</td></tr>'
         || '</table>'
         || BUTTON_LINK('Log onto EPF Platform', GET_BASE_URL())
         || '<p style="font-size:13px;color:#555">Please log onto the Dedicated EPF Platform '
         || 'to view further details.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        DECLARE v_mail_id NUMBER;
        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your ' || p_request_type
                            || ' request (Ref: ' || p_ref_no || ') has been rejected by '
                            || p_rejected_by_name || '. Remarks: ' || NVL(p_remarks,'(none)'),
                p_body_html => v_body
            );
            LOG_EMAIL(p_maker_user_id, v_email, v_subject,
                      'Task rejected notification sent. Ref: ' || p_ref_no, 'TASK_REJECTED');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_maker_user_id, v_email, v_subject,
                          'Failed to send task rejected email.', 'TASK_REJECTED', 'FAILED', v_err);
        END;
    END SEND_TASK_REJECTED_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_REQUEST_PENDING_EMAIL  –  FSD email scenario #19
    --  Subject: [Request Type] Request is pending approval
    --  Recipient: relevant approver (Checker or Authorizer)
    --  Trigger: request lands at user for approval
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_REQUEST_PENDING_EMAIL (
        p_approver_user_id  IN NUMBER,
        p_request_type      IN VARCHAR2,
        p_ref_no            IN VARCHAR2,
        p_created_by        IN VARCHAR2,
        p_created_on        IN DATE DEFAULT SYSDATE
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
    BEGIN
        GET_USER_INFO(p_approver_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_subject := p_request_type || ' Request is pending approval';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">A <strong>' || p_request_type
         || '</strong> request is pending your approval.</p>'
         || '<table style="width:100%;border-collapse:collapse;margin:16px 0">'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0;width:40%">Request Type</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_request_type || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Reference No.</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_ref_no || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Created By</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_created_by || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Created On</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">'
         || TO_CHAR(p_created_on, 'DD-Mon-YYYY HH:MI AM') || '</td></tr>'
         || '</table>'
         || BUTTON_LINK('Log onto EPF Platform', GET_BASE_URL())
         || '<p style="font-size:13px;color:#555">Please log onto the Dedicated EPF Platform '
         || 'to review the request.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        DECLARE v_mail_id NUMBER;
        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', A ' || p_request_type
                            || ' request (Ref: ' || p_ref_no || ') created by '
                            || p_created_by || ' is pending your approval.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_approver_user_id, v_email, v_subject,
                      'Pending approval notification. Ref: ' || p_ref_no, 'REQ_PENDING');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_approver_user_id, v_email, v_subject,
                          'Failed to send request pending email.', 'REQ_PENDING', 'FAILED', v_err);
        END;
    END SEND_REQUEST_PENDING_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_REQUEST_COMPLETED_EMAIL  –  FSD email scenario #20
    --  Subject: [Request Type] Request is Completed
    --  Recipient: request creator (Maker / AAML Maker)
    --  Trigger: all required approvals complete (incl. AAML Checker)
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_REQUEST_COMPLETED_EMAIL (
        p_maker_user_id  IN NUMBER,
        p_request_type   IN VARCHAR2,
        p_ref_no         IN VARCHAR2,
        p_created_on     IN DATE DEFAULT SYSDATE
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_ts       VARCHAR2(30);
    BEGIN
        GET_USER_INFO(p_maker_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_ts      := TO_CHAR(SYSDATE, 'HH:MI:SS AM');
        v_subject := p_request_type || ' Request is Completed';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7"><strong>' || p_request_type
         || '</strong> Request has been successfully completed on the Dedicated Employee '
         || 'Pension Fund (EPF) Platform at <strong>' || v_ts || '</strong> on '
         || '<strong>' || TO_CHAR(SYSDATE,'DD-Mon-YYYY') || '</strong>.</p>'
         || '<table style="width:100%;border-collapse:collapse;margin:16px 0">'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0;width:40%">Request Type</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_request_type || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Reference No.</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_ref_no || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Created On</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">'
         || TO_CHAR(p_created_on, 'DD-Mon-YYYY HH:MI AM') || '</td></tr>'
         || '</table>'
         || '<div style="background:#e8f5e9;border-left:4px solid #43a047;padding:14px 18px;'
         || 'border-radius:4px;margin:20px 0">'
         || '<p style="margin:0;font-size:13px;color:#2e7d32">'
         || 'This request has been fully processed. No further action is required.</p>'
         || '</div>';

        v_body := BUILD_EMAIL_HTML(v_content);

        DECLARE v_mail_id NUMBER;
        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your ' || p_request_type
                            || ' request (Ref: ' || p_ref_no || ') has been completed at '
                            || v_ts || ' on ' || TO_CHAR(SYSDATE,'DD-Mon-YYYY') || '.',
                p_body_html => v_body
            );
            LOG_EMAIL(p_maker_user_id, v_email, v_subject,
                      'Request completed notification. Ref: ' || p_ref_no, 'REQ_COMPLETED');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_maker_user_id, v_email, v_subject,
                          'Failed to send request completed email.', 'REQ_COMPLETED', 'FAILED', v_err);
        END;
    END SEND_REQUEST_COMPLETED_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  SEND_ACCOUNT_STATEMENT_EMAIL  –  FSD email scenario #21
    --  Subject: Your Account Statement from EPF Platform
    --  Recipient: the employee who requested it
    --  Trigger: employee clicks 'Request on Email' on Account Statement page
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_ACCOUNT_STATEMENT_EMAIL (
        p_employee_user_id  IN NUMBER,
        p_folio             IN VARCHAR2,
        p_fund_name         IN VARCHAR2,
        p_date_from         IN DATE,
        p_date_to           IN DATE,
        p_attachment        IN BLOB DEFAULT NULL
    ) IS
        v_email    EPF_USERS.EMAIL%TYPE;
        v_name     EPF_USERS.FULL_NAME%TYPE;
        v_subject  VARCHAR2(500);
        v_body     VARCHAR2(32767);
        v_content  VARCHAR2(32767);
        v_err      VARCHAR2(4000);
        v_period   VARCHAR2(100);
        v_mail_id  NUMBER;
    BEGIN
        GET_USER_INFO(p_employee_user_id, v_email, v_name);
        IF v_email IS NULL THEN RETURN; END IF;

        v_period  := TO_CHAR(p_date_from,'DD-Mon-YYYY') || ' to ' || TO_CHAR(p_date_to,'DD-Mon-YYYY');
        v_subject := 'Your Account Statement from EPF Platform';

        v_content :=
            '<p style="font-size:15px">Dear <strong>' || v_name || '</strong>,</p>'
         || '<p style="line-height:1.7">Please find attached your Account Statement from the '
         || 'Dedicated Employee Pension Fund (EPF) Platform for the period '
         || '<strong>' || v_period || '</strong>.</p>'
         || '<table style="width:100%;border-collapse:collapse;margin:16px 0">'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0;width:40%">Folio</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_folio || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Fund</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || p_fund_name || '</td></tr>'
         || '<tr><td style="padding:8px 12px;background:#f5f5f5;font-weight:bold;'
         || 'border:1px solid #e0e0e0">Period</td>'
         || '<td style="padding:8px 12px;border:1px solid #e0e0e0">' || v_period || '</td></tr>'
         || '</table>'
         || '<p style="font-size:13px;color:#555">'
         || 'Please find your account statement attached to this email. '
         || 'If the attachment is not visible, please log onto the EPF Platform '
         || 'to view and download your statement.</p>';

        v_body := BUILD_EMAIL_HTML(v_content);

        BEGIN
            v_mail_id := APEX_MAIL.SEND(
                p_to        => v_email,
                p_from      => 'noreply@alfalahinvestments.com',
                p_subj      => v_subject,
                p_body      => 'Dear ' || v_name || ', Your account statement for '
                            || v_period || ' (Folio: ' || p_folio || ', Fund: '
                            || p_fund_name || ') is attached.',
                p_body_html => v_body
            );

            -- Attach PDF if provided (stub: APEX_MAIL.ADD_ATTACHMENT)
            IF p_attachment IS NOT NULL THEN
                APEX_MAIL.ADD_ATTACHMENT(
                    p_mail_id    => v_mail_id,
                    p_attachment => p_attachment,
                    p_filename   => 'AccountStatement_' || p_folio || '_'
                                 || TO_CHAR(p_date_from,'YYYYMMDD') || '_'
                                 || TO_CHAR(p_date_to,'YYYYMMDD') || '.pdf',
                    p_mime_type  => 'application/pdf'
                );
            END IF;

            LOG_EMAIL(p_employee_user_id, v_email, v_subject,
                      'Account statement emailed. Period: ' || v_period, 'ACCT_STMT');
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                LOG_EMAIL(p_employee_user_id, v_email, v_subject,
                          'Failed to send account statement email.', 'ACCT_STMT', 'FAILED', v_err);
        END;
    END SEND_ACCOUNT_STATEMENT_EMAIL;

END EPF_EMAIL_PKG;
/

-- ============================================================
-- End of 14_epf_email_pkg_addons.sql
-- ============================================================
