-- ============================================================
-- FILE: /home/user/EPF/db/10_epf_corp_admin_pkg.sql
-- EPF PORTAL  –  Corporate Admin Package (Spec + Body)
-- Manages CORP_MAKER / CORP_CHECKER lifecycle for a company.
-- Depends on: 07_corp_admin_ddl.sql, 08_epf_email_pkg.sql,
--             09_epf_auth_pkg.sql, EPF_STATUS_PKG
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_CORP_ADMIN_PKG AS
-- ============================================================
--  EPF_CORP_ADMIN_PKG  –  Corporate Admin User Management
-- ============================================================

    -- ── Create a new Maker or Checker user ────────────────────
    PROCEDURE CREATE_USER (
        p_company_id       IN  NUMBER,
        p_created_by_ucid  IN  NUMBER,          -- APP_USER_COMPANY_ID of the Admin
        p_role_code        IN  VARCHAR2,         -- 'CORP_MAKER' | 'CORP_CHECKER'
        p_full_name        IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_mobile_no        IN  VARCHAR2,
        p_employee_code    IN  VARCHAR2,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_user_id      OUT NUMBER
    );

    -- ── Update an existing Maker or Checker ───────────────────
    PROCEDURE UPDATE_USER (
        p_user_company_id  IN  NUMBER,
        p_updated_by_ucid  IN  NUMBER,
        p_role_code        IN  VARCHAR2,
        p_full_name        IN  VARCHAR2,
        p_mobile_no        IN  VARCHAR2,
        p_employee_code    IN  VARCHAR2,
        p_new_status_code  IN  VARCHAR2,         -- 'ACTIVE' | 'INACTIVE'
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2
    );

    -- ── Bulk-delete users (colon-separated UCIDs) ─────────────
    PROCEDURE DELETE_USERS (
        p_user_company_ids IN  VARCHAR2,         -- e.g. '12:45:78'
        p_deleted_by_ucid  IN  NUMBER,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_count        OUT NUMBER
    );

    -- ── Activity history for a specific user-company ──────────
    FUNCTION GET_USER_HISTORY (
        p_user_company_id IN NUMBER
    ) RETURN SYS_REFCURSOR;

