-- ============================================================
-- FILE: /home/user/EPF/db/19_epf_pkg_auth.sql
-- EPF_PKG_AUTH  –  Consolidated Authentication Package
-- Replaces both EPF_PKG_AUTH and EPF_AUTH_PKG.
-- Wire APEX Authentication Scheme to: EPF_PKG_AUTH.APEX_AUTHENTICATE
-- Wire APEX Post-Authentication Process to: EPF_PKG_AUTH.POST_AUTH_SETUP
-- Depends on: UC_CRYPTO, EPF_STATUS_PKG, EPF_UTIL, EPF_EMAIL_PKG
-- Tables: EPF_USERS, EPF_USER_SESSION_LOG, EPF_USER_ACCOUNT_LOCKS,
--         EPF_PASSWORD_TOKENS, EPF_OTP_REQUESTS, EPF_ACTIVITY_LOGS
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_PKG_AUTH AS

  -- ── Constants ────────────────────────────────────────────────
  FROM_EMAIL           CONSTANT VARCHAR2(100) := 'epf.portal@alfalahamc.com';
  MAX_FAILED_ATTEMPTS  CONSTANT PLS_INTEGER   := 5;
  PWD_LINK_EXPIRY_HRS  CONSTANT PLS_INTEGER   := 2;
  OTP_EXPIRY_MINS      CONSTANT PLS_INTEGER   := 5;
  MAX_OTP_RESENDS      CONSTANT PLS_INTEGER   := 4;

  -- ── Result codes (for verify_otp / internal use) ─────────────
  AUTH_OK                    CONSTANT PLS_INTEGER := 0;
  AUTH_BAD_CREDENTIALS       CONSTANT PLS_INTEGER := 1;
  AUTH_ACCOUNT_LOCKED        CONSTANT PLS_INTEGER := 2;
  AUTH_ACCOUNT_INACTIVE      CONSTANT PLS_INTEGER := 3;
  AUTH_FORCE_PASSWORD_CHANGE CONSTANT PLS_INTEGER := 4;
  AUTH_OTP_REQUIRED          CONSTANT PLS_INTEGER := 5;
  AUTH_OTP_INVALID           CONSTANT PLS_INTEGER := 6;
  AUTH_OTP_EXPIRED           CONSTANT PLS_INTEGER := 7;

  -- ── APEX Integration ─────────────────────────────────────────

  -- Wire to APEX Authentication Scheme > Authentication Function
  FUNCTION APEX_AUTHENTICATE (
    p_username IN VARCHAR2,
    p_password IN VARCHAR2
  ) RETURN BOOLEAN;

  -- Wire to APEX Post-Authentication Process
  PROCEDURE POST_AUTH_SETUP;

  -- ── Password Utilities ───────────────────────────────────────

  FUNCTION  HASH_PASSWORD    (p_password IN VARCHAR2, p_salt IN VARCHAR2) RETURN VARCHAR2;
  FUNCTION  GENERATE_SALT    RETURN VARCHAR2;
  FUNCTION  VALIDATE_PASSWORD_POLICY (p_password IN VARCHAR2) RETURN VARCHAR2; -- NULL = OK

  -- Apply a new password directly (called by APEX after OTP confirm)
  PROCEDURE APPLY_NEW_PASSWORD (
    p_user_id  IN NUMBER,
    p_new_pwd  IN VARCHAR2
  );

  -- ── Forgot Password Flow ─────────────────────────────────────

  -- Step 0: Initiate reset (always returns success to prevent email enumeration)
  PROCEDURE FORGOT_PASSWORD (
    p_email       IN  VARCHAR2,
    p_ip          IN  VARCHAR2 DEFAULT NULL,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  );

  -- Validate a reset / set-password token; returns user_id or 0 if invalid/expired
  FUNCTION VALIDATE_RESET_TOKEN (p_token IN VARCHAR2) RETURN NUMBER;

  -- Step 1: Validate new password + send OTP
  PROCEDURE SET_NEW_PASSWORD_REQUEST (
    p_user_id      IN  NUMBER,
    p_new_password IN  VARCHAR2,
    p_confirm_pwd  IN  VARCHAR2,
    p_out_success  OUT VARCHAR2,
    p_out_message  OUT VARCHAR2,
    p_out_otp_sent OUT VARCHAR2
  );

  -- Step 2: Confirm OTP (then call APPLY_NEW_PASSWORD)
  PROCEDURE CONFIRM_OTP_AND_SET_PASSWORD (
    p_user_id     IN  NUMBER,
    p_otp         IN  VARCHAR2,
    p_token       IN  VARCHAR2,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  );

  -- ── Change Password Flow (logged-in user) ────────────────────

  -- Step 1: Verify current password + send OTP
  PROCEDURE CHANGE_PASSWORD (
    p_user_id      IN  NUMBER,
    p_current_pwd  IN  VARCHAR2,
    p_new_password IN  VARCHAR2,
    p_confirm_pwd  IN  VARCHAR2,
    p_out_success  OUT VARCHAR2,
    p_out_message  OUT VARCHAR2,
    p_out_otp_sent OUT VARCHAR2
  );

  -- Step 2: Confirm OTP (then call APPLY_NEW_PASSWORD)
  PROCEDURE CONFIRM_OTP_CHANGE_PASSWORD (
    p_user_id     IN  NUMBER,
    p_otp         IN  VARCHAR2,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  );

  -- Resend OTP (max MAX_OTP_RESENDS; exceeding blocks the account)
  PROCEDURE RESEND_OTP (
    p_user_id     IN  NUMBER,
    p_purpose     IN  VARCHAR2,   -- 'FORGOT_PWD' | 'PWD_CHANGE'
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  );

  -- ── First-Time Setup ─────────────────────────────────────────

  -- Called after user creation: generate set-password token + send welcome email
  PROCEDURE SET_FIRST_PASSWORD_TOKEN (
    p_user_id IN NUMBER,
    p_ip      IN VARCHAR2 DEFAULT NULL
  );

  -- ── Admin Actions ────────────────────────────────────────────

  PROCEDURE ADMIN_BLOCK_USER   (p_email IN VARCHAR2, p_admin IN VARCHAR2, p_reason IN VARCHAR2);
  PROCEDURE ADMIN_UNBLOCK_USER (p_email IN VARCHAR2, p_admin IN VARCHAR2);
  PROCEDURE FORCE_PASSWORD_CHANGE (p_user_id IN NUMBER);

  -- ── Activity Logging (public – callable by other packages) ───
  -- Inserts into EPF_ACTIVITY_LOGS (user/session oriented log)
  PROCEDURE LOG_ACTIVITY (
    p_user_id         IN NUMBER,
    p_company_id      IN NUMBER   DEFAULT NULL,
    p_user_company_id IN NUMBER   DEFAULT NULL,
    p_action_code     IN VARCHAR2,
    p_action_detail   IN VARCHAR2,
    p_page_name       IN VARCHAR2 DEFAULT NULL
  );