END EPF_CORP_ADMIN_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_CORP_ADMIN_PKG AS
-- ============================================================
--  EPF_CORP_ADMIN_PKG  –  Body
-- ============================================================

    -- ============================================================
    --  PRIVATE HELPERS
    -- ============================================================

    -- ─────────────────────────────────────────────────────────────
    --  GET_ADMIN_NAME
    --  Returns FULL_NAME of the user owning a USER_COMPANY_ID.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_ADMIN_NAME (
        p_user_company_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name EPF_USERS.FULL_NAME%TYPE;
    BEGIN
        SELECT u.FULL_NAME
          INTO v_name
          FROM EPF_USERS u
          JOIN EPF_USER_COMPANIES uc ON uc.USER_ID = u.USER_ID
         WHERE uc.USER_COMPANY_ID = p_user_company_id;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'Admin';
    END GET_ADMIN_NAME;

    -- ─────────────────────────────────────────────────────────────
    --  GET_ROLE_ID
    --  Returns ROLE_ID for a given ROLE_CODE.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_ROLE_ID (
        p_role_code IN VARCHAR2
    ) RETURN NUMBER IS
        v_role_id EPF_ROLES.ROLE_ID%TYPE;
    BEGIN
        SELECT ROLE_ID
          INTO v_role_id
          FROM EPF_ROLES
         WHERE ROLE_CODE = p_role_code;
        RETURN v_role_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_ROLE_ID;

    -- ─────────────────────────────────────────────────────────────
    --  LOG_ACTIVITY
    --  Writes one row to EPF_ACTIVITY_LOGS.  AUTONOMOUS.
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE LOG_ACTIVITY (
        p_user_id         IN NUMBER,
        p_company_id      IN NUMBER   DEFAULT NULL,
        p_user_company_id IN NUMBER   DEFAULT NULL,
        p_action_code     IN VARCHAR2,
        p_action_detail   IN VARCHAR2,
        p_page_name       IN VARCHAR2 DEFAULT 'Corp Admin – User Management'
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_seq   NUMBER;
        v_refno VARCHAR2(30);
    BEGIN
        SELECT ACT_LOG_REF_SEQ.NEXTVAL INTO v_seq FROM DUAL;
        v_refno := 'ACT-' || TO_CHAR(SYSDATE, 'YYYYMM') || '-' || LPAD(v_seq, 6, '0');

        INSERT INTO EPF_ACTIVITY_LOGS (
            COMPANY_ID, USER_ID, USER_COMPANY_ID,
            ACTION_CODE, ACTION_DETAIL, ACTION_DATE,
            PAGE_NAME, REF_NO
        ) VALUES (
            p_company_id, p_user_id, p_user_company_id,
            p_action_code, p_action_detail, SYSDATE,
            p_page_name, v_refno
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END LOG_ACTIVITY;

    -- ─────────────────────────────────────────────────────────────
    --  VALIDATE_NAME
    --  Returns NULL on pass; error message on fail.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION VALIDATE_NAME (
        p_name IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        IF p_name IS NULL OR TRIM(p_name) IS NULL THEN
            RETURN 'Full name is required.';
        END IF;
        IF NOT REGEXP_LIKE(TRIM(p_name), '^[A-Za-z ]+$') THEN
            RETURN 'Full name must contain alphabets and spaces only.';
        END IF;
        RETURN NULL;
    END VALIDATE_NAME;

    -- ─────────────────────────────────────────────────────────────
    --  VALIDATE_EMAIL_FMT
    --  Returns NULL on pass; error message on fail.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION VALIDATE_EMAIL_FMT (
        p_email IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        IF p_email IS NULL OR TRIM(p_email) IS NULL THEN
            RETURN 'Email address is required.';
        END IF;
        IF NOT REGEXP_LIKE(TRIM(p_email),
                '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$') THEN
            RETURN 'Invalid email address format.';
        END IF;
        RETURN NULL;
    END VALIDATE_EMAIL_FMT;

    -- ─────────────────────────────────────────────────────────────
    --  VALIDATE_MOBILE_FMT
    -- ─────────────────────────────────────────────────────────────
    FUNCTION VALIDATE_MOBILE_FMT (
        p_mobile IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        IF p_mobile IS NULL OR TRIM(p_mobile) IS NULL THEN
            RETURN 'Mobile number is required.';
        END IF;
        IF NOT REGEXP_LIKE(TRIM(p_mobile), '^\+?[0-9]{7,15}$') THEN
            RETURN 'Mobile number must contain digits only (7–15 digits).';
        END IF;
        RETURN NULL;
    END VALIDATE_MOBILE_FMT;

    -- ============================================================
    --  PUBLIC PROCEDURES
    -- ============================================================

    -- ─────────────────────────────────────────────────────────────
    --  CREATE_USER
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE CREATE_USER (
        p_company_id       IN  NUMBER,
        p_created_by_ucid  IN  NUMBER,
        p_role_code        IN  VARCHAR2,
        p_full_name        IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_mobile_no        IN  VARCHAR2,
        p_employee_code    IN  VARCHAR2,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_user_id      OUT NUMBER
    ) IS
        v_role_id        EPF_ROLES.ROLE_ID%TYPE;
        v_exist_user_id  EPF_USERS.USER_ID%TYPE;
        v_exist_ucid     EPF_USER_COMPANIES.USER_COMPANY_ID%TYPE;
        v_exist_role     EPF_ROLES.ROLE_CODE%TYPE;
        v_active_status  NUMBER          := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'ACTIVE');
        v_new_user_id    EPF_USERS.USER_ID%TYPE;
        v_new_ucid       EPF_USER_COMPANIES.USER_COMPANY_ID%TYPE;
        v_admin_name     EPF_USERS.FULL_NAME%TYPE;
        v_err            VARCHAR2(500);
        v_email_clean    VARCHAR2(200)   := LOWER(TRIM(p_email));
        v_name_clean     VARCHAR2(200)   := TRIM(p_full_name);
    BEGIN
        p_out_success := 'N';
        p_out_user_id := NULL;

        -- ── Validate role ──────────────────────────────────────
        IF p_role_code NOT IN ('CORP_MAKER', 'CORP_CHECKER') THEN
            p_out_message := 'Invalid user type. Only Maker and Checker can be created by Admin.';
            RETURN;
        END IF;

        -- ── Validate inputs ────────────────────────────────────
        v_err := VALIDATE_NAME(p_full_name);
        IF v_err IS NOT NULL THEN p_out_message := v_err; RETURN; END IF;

        v_err := VALIDATE_EMAIL_FMT(p_email);
        IF v_err IS NOT NULL THEN p_out_message := v_err; RETURN; END IF;

        v_err := VALIDATE_MOBILE_FMT(p_mobile_no);
        IF v_err IS NOT NULL THEN p_out_message := v_err; RETURN; END IF;

        -- ── Resolve role_id ────────────────────────────────────
        v_role_id := GET_ROLE_ID(p_role_code);
        IF v_role_id IS NULL THEN
            p_out_message := 'Role configuration error. Please contact support.';
            RETURN;
        END IF;

        v_admin_name := GET_ADMIN_NAME(p_created_by_ucid);

        -- ── Check if email already exists globally ─────────────
        BEGIN
            SELECT USER_ID INTO v_exist_user_id
              FROM EPF_USERS
             WHERE LOWER(EMAIL) = v_email_clean;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_exist_user_id := NULL;
        END;

        IF v_exist_user_id IS NOT NULL THEN
            -- Check: is this user already a CORP_MAKER or CORP_CHECKER for THIS company?
            BEGIN
                SELECT uc.USER_COMPANY_ID, r.ROLE_CODE
                  INTO v_exist_ucid, v_exist_role
                  FROM EPF_USER_COMPANIES    uc
                  JOIN EPF_USER_COMP_ROLES   ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
                  JOIN EPF_ROLES             r   ON r.ROLE_ID           = ucr.ROLE_ID
                 WHERE uc.USER_ID       = v_exist_user_id
                   AND uc.COMPANY_ID    = p_company_id
                   AND ucr.IS_ACTIVE    = 'Y'
                   AND r.ROLE_CODE      = p_role_code
                   AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) != 'DELETED'
                   AND ROWNUM = 1;

                -- If we got here: duplicate
                p_out_message := 'This email is already registered as '
                              || INITCAP(REPLACE(p_role_code, 'CORP_', ''))
                              || ' for this company.';
                RETURN;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN NULL;  -- not a duplicate
            END;

            -- Check if user is an Authorizer for this company → add additional role
            DECLARE
                v_auth_ucid NUMBER;
            BEGIN
                SELECT uc.USER_COMPANY_ID
                  INTO v_auth_ucid
                  FROM EPF_USER_COMPANIES    uc
                  JOIN EPF_USER_COMP_ROLES   ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
                  JOIN EPF_ROLES             r   ON r.ROLE_ID           = ucr.ROLE_ID
                 WHERE uc.USER_ID    = v_exist_user_id
                   AND uc.COMPANY_ID = p_company_id
                   AND ucr.IS_ACTIVE = 'Y'
                   AND r.ROLE_CODE   = 'CORP_AUTHORIZER'
                   AND ROWNUM        = 1;

                -- Authorizer exists → add new role to existing USER_COMPANY_ID
                INSERT INTO EPF_USER_COMP_ROLES (
                    USER_COMPANY_ID, ROLE_ID, IS_ACTIVE
                ) VALUES (
                    v_auth_ucid, v_role_id, 'Y'
                );
                COMMIT;

                p_out_user_id := v_exist_user_id;
                p_out_success := 'Y';
                LOG_ACTIVITY(
                    p_user_id         => v_exist_user_id,
                    p_company_id      => p_company_id,
                    p_user_company_id => v_auth_ucid,
                    p_action_code     => 'USER_ROLE_ADDED',
                    p_action_detail   => 'Role ' || p_role_code || ' added by Admin '
                                      || v_admin_name || ' on '
                                      || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                      || TO_CHAR(SYSDATE, 'HH:MI AM')
                );
                RETURN;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Existing user is not an Authorizer; use same USER_ID
                    -- but create a new user-company or re-activate
                    NULL;
            END;
        END IF;

        -- ── New user: INSERT into EPF_USERS ────────────────────
        IF v_exist_user_id IS NULL THEN
            INSERT INTO EPF_USERS (
                FULL_NAME, EMAIL, MOBILE_NO, DESIGNATION,
                FORCE_PWD_CHANGE, IS_ACTIVE, STATUS_ID,
                ACCOUNT_LOCKED, FAILED_LOGIN_COUNT, MFA_ENABLED
            ) VALUES (
                v_name_clean, v_email_clean, TRIM(p_mobile_no), p_employee_code,
                'Y', 'Y', v_active_status,
                'N', 0, 'N'
            )
            RETURNING USER_ID INTO v_new_user_id;
        ELSE
            v_new_user_id := v_exist_user_id;
        END IF;

        -- ── MERGE into EPF_USER_COMPANIES ──────────────────────
        --    Insert new; if already exists (different role), update.
        BEGIN
            SELECT USER_COMPANY_ID
              INTO v_exist_ucid
              FROM EPF_USER_COMPANIES
             WHERE USER_ID    = v_new_user_id
               AND COMPANY_ID = p_company_id;

            -- Record exists – reactivate and set active status
            UPDATE EPF_USER_COMPANIES
               SET STATUS_ID  = v_active_status,
                   IS_DEFAULT = NVL(IS_DEFAULT, 'Y')
             WHERE USER_COMPANY_ID = v_exist_ucid;

            v_new_ucid := v_exist_ucid;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                INSERT INTO EPF_USER_COMPANIES (
                    USER_ID, COMPANY_ID, STATUS_ID, IS_DEFAULT
                ) VALUES (
                    v_new_user_id, p_company_id, v_active_status, 'Y'
                )
                RETURNING USER_COMPANY_ID INTO v_new_ucid;
        END;

        -- ── Insert role assignment ──────────────────────────────
        INSERT INTO EPF_USER_COMP_ROLES (
            USER_COMPANY_ID, ROLE_ID, IS_ACTIVE
        ) VALUES (
            v_new_ucid, v_role_id, 'Y'
        );

        COMMIT;

        -- ── Send welcome email with set-password link ───────────
        EPF_AUTH_PKG.SET_FIRST_PASSWORD_TOKEN(v_new_user_id, NULL);

        -- ── Activity log ───────────────────────────────────────
        LOG_ACTIVITY(
            p_user_id         => v_new_user_id,
            p_company_id      => p_company_id,
            p_user_company_id => v_new_ucid,
            p_action_code     => 'USER_CREATED',
            p_action_detail   => 'User created by Admin ' || v_admin_name || ' on '
                              || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                              || TO_CHAR(SYSDATE, 'HH:MI AM')
        );

        p_out_success := 'Y';
        p_out_message := 'User has been created successfully.';
        p_out_user_id := v_new_user_id;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'A user with this email address already exists.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END CREATE_USER;

    -- ─────────────────────────────────────────────────────────────
    --  UPDATE_USER
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE UPDATE_USER (
        p_user_company_id  IN  NUMBER,
        p_updated_by_ucid  IN  NUMBER,
        p_role_code        IN  VARCHAR2,
        p_full_name        IN  VARCHAR2,
        p_mobile_no        IN  VARCHAR2,
        p_employee_code    IN  VARCHAR2,
        p_new_status_code  IN  VARCHAR2,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2
    ) IS
        -- Current values
        v_user_id        EPF_USERS.USER_ID%TYPE;
        v_old_name       EPF_USERS.FULL_NAME%TYPE;
        v_old_mobile     EPF_USERS.MOBILE_NO%TYPE;
        v_old_empcode    EPF_USERS.DESIGNATION%TYPE;
        v_old_role_code  EPF_ROLES.ROLE_CODE%TYPE;
        v_old_status_id  EPF_USER_COMPANIES.STATUS_ID%TYPE;
        v_old_status_code VARCHAR2(50);
        v_company_id     EPF_USER_COMPANIES.COMPANY_ID%TYPE;
        -- New values
        v_old_role_id    EPF_ROLES.ROLE_ID%TYPE;
        v_new_role_id    EPF_ROLES.ROLE_ID%TYPE;
        v_new_status_id  NUMBER;
        v_active_sid     NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'ACTIVE');
        v_inactive_sid   NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'INACTIVE');
        v_admin_name     EPF_USERS.FULL_NAME%TYPE;
        v_err            VARCHAR2(500);
        v_name_clean     VARCHAR2(200) := TRIM(p_full_name);
    BEGIN
        p_out_success := 'N';

        -- ── Validate role ──────────────────────────────────────
        IF p_role_code NOT IN ('CORP_MAKER', 'CORP_CHECKER') THEN
            p_out_message := 'Invalid user type. Only Maker and Checker can be managed by Admin.';
            RETURN;
        END IF;

        -- ── Validate inputs ────────────────────────────────────
        v_err := VALIDATE_NAME(p_full_name);
        IF v_err IS NOT NULL THEN p_out_message := v_err; RETURN; END IF;

        v_err := VALIDATE_MOBILE_FMT(p_mobile_no);
        IF v_err IS NOT NULL THEN p_out_message := v_err; RETURN; END IF;

        IF p_new_status_code NOT IN ('ACTIVE', 'INACTIVE') THEN
            p_out_message := 'Invalid status. Must be ACTIVE or INACTIVE.';
            RETURN;
        END IF;

        -- ── Fetch current record ───────────────────────────────
        BEGIN
            SELECT u.USER_ID, u.FULL_NAME, u.MOBILE_NO, u.DESIGNATION,
                   r.ROLE_CODE, uc.STATUS_ID, uc.COMPANY_ID
              INTO v_user_id, v_old_name, v_old_mobile, v_old_empcode,
                   v_old_role_code, v_old_status_id, v_company_id
              FROM EPF_USER_COMPANIES    uc
              JOIN EPF_USERS             u   ON u.USER_ID          = uc.USER_ID
              JOIN EPF_USER_COMP_ROLES   ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
              JOIN EPF_ROLES             r   ON r.ROLE_ID           = ucr.ROLE_ID
             WHERE uc.USER_COMPANY_ID = p_user_company_id
               AND ucr.IS_ACTIVE      = 'Y'
               AND r.ROLE_CODE       IN ('CORP_MAKER', 'CORP_CHECKER');
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'User not found or cannot be edited.';
                RETURN;
            WHEN TOO_MANY_ROWS THEN
                -- User has multiple roles — get primary one
                SELECT u.USER_ID, u.FULL_NAME, u.MOBILE_NO, u.DESIGNATION,
                       r.ROLE_CODE, uc.STATUS_ID, uc.COMPANY_ID
                  INTO v_user_id, v_old_name, v_old_mobile, v_old_empcode,
                       v_old_role_code, v_old_status_id, v_company_id
                  FROM EPF_USER_COMPANIES    uc
                  JOIN EPF_USERS             u   ON u.USER_ID          = uc.USER_ID
                  JOIN EPF_USER_COMP_ROLES   ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
                  JOIN EPF_ROLES             r   ON r.ROLE_ID           = ucr.ROLE_ID
                 WHERE uc.USER_COMPANY_ID = p_user_company_id
                   AND ucr.IS_ACTIVE      = 'Y'
                   AND r.ROLE_CODE       IN ('CORP_MAKER', 'CORP_CHECKER')
                   AND ROWNUM = 1;
        END;

        v_old_status_code := EPF_STATUS_PKG.GET_CODE(v_old_status_id);
        v_old_role_id     := GET_ROLE_ID(v_old_role_code);
        v_new_role_id     := GET_ROLE_ID(p_role_code);
        v_admin_name      := GET_ADMIN_NAME(p_updated_by_ucid);

        IF v_new_role_id IS NULL THEN
            p_out_message := 'Role configuration error.';
            RETURN;
        END IF;

        -- ── Determine new status ID ────────────────────────────
        v_new_status_id := CASE p_new_status_code
                               WHEN 'ACTIVE'   THEN v_active_sid
                               WHEN 'INACTIVE' THEN v_inactive_sid
                               ELSE v_old_status_id
                           END;

        -- ── Apply updates to EPF_USERS ─────────────────────────
        UPDATE EPF_USERS
           SET FULL_NAME   = v_name_clean,
               MOBILE_NO   = TRIM(p_mobile_no),
               DESIGNATION = p_employee_code
         WHERE USER_ID = v_user_id;

        -- ── Update status in EPF_USER_COMPANIES ────────────────
        UPDATE EPF_USER_COMPANIES
           SET STATUS_ID = v_new_status_id
         WHERE USER_COMPANY_ID = p_user_company_id;

        -- ── Update role if changed ─────────────────────────────
        IF p_role_code != v_old_role_code THEN
            UPDATE EPF_USER_COMP_ROLES
               SET IS_ACTIVE = 'N'
             WHERE USER_COMPANY_ID = p_user_company_id
               AND ROLE_ID = v_old_role_id;

            INSERT INTO EPF_USER_COMP_ROLES (
                USER_COMPANY_ID, ROLE_ID, IS_ACTIVE
            ) VALUES (
                p_user_company_id, v_new_role_id, 'Y'
            );
        END IF;

        -- ── Handle unblocking ──────────────────────────────────
        IF p_new_status_code = 'ACTIVE' AND v_old_status_code = 'BLOCKED' THEN
            UPDATE EPF_USERS
               SET ACCOUNT_LOCKED     = 'N',
                   FAILED_LOGIN_COUNT = 0
             WHERE USER_ID = v_user_id;

            EPF_EMAIL_PKG.SEND_UNBLOCK_EMAIL(v_user_id, v_admin_name);

            LOG_ACTIVITY(
                p_user_id         => v_user_id,
                p_company_id      => v_company_id,
                p_user_company_id => p_user_company_id,
                p_action_code     => 'USER_UNBLOCKED',
                p_action_detail   => 'User unblocked by Admin ' || v_admin_name || ' on '
                                  || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                  || TO_CHAR(SYSDATE, 'HH:MI AM')
            );

        -- ── Handle deactivation ────────────────────────────────
        ELSIF p_new_status_code = 'INACTIVE'
          AND v_old_status_code NOT IN ('INACTIVE', 'DELETED')
        THEN
            UPDATE EPF_USER_COMP_ROLES
               SET IS_ACTIVE = 'N'
             WHERE USER_COMPANY_ID = p_user_company_id;

            EPF_EMAIL_PKG.SEND_DEACTIVATE_EMAIL(v_user_id);

            LOG_ACTIVITY(
                p_user_id         => v_user_id,
                p_company_id      => v_company_id,
                p_user_company_id => p_user_company_id,
                p_action_code     => 'USER_DEACTIVATED',
                p_action_detail   => 'User deactivated by Admin ' || v_admin_name || ' on '
                                  || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                  || TO_CHAR(SYSDATE, 'HH:MI AM')
            );

        -- ── Handle reactivation from Inactive ─────────────────
        ELSIF p_new_status_code = 'ACTIVE'
          AND v_old_status_code = 'INACTIVE'
        THEN
            UPDATE EPF_USER_COMP_ROLES
               SET IS_ACTIVE = 'Y'
             WHERE USER_COMPANY_ID = p_user_company_id
               AND ROLE_ID         = v_new_role_id;

            LOG_ACTIVITY(
                p_user_id         => v_user_id,
                p_company_id      => v_company_id,
                p_user_company_id => p_user_company_id,
                p_action_code     => 'USER_REACTIVATED',
                p_action_detail   => 'User reactivated by Admin ' || v_admin_name || ' on '
                                  || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                  || TO_CHAR(SYSDATE, 'HH:MI AM')
            );
        END IF;

        -- ── Field-change narrations ────────────────────────────
        IF v_name_clean != NVL(v_old_name, '~') THEN
            LOG_ACTIVITY(
                p_user_id         => v_user_id,
                p_company_id      => v_company_id,
                p_user_company_id => p_user_company_id,
                p_action_code     => 'USER_NAME_CHANGED',
                p_action_detail   => 'User Name changed from ' || v_old_name
                                  || ' to ' || v_name_clean
                                  || ' by Admin ' || v_admin_name || ' on '
                                  || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                  || TO_CHAR(SYSDATE, 'HH:MI AM')
            );
        END IF;

        IF p_role_code != NVL(v_old_role_code, '~') THEN
            LOG_ACTIVITY(
                p_user_id         => v_user_id,
                p_company_id      => v_company_id,
                p_user_company_id => p_user_company_id,
                p_action_code     => 'USER_TYPE_CHANGED',
                p_action_detail   => 'User Type changed from '
                                  || INITCAP(REPLACE(v_old_role_code,   'CORP_', ''))
                                  || ' to '
                                  || INITCAP(REPLACE(p_role_code, 'CORP_', ''))
                                  || ' by Admin ' || v_admin_name || ' on '
                                  || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                  || TO_CHAR(SYSDATE, 'HH:MI AM')
            );
        END IF;

        COMMIT;

        p_out_success := 'Y';
        p_out_message := 'User details have been updated successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
    END UPDATE_USER;

    -- ─────────────────────────────────────────────────────────────
    --  DELETE_USERS
    --  Soft-deletes a colon-separated list of USER_COMPANY_IDs.
    --  Silently skips Admin/Authorizer and already-deleted records.
    -- ─────────────────────────────────────────────────────────────
    PROCEDURE DELETE_USERS (
        p_user_company_ids IN  VARCHAR2,
        p_deleted_by_ucid  IN  NUMBER,
        p_out_success      OUT VARCHAR2,
        p_out_message      OUT VARCHAR2,
        p_out_count        OUT NUMBER
    ) IS
        v_deleted_sid  NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS', 'DELETED');
        v_admin_name   EPF_USERS.FULL_NAME%TYPE := GET_ADMIN_NAME(p_deleted_by_ucid);
        v_count        NUMBER := 0;
        v_ucid         NUMBER;
        v_ptr          NUMBER := 1;
        v_delim        NUMBER;
        v_ids_work     VARCHAR2(4000) := p_user_company_ids || ':';
        -- Per-record variables
        v_user_id      EPF_USERS.USER_ID%TYPE;
        v_role_code    EPF_ROLES.ROLE_CODE%TYPE;
        v_company_id   EPF_USER_COMPANIES.COMPANY_ID%TYPE;
        v_status_code  VARCHAR2(50);
        v_status_id    EPF_USER_COMPANIES.STATUS_ID%TYPE;
    BEGIN
        p_out_success := 'N';
        p_out_count   := 0;

        IF v_deleted_sid IS NULL THEN
            p_out_message := 'Status configuration error (DELETED status not found).';
            RETURN;
        END IF;

        -- ── Tokenise colon-separated list ──────────────────────
        LOOP
            v_delim := INSTR(v_ids_work, ':', v_ptr);
            EXIT WHEN v_delim = 0;

            DECLARE
                v_token_str VARCHAR2(20) := SUBSTR(v_ids_work, v_ptr, v_delim - v_ptr);
            BEGIN
                v_ptr := v_delim + 1;

                IF TRIM(v_token_str) IS NULL THEN
                    CONTINUE;
                END IF;

                v_ucid := TO_NUMBER(TRIM(v_token_str));

                -- Fetch details; skip if not found
                BEGIN
                    SELECT u.USER_ID, r.ROLE_CODE, uc.COMPANY_ID, uc.STATUS_ID
                      INTO v_user_id, v_role_code, v_company_id, v_status_id
                      FROM EPF_USER_COMPANIES    uc
                      JOIN EPF_USERS             u   ON u.USER_ID          = uc.USER_ID
                      JOIN EPF_USER_COMP_ROLES   ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
                      JOIN EPF_ROLES             r   ON r.ROLE_ID           = ucr.ROLE_ID
                     WHERE uc.USER_COMPANY_ID = v_ucid
                       AND ucr.IS_ACTIVE      = 'Y'
                       AND ROWNUM             = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN CONTINUE;
                END;

                -- Skip Admin/Authorizer silently
                IF v_role_code IN ('CORP_ADMIN', 'CORP_AUTHORIZER') THEN
                    CONTINUE;
                END IF;

                v_status_code := EPF_STATUS_PKG.GET_CODE(v_status_id);

                -- Skip already-deleted
                IF v_status_code = 'DELETED' THEN
                    CONTINUE;
                END IF;

                -- Soft-delete
                UPDATE EPF_USER_COMPANIES
                   SET STATUS_ID = v_deleted_sid
                 WHERE USER_COMPANY_ID = v_ucid;

                UPDATE EPF_USER_COMP_ROLES
                   SET IS_ACTIVE = 'N'
                 WHERE USER_COMPANY_ID = v_ucid;

                LOG_ACTIVITY(
                    p_user_id         => v_user_id,
                    p_company_id      => v_company_id,
                    p_user_company_id => v_ucid,
                    p_action_code     => 'USER_DELETED',
                    p_action_detail   => 'User deleted by Admin ' || v_admin_name || ' on '
                                      || TO_CHAR(SYSDATE, 'DD-Mon-YYYY') || ', '
                                      || TO_CHAR(SYSDATE, 'HH:MI AM')
                );

                v_count := v_count + 1;

            EXCEPTION
                WHEN VALUE_ERROR THEN CONTINUE;   -- non-numeric token
            END;
        END LOOP;

        COMMIT;

        p_out_success := 'Y';
        p_out_count   := v_count;
        p_out_message := v_count || ' user(s) deleted successfully.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'An unexpected error occurred: ' || SQLERRM;
            p_out_count   := 0;
    END DELETE_USERS;

    -- ─────────────────────────────────────────────────────────────
    --  GET_USER_HISTORY
    --  Returns activity log entries for the given user-company,
    --  ordered newest first.
    -- ─────────────────────────────────────────────────────────────
    FUNCTION GET_USER_HISTORY (
        p_user_company_id IN NUMBER
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT
                al.REF_NO,
                TO_CHAR(al.ACTION_DATE, 'DD-Mon-YYYY') AS ACTION_DATE_FMT,
                TO_CHAR(al.ACTION_DATE, 'HH:MI AM')    AS ACTION_TIME_FMT,
                al.ACTION_DATE,
                al.ACTION_CODE,
                al.ACTION_DETAIL
              FROM EPF_ACTIVITY_LOGS al
             WHERE al.USER_COMPANY_ID = p_user_company_id
             ORDER BY al.ACTION_DATE DESC;
        RETURN v_cur;
    END GET_USER_HISTORY;

END EPF_CORP_ADMIN_PKG;
/

-- ============================================================
-- End of 10_epf_corp_admin_pkg.sql
-- ============================================================