END EPF_PKG_AUTH;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_PKG_AUTH AS

  -- ═══════════════════════════════════════════════════════════
  --  PRIVATE HELPERS
  -- ═══════════════════════════════════════════════════════════

  FUNCTION HASH_PASSWORD (p_password IN VARCHAR2, p_salt IN VARCHAR2)
    RETURN VARCHAR2 IS
    l_raw RAW(2000);
  BEGIN
    l_raw := UC_CRYPTO.HASH(
                UTL_RAW.CAST_TO_RAW(p_password || ':' || p_salt),
                UC_CRYPTO.HASH_SH512);
    RETURN RAWTOHEX(l_raw);
  END HASH_PASSWORD;

  FUNCTION GENERATE_SALT RETURN VARCHAR2 IS
  BEGIN
    RETURN RAWTOHEX(UC_CRYPTO.RANDOMBYTES(32));
  END GENERATE_SALT;

  FUNCTION GENERATE_OTP RETURN VARCHAR2 IS
  BEGIN
    RETURN LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(100000, 999999))), 6, '0');
  END GENERATE_OTP;

  FUNCTION GENERATE_TOKEN RETURN VARCHAR2 IS
  BEGIN
    RETURN RAWTOHEX(UC_CRYPTO.RANDOMBYTES(32));
  END GENERATE_TOKEN;

  FUNCTION VALIDATE_PASSWORD_POLICY (p_password IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF LENGTH(p_password) < 8                       THEN RETURN 'Password must be at least 8 characters.'; END IF;
    IF NOT REGEXP_LIKE(p_password, '[A-Z]')          THEN RETURN 'Password must contain at least one uppercase letter.'; END IF;
    IF NOT REGEXP_LIKE(p_password, '[a-z]')          THEN RETURN 'Password must contain at least one lowercase letter.'; END IF;
    IF NOT REGEXP_LIKE(p_password, '[0-9]')          THEN RETURN 'Password must contain at least one digit.'; END IF;
    IF NOT REGEXP_LIKE(p_password, '[^A-Za-z0-9]')  THEN RETURN 'Password must contain at least one special character.'; END IF;
    RETURN NULL;
  END VALIDATE_PASSWORD_POLICY;

  -- Increment failed login count (autonomous)
  PROCEDURE P_INCREMENT_FAILED (p_user_id IN NUMBER) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    UPDATE EPF_USERS
       SET FAILED_LOGIN_COUNT = NVL(FAILED_LOGIN_COUNT, 0) + 1,
           UPDATED_DATE       = SYSDATE
     WHERE USER_ID = p_user_id;
    COMMIT;
  EXCEPTION WHEN OTHERS THEN ROLLBACK;
  END P_INCREMENT_FAILED;

  -- Lock account after max failed attempts (autonomous)
  PROCEDURE P_LOCK_ACCOUNT (p_user_id IN NUMBER, p_reason IN VARCHAR2 DEFAULT 'Too many failed login attempts') IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_email EPF_USERS.EMAIL%TYPE;
  BEGIN
    UPDATE EPF_USERS
       SET FAILED_LOGIN_COUNT = 0,
           ACCOUNT_LOCKED     = 'Y',
           STATUS_ID          = EPF_STATUS_PKG.GET_ID('USER_STATUS', 'BLOCKED'),
           UPDATED_DATE       = SYSDATE
     WHERE USER_ID = p_user_id
    RETURNING EMAIL INTO l_email;

    INSERT INTO EPF_USER_ACCOUNT_LOCKS (USER_ID, LOCK_BY, LOCK_DATE, LOCK_REASON)
    VALUES (p_user_id, 'SYSTEM', SYSDATE, p_reason);
    COMMIT;

    -- Best-effort lockout notification
    BEGIN
      DECLARE v_id NUMBER;
      BEGIN
        v_id := APEX_MAIL.SEND(
          p_to        => l_email,
          p_from      => FROM_EMAIL,
          p_subj      => 'EPF Portal – Account Locked',
          p_body      => 'Your EPF Portal account has been locked. Contact your administrator.',
          p_body_html => '<p>Your <strong>EPF Portal</strong> account has been <strong>locked</strong>.</p>'
                      || '<p>Please contact your administrator to unlock.</p>'
        );
        APEX_MAIL.PUSH_QUEUE;
      END;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  EXCEPTION WHEN OTHERS THEN ROLLBACK;
  END P_LOCK_ACCOUNT;

  -- Session log (autonomous)
  PROCEDURE P_SESSION_LOG (
    p_user_id         IN NUMBER,
    p_username        IN VARCHAR2,
    p_is_success      IN CHAR,
    p_login_status_id IN NUMBER,
    p_failure_reason  IN VARCHAR2,
    p_message         IN VARCHAR2
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO EPF_USER_SESSION_LOG (
      USER_ID, USERNAME, IP_ADDRESS, USER_AGENT,
      IS_SUCCESS, LOGIN_STATUS_ID, FAILURE_REASON, MESSAGE
    ) VALUES (
      p_user_id, p_username,
      OWA_UTIL.GET_CGI_ENV('REMOTE_ADDR'),
      OWA_UTIL.GET_CGI_ENV('HTTP_USER_AGENT'),
      p_is_success, p_login_status_id, p_failure_reason, p_message
    );
    COMMIT;
  EXCEPTION WHEN OTHERS THEN ROLLBACK;
  END P_SESSION_LOG;

  -- ═══════════════════════════════════════════════════════════
  --  LOG_ACTIVITY  (public, autonomous)
  --  Inserts into EPF_ACTIVITY_LOGS (user/session audit log)
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE LOG_ACTIVITY (
    p_user_id         IN NUMBER,
    p_company_id      IN NUMBER   DEFAULT NULL,
    p_user_company_id IN NUMBER   DEFAULT NULL,
    p_action_code     IN VARCHAR2,
    p_action_detail   IN VARCHAR2,
    p_page_name       IN VARCHAR2 DEFAULT NULL
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO EPF_ACTIVITY_LOGS (
      COMPANY_ID, USER_ID, USER_COMPANY_ID,
      ACTION_CODE, ACTION_DETAIL, ACTION_DATE,
      PAGE_NAME
    ) VALUES (
      p_company_id, p_user_id, p_user_company_id,
      p_action_code, p_action_detail, SYSDATE,
      p_page_name
    );
    COMMIT;
  EXCEPTION WHEN OTHERS THEN ROLLBACK;
  END LOG_ACTIVITY;

  -- ═══════════════════════════════════════════════════════════
  --  APPLY_NEW_PASSWORD  (public – called from APEX after OTP)
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE APPLY_NEW_PASSWORD (p_user_id IN NUMBER, p_new_pwd IN VARCHAR2) IS
    v_salt VARCHAR2(500);
    v_hash VARCHAR2(500);
  BEGIN
    v_salt := GENERATE_SALT();
    v_hash := HASH_PASSWORD(p_new_pwd, v_salt);
    UPDATE EPF_USERS
       SET PASSWORD_HASH       = v_hash,
           PASSWORD_SALT       = v_salt,
           FORCE_PWD_CHANGE    = 'N',
           FIRST_LOGIN         = 'N',
           PASSWORD_CHANGED_DT = SYSTIMESTAMP,
           FAILED_LOGIN_COUNT  = 0,
           UPDATED_DATE        = SYSDATE
     WHERE USER_ID = p_user_id;
    COMMIT;
  END APPLY_NEW_PASSWORD;

  -- ═══════════════════════════════════════════════════════════
  --  APEX_AUTHENTICATE
  --  Wire to: APEX > Auth Scheme > Authentication Function Name
  -- ═══════════════════════════════════════════════════════════
  FUNCTION APEX_AUTHENTICATE (
    p_username IN VARCHAR2,
    p_password IN VARCHAR2
  ) RETURN BOOLEAN IS
    l_user_id      EPF_USERS.USER_ID%TYPE;
    l_salt         EPF_USERS.PASSWORD_SALT%TYPE;
    l_real_hash    EPF_USERS.PASSWORD_HASH%TYPE;
    l_calc_hash    VARCHAR2(4000);
    l_failed       EPF_USERS.FAILED_LOGIN_COUNT%TYPE;
    l_is_active    EPF_USERS.IS_ACTIVE%TYPE;
    l_locked       EPF_USERS.ACCOUNT_LOCKED%TYPE;
    l_status_id    EPF_USERS.STATUS_ID%TYPE;
    l_full_name    EPF_USERS.FULL_NAME%TYPE;
    l_force_pwd    EPF_USERS.FORCE_PWD_CHANGE%TYPE;
    v_blocked_sid  NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'BLOCKED');
    v_inactive_sid NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'INACTIVE');
    v_active_sid   NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'ACTIVE');
  BEGIN
    BEGIN
      SELECT USER_ID, PASSWORD_SALT, PASSWORD_HASH,
             FAILED_LOGIN_COUNT, IS_ACTIVE, ACCOUNT_LOCKED,
             STATUS_ID, FULL_NAME, FORCE_PWD_CHANGE
        INTO l_user_id, l_salt, l_real_hash,
             l_failed, l_is_active, l_locked,
             l_status_id, l_full_name, l_force_pwd
        FROM EPF_USERS
       WHERE LOWER(TRIM(EMAIL)) = LOWER(TRIM(p_username));
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        P_SESSION_LOG(NULL, p_username, 'N', NULL, 'USER_NOT_FOUND', 'Login failed: user not found');
        RETURN FALSE;
    END;

    IF l_locked = 'Y' OR l_status_id = v_blocked_sid THEN
      P_SESSION_LOG(l_user_id, p_username, 'N', v_blocked_sid, 'ACCOUNT_LOCKED',
                    'Login blocked: account is locked');
      RETURN FALSE;
    END IF;

    IF l_is_active = 'N' OR l_status_id = v_inactive_sid THEN
      P_SESSION_LOG(l_user_id, p_username, 'N', v_inactive_sid, 'ACCOUNT_INACTIVE',
                    'Login blocked: account is inactive');
      RETURN FALSE;
    END IF;

    l_calc_hash := HASH_PASSWORD(p_password, l_salt);
    IF UPPER(l_calc_hash) != UPPER(NVL(l_real_hash, '__INVALID__')) THEN
      IF NVL(l_failed, 0) + 1 >= MAX_FAILED_ATTEMPTS THEN
        P_LOCK_ACCOUNT(l_user_id, 'Too many failed login attempts');
        P_SESSION_LOG(l_user_id, p_username, 'N', v_blocked_sid, 'MAX_FAILED_ATTEMPTS',
                      'Account locked after ' || MAX_FAILED_ATTEMPTS || ' failed attempts');
      ELSE
        P_INCREMENT_FAILED(l_user_id);
        P_SESSION_LOG(l_user_id, p_username, 'N', NULL, 'BAD_PASSWORD',
                      'Login failed: incorrect password. Attempt ' || (NVL(l_failed, 0) + 1));
      END IF;
      RETURN FALSE;
    END IF;

    -- Success
    UPDATE EPF_USERS
       SET FAILED_LOGIN_COUNT = 0,
           LAST_LOGIN_DATE    = SYSTIMESTAMP,
           UPDATED_DATE       = SYSDATE
     WHERE USER_ID = l_user_id;
    COMMIT;

    P_SESSION_LOG(l_user_id, p_username, 'Y', v_active_sid, NULL,
                  'Login successful: ' || l_full_name);

    LOG_ACTIVITY(l_user_id, NULL, NULL, 'LOGIN_SUCCESS',
                 'Successful login on ' || TO_CHAR(SYSDATE, 'DD-Mon-YY HH:MI am'), 'Login');

    APEX_UTIL.SET_SESSION_STATE('APP_USER_ID',        l_user_id);
    APEX_UTIL.SET_SESSION_STATE('APP_ITEM_FORCE_PWD', l_force_pwd);
    APEX_UTIL.SET_SESSION_STATE('APP_FULL_NAME',      l_full_name);

    RETURN TRUE;

  EXCEPTION
    WHEN OTHERS THEN
      P_SESSION_LOG(NULL, p_username, 'N', NULL, 'EXCEPTION', SQLERRM);
      RETURN FALSE;
  END APEX_AUTHENTICATE;

  -- ═══════════════════════════════════════════════════════════
  --  POST_AUTH_SETUP
  --  Wire to: APEX > Auth Scheme > Post-Authentication Process
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE POST_AUTH_SETUP IS
    l_user_id   NUMBER  := TO_NUMBER(NVL(APEX_UTIL.GET_SESSION_STATE('APP_USER_ID'), '0'));
    l_force_pwd VARCHAR2(1) := APEX_UTIL.GET_SESSION_STATE('APP_ITEM_FORCE_PWD');
    l_comp_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_comp_count
      FROM EPF_USER_COMPANIES uc
      JOIN EPF_COMPANIES      c  ON c.COMPANY_ID = uc.COMPANY_ID
     WHERE uc.USER_ID   = l_user_id
       AND uc.STATUS_ID = EPF_STATUS_PKG.GET_ID('USER_STATUS',   'ACTIVE')
       AND c.STATUS_ID  = EPF_STATUS_PKG.GET_ID('CLIENT_STATUS', 'ACTIVE');

    APEX_UTIL.SET_SESSION_STATE('APP_ITEM_COMP_COUNT', l_comp_count);

    IF l_force_pwd = 'Y' THEN
      APEX_UTIL.SET_SESSION_STATE('APP_ITEM_REDIRECT_REASON', 'FORCE_PWD');
    END IF;
  END POST_AUTH_SETUP;

  -- ═══════════════════════════════════════════════════════════
  --  FORGOT_PASSWORD
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE FORGOT_PASSWORD (
    p_email       IN  VARCHAR2,
    p_ip          IN  VARCHAR2 DEFAULT NULL,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  ) IS
    v_user_id NUMBER;
    v_locked  VARCHAR2(1);
    v_status  VARCHAR2(50);
    v_token   VARCHAR2(200);
  BEGIN
    p_out_success := 'Y';
    p_out_message := 'If an account exists for this email, a reset link has been sent. Link expires in '
                  || PWD_LINK_EXPIRY_HRS || ' hours.';

    BEGIN
      SELECT u.USER_ID, u.ACCOUNT_LOCKED,
             EPF_STATUS_PKG.GET_CODE(u.STATUS_ID)
        INTO v_user_id, v_locked, v_status
        FROM EPF_USERS u
       WHERE LOWER(TRIM(u.EMAIL)) = LOWER(TRIM(p_email))
         AND ROWNUM = 1;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN;
    END;

    IF v_status != 'ACTIVE' OR v_locked = 'Y' THEN RETURN; END IF;

    -- Expire previous tokens
    UPDATE EPF_PASSWORD_TOKENS
       SET USED_YN = 'Y'
     WHERE USER_ID = v_user_id AND PURPOSE = 'RESET_PASSWORD' AND USED_YN = 'N';
    COMMIT;

    v_token := GENERATE_TOKEN();

    INSERT INTO EPF_PASSWORD_TOKENS (USER_ID, TOKEN, PURPOSE, EXPIRES_AT, IP_ADDRESS)
    VALUES (v_user_id, v_token, 'RESET_PASSWORD', SYSDATE + (PWD_LINK_EXPIRY_HRS / 24), p_ip);
    COMMIT;

    EPF_EMAIL_PKG.SEND_FORGOT_PWD_EMAIL(v_user_id, v_token);

    LOG_ACTIVITY(v_user_id, NULL, NULL, 'FORGOT_PWD_REQUEST',
                 'Forgot password requested on ' || TO_CHAR(SYSDATE, 'DD-Mon-YY HH:MI am'),
                 'Forgot Password');

  EXCEPTION WHEN OTHERS THEN NULL;
  END FORGOT_PASSWORD;

  -- ═══════════════════════════════════════════════════════════
  --  VALIDATE_RESET_TOKEN  — returns user_id or 0
  -- ═══════════════════════════════════════════════════════════
  FUNCTION VALIDATE_RESET_TOKEN (p_token IN VARCHAR2) RETURN NUMBER IS
    v_user_id NUMBER;
    v_expires DATE;
    v_used    VARCHAR2(1);
  BEGIN
    SELECT USER_ID, EXPIRES_AT, USED_YN
      INTO v_user_id, v_expires, v_used
      FROM EPF_PASSWORD_TOKENS
     WHERE TOKEN = p_token;

    IF v_used = 'Y' THEN RETURN 0; END IF;
    IF v_expires IS NOT NULL AND v_expires < SYSDATE THEN RETURN 0; END IF;
    RETURN v_user_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
  END VALIDATE_RESET_TOKEN;

  -- ═══════════════════════════════════════════════════════════
  --  SET_NEW_PASSWORD_REQUEST  (Forgot-pwd Step 1)
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE SET_NEW_PASSWORD_REQUEST (
    p_user_id      IN  NUMBER,
    p_new_password IN  VARCHAR2,
    p_confirm_pwd  IN  VARCHAR2,
    p_out_success  OUT VARCHAR2,
    p_out_message  OUT VARCHAR2,
    p_out_otp_sent OUT VARCHAR2
  ) IS
    v_otp VARCHAR2(10);
    v_err VARCHAR2(500);
  BEGIN
    p_out_success  := 'N';
    p_out_otp_sent := 'N';

    IF p_new_password != p_confirm_pwd THEN
      p_out_message := 'New Password and Confirm Password fields do not match.';
      RETURN;
    END IF;

    v_err := VALIDATE_PASSWORD_POLICY(p_new_password);
    IF v_err IS NOT NULL THEN
      p_out_message := v_err;
      RETURN;
    END IF;

    v_otp := GENERATE_OTP();

    UPDATE EPF_OTP_REQUESTS
       SET USED_YN = 'Y'
     WHERE USER_ID = p_user_id AND PURPOSE = 'FORGOT_PWD' AND USED_YN = 'N';
    COMMIT;

    INSERT INTO EPF_OTP_REQUESTS (USER_ID, OTP_CODE, PURPOSE, EXPIRES_AT, USED_YN, ATTEMPT_COUNT, RESEND_COUNT)
    VALUES (p_user_id, v_otp, 'FORGOT_PWD', SYSDATE + (OTP_EXPIRY_MINS / 1440), 'N', 0, 0);
    COMMIT;

    EPF_EMAIL_PKG.SEND_OTP_EMAIL(p_user_id, v_otp, 'FORGOT_PWD');

    p_out_success  := 'Y';
    p_out_otp_sent := 'Y';
    p_out_message  := 'OTP sent to your registered email. Valid for ' || OTP_EXPIRY_MINS || ' minutes.';
  END SET_NEW_PASSWORD_REQUEST;

  -- ═══════════════════════════════════════════════════════════
  --  CONFIRM_OTP_AND_SET_PASSWORD  (Forgot-pwd Step 2)
  --  After success, caller must call APPLY_NEW_PASSWORD.
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE CONFIRM_OTP_AND_SET_PASSWORD (
    p_user_id     IN  NUMBER,
    p_otp         IN  VARCHAR2,
    p_token       IN  VARCHAR2,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  ) IS
    v_otp_rec EPF_OTP_REQUESTS%ROWTYPE;
  BEGIN
    p_out_success := 'N';

    BEGIN
      SELECT * INTO v_otp_rec
        FROM EPF_OTP_REQUESTS
       WHERE USER_ID = p_user_id AND PURPOSE = 'FORGOT_PWD' AND USED_YN = 'N'
         AND ROWNUM = 1
       ORDER BY CREATED_DATE DESC;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        p_out_message := 'Invalid OTP.';
        RETURN;
    END;

    IF v_otp_rec.EXPIRES_AT < SYSDATE THEN
      p_out_message := 'OTP has expired. Please request a new one.';
      RETURN;
    END IF;

    IF v_otp_rec.OTP_CODE != p_otp THEN
      UPDATE EPF_OTP_REQUESTS SET ATTEMPT_COUNT = ATTEMPT_COUNT + 1 WHERE OTP_ID = v_otp_rec.OTP_ID;
      COMMIT;
      IF v_otp_rec.ATTEMPT_COUNT + 1 >= MAX_FAILED_ATTEMPTS THEN
        P_LOCK_ACCOUNT(p_user_id, '5 incorrect OTP submissions for password reset');
      END IF;
      p_out_message := 'Invalid OTP.';
      RETURN;
    END IF;

    UPDATE EPF_OTP_REQUESTS      SET USED_YN = 'Y' WHERE OTP_ID = v_otp_rec.OTP_ID;
    UPDATE EPF_PASSWORD_TOKENS   SET USED_YN = 'Y' WHERE TOKEN  = p_token;
    UPDATE EPF_USERS
       SET ACCOUNT_LOCKED = 'N', FAILED_LOGIN_COUNT = 0
     WHERE USER_ID = p_user_id;
    COMMIT;

    LOG_ACTIVITY(p_user_id, NULL, NULL, 'PWD_RESET_CONFIRMED',
                 'Password reset completed on ' || TO_CHAR(SYSDATE, 'DD-Mon-YY HH:MI am'),
                 'Reset Password');

    EPF_EMAIL_PKG.SEND_PWD_CHANGED_EMAIL(p_user_id);

    p_out_success := 'Y';
    p_out_message := 'OTP verified. Password has been updated.';
  END CONFIRM_OTP_AND_SET_PASSWORD;

  -- ═══════════════════════════════════════════════════════════
  --  CHANGE_PASSWORD  (Profile Step 1)
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE CHANGE_PASSWORD (
    p_user_id      IN  NUMBER,
    p_current_pwd  IN  VARCHAR2,
    p_new_password IN  VARCHAR2,
    p_confirm_pwd  IN  VARCHAR2,
    p_out_success  OUT VARCHAR2,
    p_out_message  OUT VARCHAR2,
    p_out_otp_sent OUT VARCHAR2
  ) IS
    v_user EPF_USERS%ROWTYPE;
    v_hash VARCHAR2(500);
    v_otp  VARCHAR2(10);
    v_err  VARCHAR2(500);
  BEGIN
    p_out_success  := 'N';
    p_out_otp_sent := 'N';

    SELECT * INTO v_user FROM EPF_USERS WHERE USER_ID = p_user_id;

    v_hash := HASH_PASSWORD(p_current_pwd, v_user.PASSWORD_SALT);
    IF UPPER(v_hash) != UPPER(NVL(v_user.PASSWORD_HASH, 'X')) THEN
      p_out_message := 'Current password is incorrect.';
      RETURN;
    END IF;

    IF p_new_password != p_confirm_pwd THEN
      p_out_message := 'New Password and Confirm Password fields do not match.';
      RETURN;
    END IF;

    v_err := VALIDATE_PASSWORD_POLICY(p_new_password);
    IF v_err IS NOT NULL THEN
      p_out_message := v_err;
      RETURN;
    END IF;

    v_otp := GENERATE_OTP();

    UPDATE EPF_OTP_REQUESTS
       SET USED_YN = 'Y'
     WHERE USER_ID = p_user_id AND PURPOSE = 'PWD_CHANGE' AND USED_YN = 'N';
    COMMIT;

    INSERT INTO EPF_OTP_REQUESTS (USER_ID, OTP_CODE, PURPOSE, EXPIRES_AT, USED_YN, ATTEMPT_COUNT, RESEND_COUNT)
    VALUES (p_user_id, v_otp, 'PWD_CHANGE', SYSDATE + (OTP_EXPIRY_MINS / 1440), 'N', 0, 0);
    COMMIT;

    EPF_EMAIL_PKG.SEND_OTP_EMAIL(p_user_id, v_otp, 'PWD_CHANGE');

    p_out_success  := 'Y';
    p_out_otp_sent := 'Y';
    p_out_message  := 'An OTP has been sent to your registered email. Valid for ' || OTP_EXPIRY_MINS || ' minutes.';
  END CHANGE_PASSWORD;

  -- ═══════════════════════════════════════════════════════════
  --  CONFIRM_OTP_CHANGE_PASSWORD  (Profile Step 2)
  --  After success, caller must call APPLY_NEW_PASSWORD.
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE CONFIRM_OTP_CHANGE_PASSWORD (
    p_user_id     IN  NUMBER,
    p_otp         IN  VARCHAR2,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  ) IS
    v_otp_rec EPF_OTP_REQUESTS%ROWTYPE;
  BEGIN
    p_out_success := 'N';

    BEGIN
      SELECT * INTO v_otp_rec
        FROM EPF_OTP_REQUESTS
       WHERE USER_ID = p_user_id AND PURPOSE = 'PWD_CHANGE' AND USED_YN = 'N'
         AND ROWNUM = 1
       ORDER BY CREATED_DATE DESC;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        p_out_message := 'Invalid OTP.';
        RETURN;
    END;

    IF v_otp_rec.EXPIRES_AT < SYSDATE THEN
      p_out_message := 'OTP has expired. Please try again.';
      RETURN;
    END IF;

    IF v_otp_rec.OTP_CODE != p_otp THEN
      UPDATE EPF_OTP_REQUESTS SET ATTEMPT_COUNT = ATTEMPT_COUNT + 1 WHERE OTP_ID = v_otp_rec.OTP_ID;
      COMMIT;
      IF v_otp_rec.ATTEMPT_COUNT + 1 >= MAX_FAILED_ATTEMPTS THEN
        P_LOCK_ACCOUNT(p_user_id, '5 incorrect OTP submissions for password change');
      END IF;
      p_out_message := 'Invalid OTP.';
      RETURN;
    END IF;

    UPDATE EPF_OTP_REQUESTS SET USED_YN = 'Y' WHERE OTP_ID = v_otp_rec.OTP_ID;
    COMMIT;

    LOG_ACTIVITY(p_user_id, NULL, NULL, 'PWD_CHANGED',
                 'Password changed on ' || TO_CHAR(SYSDATE, 'DD-Mon-YY HH:MI am'),
                 'Change Password');

    EPF_EMAIL_PKG.SEND_PWD_CHANGED_EMAIL(p_user_id);

    p_out_success := 'Y';
    p_out_message := 'OTP verified. Password has been updated.';
  END CONFIRM_OTP_CHANGE_PASSWORD;

  -- ═══════════════════════════════════════════════════════════
  --  RESEND_OTP
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE RESEND_OTP (
    p_user_id     IN  NUMBER,
    p_purpose     IN  VARCHAR2,
    p_out_success OUT VARCHAR2,
    p_out_message OUT VARCHAR2
  ) IS
    v_otp_rec EPF_OTP_REQUESTS%ROWTYPE;
    v_new_otp VARCHAR2(10);
  BEGIN
    p_out_success := 'N';

    BEGIN
      SELECT * INTO v_otp_rec
        FROM EPF_OTP_REQUESTS
       WHERE USER_ID = p_user_id AND PURPOSE = p_purpose AND USED_YN = 'N'
         AND ROWNUM = 1
       ORDER BY CREATED_DATE DESC;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        p_out_message := 'No active OTP session found. Please restart the process.';
        RETURN;
    END;

    IF v_otp_rec.RESEND_COUNT >= MAX_OTP_RESENDS THEN
      P_LOCK_ACCOUNT(p_user_id, 'Exceeded maximum OTP resend attempts');
      p_out_message := 'Too many resend attempts. Your account has been blocked. '
                    || 'Please contact your Administrator.';
      RETURN;
    END IF;

    v_new_otp := GENERATE_OTP();

    UPDATE EPF_OTP_REQUESTS
       SET OTP_CODE      = v_new_otp,
           EXPIRES_AT    = SYSDATE + (OTP_EXPIRY_MINS / 1440),
           RESEND_COUNT  = RESEND_COUNT + 1,
           ATTEMPT_COUNT = 0
     WHERE OTP_ID = v_otp_rec.OTP_ID;
    COMMIT;

    EPF_EMAIL_PKG.SEND_OTP_EMAIL(p_user_id, v_new_otp, p_purpose);

    p_out_success := 'Y';
    p_out_message := 'A new OTP has been sent to your registered email. You have '
                  || TO_CHAR(MAX_OTP_RESENDS - v_otp_rec.RESEND_COUNT - 1)
                  || ' resend(s) remaining.';
  END RESEND_OTP;

  -- ═══════════════════════════════════════════════════════════
  --  SET_FIRST_PASSWORD_TOKEN
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE SET_FIRST_PASSWORD_TOKEN (
    p_user_id IN NUMBER,
    p_ip      IN VARCHAR2 DEFAULT NULL
  ) IS
    v_token VARCHAR2(200);
  BEGIN
    UPDATE EPF_PASSWORD_TOKENS
       SET USED_YN = 'Y'
     WHERE USER_ID = p_user_id AND PURPOSE = 'SET_PASSWORD' AND USED_YN = 'N';
    COMMIT;

    v_token := GENERATE_TOKEN();

    INSERT INTO EPF_PASSWORD_TOKENS (USER_ID, TOKEN, PURPOSE, EXPIRES_AT, IP_ADDRESS)
    VALUES (p_user_id, v_token, 'SET_PASSWORD', NULL, p_ip);
    COMMIT;

    EPF_EMAIL_PKG.SEND_WELCOME_EMAIL(p_user_id, v_token);
  END SET_FIRST_PASSWORD_TOKEN;

  -- ═══════════════════════════════════════════════════════════
  --  ADMIN_BLOCK_USER
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE ADMIN_BLOCK_USER (p_email IN VARCHAR2, p_admin IN VARCHAR2, p_reason IN VARCHAR2) IS
    l_userid NUMBER := EPF_UTIL.GET_USER_ID(p_email);
  BEGIN
    IF l_userid IS NULL THEN
      RAISE_APPLICATION_ERROR(-20040, 'User not found: ' || p_email);
    END IF;

    UPDATE EPF_USERS
       SET ACCOUNT_LOCKED = 'Y',
           STATUS_ID      = EPF_STATUS_PKG.GET_ID('USER_STATUS', 'BLOCKED'),
           UPDATED_DATE   = SYSDATE
     WHERE USER_ID = l_userid;

    INSERT INTO EPF_USER_ACCOUNT_LOCKS (USER_ID, LOCK_BY, LOCK_DATE, LOCK_REASON)
    VALUES (l_userid, p_admin, SYSDATE, p_reason);
    COMMIT;

    LOG_ACTIVITY(l_userid, NULL, NULL, 'ADMIN_BLOCKED',
                 'Account blocked by ' || p_admin || '. Reason: ' || p_reason, 'Admin');
  END ADMIN_BLOCK_USER;

  -- ═══════════════════════════════════════════════════════════
  --  ADMIN_UNBLOCK_USER
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE ADMIN_UNBLOCK_USER (p_email IN VARCHAR2, p_admin IN VARCHAR2) IS
    l_userid NUMBER := EPF_UTIL.GET_USER_ID(p_email);
  BEGIN
    IF l_userid IS NULL THEN
      RAISE_APPLICATION_ERROR(-20041, 'User not found: ' || p_email);
    END IF;

    UPDATE EPF_USER_ACCOUNT_LOCKS
       SET UNLOCK_DATE = SYSDATE
     WHERE USER_ID = l_userid AND UNLOCK_DATE IS NULL;

    UPDATE EPF_USERS
       SET ACCOUNT_LOCKED     = 'N',
           STATUS_ID          = EPF_STATUS_PKG.GET_ID('USER_STATUS', 'ACTIVE'),
           FAILED_LOGIN_COUNT = 0,
           FORCE_PWD_CHANGE   = 'Y',
           UPDATED_DATE       = SYSDATE
     WHERE USER_ID = l_userid;
    COMMIT;

    LOG_ACTIVITY(l_userid, NULL, NULL, 'ADMIN_UNBLOCKED',
                 'Account unblocked by ' || p_admin, 'Admin');
  END ADMIN_UNBLOCK_USER;

  -- ═══════════════════════════════════════════════════════════
  --  FORCE_PASSWORD_CHANGE
  -- ═══════════════════════════════════════════════════════════
  PROCEDURE FORCE_PASSWORD_CHANGE (p_user_id IN NUMBER) IS
  BEGIN
    UPDATE EPF_USERS
       SET FORCE_PWD_CHANGE = 'Y',
           UPDATED_DATE     = SYSDATE
     WHERE USER_ID = p_user_id;
    COMMIT;
  END FORCE_PASSWORD_CHANGE;

END EPF_PKG_AUTH;
/

-- ============================================================
-- End of 19_epf_pkg_auth.sql
-- ============================================================
