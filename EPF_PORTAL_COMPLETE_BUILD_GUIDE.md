# EPF Portal — Oracle APEX 24.2 Complete Page Build Guide
**Date:** 22-Jun-2026  |  **App:** EPF Portal (App ID: 51534)  |  **DB:** Oracle 19c  |  **APEX:** 24.2.17

---

## Table of Contents

1. [Architecture & Key Objects](#1-architecture--key-objects)
2. [Database Installation Order](#2-database-installation-order)
3. [APEX App Configuration](#3-apex-app-configuration)
4. [Authorization Schemes](#4-authorization-schemes)
5. [Login & Auth Pages (9999, 9901, 9902, 9903)](#5-login--auth-pages)
6. [AAML Maker Pages (10–15)](#6-aaml-maker-pages)
7. [AAML Checker Pages (20–23)](#7-aaml-checker-pages)
8. [AAML Admin & Ops Pages](#8-aaml-admin--ops-pages)
9. [Corp Admin — Page 30](#9-corp-admin--page-30)
10. [Corp Maker Pages (40–45)](#10-corp-maker-pages-40-45)
11. [Corp Checker Pages (50–55, 60)](#11-corp-checker-pages-50-55-60)
12. [Corp Authorizer Pages (70–76)](#12-corp-authorizer-pages-70-76)
13. [Employee Self-Service Pages (80–85)](#13-employee-self-service-pages-80-85)
14. [Shared APEX Components](#14-shared-apex-components)
15. [Status Code Reference](#15-status-code-reference)
16. [Email Reference](#16-email-reference)
17. [FSD Narration Formats](#17-fsd-narration-formats)
18. [Master Implementation Checklist](#18-master-implementation-checklist)

---

## 1. Architecture & Key Objects

### 1.1 Role Codes

| Role Code | Display Name | Portal Section |
|---|---|---|
| `ALFALAH_ADMIN` | AAML Admin | AAML back-office |
| `ALFALAH_MAKER` | AAML Maker | AAML back-office |
| `ALFALAH_CHECKER` | AAML Checker | AAML back-office |
| `ALFALAH_OPS` | AAML Operations | AAML back-office |
| `CORP_ADMIN` | Corporate Admin | Client company |
| `CORP_MAKER` | Corporate Maker | Client company |
| `CORP_CHECKER` | Corporate Checker | Client company |
| `CORP_AUTHORIZER` | Corporate Authorizer | Client company |
| `EMPLOYEE` | Employee | Self-service |

### 1.2 Application Items (set at login by EPF_PKG_AUTH.POST_AUTH_SETUP)

| Item Name | Source | Description |
|---|---|---|
| `APP_USER_ID` | `EPF_USERS.USER_ID` | DB user ID |
| `APP_USER_COMPANY_ID` | `EPF_USER_COMPANIES.USER_COMPANY_ID` | Active company membership |
| `APP_COMPANY_ID` | `EPF_COMPANIES.COMPANY_ID` | Active company |
| `APP_COMPANY_NAME` | `EPF_COMPANIES.COMPANY_NAME` | Display name |
| `APP_COMPANY_CODE` | `EPF_COMPANIES.COMPANY_CODE` | Short code |
| `APP_FULL_NAME` | `EPF_USERS.FULL_NAME` | Display name |
| `APP_ROLE_CODE` | `EPF_ROLES.ROLE_CODE` | Primary role |
| `APP_ITEM_FORCE_PWD` | `EPF_USERS.FORCE_PWD_CHANGE` | `Y` if must change password |
| `APP_ITEM_COMP_COUNT` | Computed | Number of companies assigned |
| `APP_FOLIO_ID` | `EPF_USER_COMPANIES.FOLIO_ID` | Employee folio (EMPLOYEE role only) |
| `APP_ITEM_REDIRECT_REASON` | Set by auth logic | Used for login error messaging |

### 1.3 Key Packages

| Package | Purpose |
|---|---|
| `EPF_PKG_AUTH` | Authentication, OTP, password management, post-auth setup |
| `EPF_STATUS_PKG` | `GET_CODE(id)`, `GET_ID(category, code)` — use everywhere |
| `EPF_UTIL` | Company/user/role lookup helpers, activity logging |
| `EPF_AAML_PKG` | All AAML Maker/Checker business logic |
| `EPF_EMP_SYNC_PKG` | DFN API employee synchronisation |
| `EPF_CORP_ADMIN_PKG` | Corp Admin user management |
| `EPF_CORP_TXN_PKG` | Corp Maker/Checker transaction flows |
| `EPF_AUTHORIZER_PKG` | Multi-authorizer decision workflow |
| `EPF_EMPLOYEE_PKG` | Employee self-service |
| `EPF_EMAIL_PKG` | All email delivery (21 email types) |

### 1.4 Key Views

| View | Used By |
|---|---|
| `EPF_V_USER_COMPANIES` | Auth scheme, post-auth setup, role selector (Page 100) |
| `EPF_V_USER_ROLES` | Authorization schemes |
| `V_EPF_CHANGE_REQUESTS` | AAML Checker CR review |
| `V_EPF_CLIENT_DASHBOARD` | AAML pages 3, 10, 207 |
| `V_EPF_CLIENT_DETAIL` | Client detail page 208/4 |
| `V_EPF_COMPANY_EMPLOYEES` | Employee selection pages |
| `V_EPF_CONTRIBUTION_BATCHES` | Corp Maker page 40, Checker page 50 |
| `V_EPF_LOAN_REQUESTS` | Corp Maker page 41, Checker page 51 |
| `V_EPF_WITHDRAWAL_REQUESTS` | Corp Maker page 42, Checker page 52 |

### 1.5 Workflow Summary

```
                     AAML Maker
                    creates client
                         │
               ┌─────────▼──────────┐
               │  CLIENT_STATUS     │
               │  = DRAFT           │ ← Onboarding wizard (Tabs 1-4)
               └─────────┬──────────┘
                         │ SUBMIT_TO_CHECKER
               ┌─────────▼──────────┐
               │  PENDING_CHECKER   │ ← AAML Checker reviews
               └──┬──────────────┬──┘
          APPROVE  │              │ REJECT / REVERT
               ┌───▼───┐     REJECTED / DRAFT
               │ACTIVE │
               └───────┘

     Corp Maker creates request
              │
    ┌──────── ▼ ─────────┐
    │ PENDING_CHECKER    │ (if Checker exists)
    │ PENDING_AUTHORIZER │ (if no Checker — bypass)
    └───┬─────────────┬──┘
  Checker  │          │ Checker rejects
    ┌──────▼────┐   REJECTED
    │PENDING_   │
    │AUTHORIZER │ ← all Authorizers must approve
    └──────┬────┘
           │ all approve
       AUTHORIZED → AAML Queue → COMPLETED

  Employee creates loan/withdrawal → PENDING_MAKER
  Corp Maker picks up → normal flow above
```

---

## 2. Database Installation Order

Run scripts in this exact order from `db/` directory:

```sql
@install_all.sql
```

Or individually:

| Step | File | Purpose |
|---|---|---|
| 00 | `00_uc_crypto_pkg.sql` | Pure-PL/SQL crypto (SHA-512) |
| 01 | `01_ddl_new_objects.sql` | Core tables, sequences |
| 05b | `05b_table_corrections.sql` | Missing column additions |
| 03 | `03_epf_aaml_pkg_body.sql` | EPF_AAML_PKG body |
| 04 | `04_epf_emp_sync_pkg.sql` | DFN sync package |
| 06 | `06_epf_aaml_pkg_addons.sql` | EPF_AAML_PKG addons |
| 07 | `07_corp_admin_ddl.sql` | Corp admin tables, sequences |
| 08 | `08_epf_email_pkg.sql` | EPF_EMAIL_PKG |
| 09 | `09_epf_auth_pkg.sql` | EPF_AUTH_PKG (legacy, superseded) |
| 10 | `10_epf_corp_admin_pkg.sql` | EPF_CORP_ADMIN_PKG |
| 11 | `11_corp_txn_ddl.sql` | Transaction tables, sequences |
| 12 | `12_epf_corp_txn_pkg.sql` | EPF_CORP_TXN_PKG |
| 13 | `13_authorizer_employee_ddl.sql` | Authorizer/employee tables |
| 14 | `14_epf_email_pkg_addons.sql` | EPF_EMAIL_PKG rewrite (12 procedures) |
| 15 | `15_epf_authorizer_pkg.sql` | EPF_AUTHORIZER_PKG |
| 16 | `16_epf_employee_pkg.sql` | EPF_EMPLOYEE_PKG |
| 17 | `17_epf_util_pkg.sql` | EPF_UTIL helpers |
| 18 | `18_epf_corp_pkg.sql` | EPF_CORP_PKG |
| 19 | `19_epf_pkg_auth.sql` | EPF_PKG_AUTH (consolidated auth) |
| 20 | `20_epf_views.sql` | All 9 application views |
| — | `verify_all.sql` | Post-install verification |

> **IMPORTANT:** Never hardcode Status IDs. Always use `EPF_STATUS_PKG.GET_ID('CATEGORY','CODE')`.

---

## 3. APEX App Configuration

### 3.1 Authentication Scheme

**Name:** EPF Custom Auth  
**Type:** Custom  
**Authentication Function:**

```plsql
FUNCTION EPF_CUSTOM_AUTH (
    p_username IN VARCHAR2,
    p_password IN VARCHAR2
) RETURN BOOLEAN IS
    v_result VARCHAR2(1);
BEGIN
    v_result := EPF_PKG_AUTH.APEX_AUTHENTICATE(
        p_username   => p_username,
        p_password   => p_password,
        p_session_id => V('APP_SESSION')
    );
    RETURN (v_result = 'Y');
END;
```

**Post-Authentication Procedure:**

```plsql
PROCEDURE EPF_POST_AUTH IS
    v_user_id    NUMBER;
    v_ucid       NUMBER;
    v_company_id NUMBER;
    v_role_code  VARCHAR2(50);
    v_comp_count NUMBER;
BEGIN
    EPF_PKG_AUTH.POST_AUTH_SETUP(
        p_email          => V('APP_USER'),
        p_out_user_id    => v_user_id,
        p_out_ucid       => v_ucid,
        p_out_company_id => v_company_id,
        p_out_role_code  => v_role_code,
        p_out_comp_count => v_comp_count
    );
    APEX_UTIL.SET_SESSION_STATE('APP_USER_ID',        v_user_id);
    APEX_UTIL.SET_SESSION_STATE('APP_USER_COMPANY_ID',v_ucid);
    APEX_UTIL.SET_SESSION_STATE('APP_COMPANY_ID',     v_company_id);
    APEX_UTIL.SET_SESSION_STATE('APP_ROLE_CODE',      v_role_code);
    APEX_UTIL.SET_SESSION_STATE('APP_ITEM_COMP_COUNT',v_comp_count);
END;
```

**Login URL:** `f?p=&APP_ID.:9999:&APP_SESSION.`  
**Logout URL:** `f?p=&APP_ID.:9999:&APP_SESSION.:LOGOUT`

### 3.2 Application Process: SET_SESSION_DETAILS

**Name:** SET_SESSION_DETAILS  
**Point:** On New Instance (Before Header)  
**Condition:** User is authenticated  

```plsql
DECLARE
    v_comps    SYS.ODCINUMBERLIST;
    v_roles    SYS.ODCINUMBERLIST;
BEGIN
    -- Refresh company name + code
    APEX_UTIL.SET_SESSION_STATE('APP_COMPANY_NAME',
        EPF_UTIL.GET_COMPANY(:APP_COMPANY_ID));
    APEX_UTIL.SET_SESSION_STATE('APP_COMPANY_CODE',
        EPF_UTIL.GET_COMPANY_CODE(:APP_COMPANY_ID));

    -- Full name from session
    SELECT FULL_NAME INTO :APP_FULL_NAME
      FROM EPF_USERS WHERE USER_ID = :APP_USER_ID;

    -- Check force-password-change
    DECLARE v_force VARCHAR2(1);
    BEGIN
        SELECT NVL(FORCE_PWD_CHANGE,'N') INTO v_force
          FROM EPF_USERS WHERE USER_ID = :APP_USER_ID;
        APEX_UTIL.SET_SESSION_STATE('APP_ITEM_FORCE_PWD', v_force);
    END;
END;
```

### 3.3 Force-Password-Change Branch

Add a **Branch** to all pages with:
- **Type:** Redirect to Page in This Application
- **Target Page:** 9903
- **Condition:** `NVL(:APP_ITEM_FORCE_PWD,'N') = 'Y'`
- **When:** After Processing (or Before Regions on Page 9999)

### 3.4 Application Items

Create these in **Shared Components → Application Items**:

| Item | Scope | Description |
|---|---|---|
| `APP_USER_ID` | Application | DB User ID |
| `APP_USER_COMPANY_ID` | Application | Active UCID |
| `APP_COMPANY_ID` | Application | Active Company ID |
| `APP_COMPANY_NAME` | Application | Company name |
| `APP_COMPANY_CODE` | Application | Company code |
| `APP_FULL_NAME` | Application | User full name |
| `APP_ROLE_CODE` | Application | Primary role code |
| `APP_ITEM_FORCE_PWD` | Application | Y/N |
| `APP_ITEM_COMP_COUNT` | Application | Number of companies |
| `APP_FOLIO_ID` | Application | Employee folio ID |
| `APP_ITEM_REDIRECT_REASON` | Application | Login redirect messaging |

### 3.5 Navigation Bar

| Entry | URL / Item | Condition |
|---|---|---|
| `&APP_FULL_NAME.` | Static text | Always |
| `&APP_COMPANY_NAME.` | Static text | Always |
| Change Password | Page 9903 | User is authenticated |
| Logout | Logout URL | User is authenticated |

---

## 4. Authorization Schemes

Create in **Shared Components → Authorization Schemes → SQL Query Returns At Least One Row**:

### IS_AAML_MAKER
```sql
SELECT 1
  FROM EPF_V_USER_COMPANIES u
  JOIN EPF_USER_COMP_ROLES  ur ON ur.USER_COMPANY_ID = u.USER_COMPANY_ID
  JOIN EPF_ROLES             r  ON r.ROLE_ID          = ur.ROLE_ID
 WHERE UPPER(u.EMAIL) = UPPER(:APP_USER)
   AND r.ROLE_CODE    = 'ALFALAH_MAKER'
   AND ur.IS_ACTIVE   = 'Y'
   AND u.USER_COMPANY_STATUS = 'ACTIVE'
```

### IS_AAML_CHECKER
```sql
-- Same as IS_AAML_MAKER but ROLE_CODE = 'ALFALAH_CHECKER'
```

### IS_AAML_ANY
```sql
-- ROLE_CODE IN ('ALFALAH_MAKER','ALFALAH_CHECKER','ALFALAH_ADMIN','ALFALAH_OPS')
```

### IS_AAML_ADMIN
```sql
-- ROLE_CODE = 'ALFALAH_ADMIN'
```

### IS_AAML_OPS
```sql
-- ROLE_CODE = 'ALFALAH_OPS'
```

### IS_CORP_ADMIN
```sql
SELECT 1
  FROM EPF_V_USER_COMPANIES u
  JOIN EPF_USER_COMP_ROLES  ur ON ur.USER_COMPANY_ID = u.USER_COMPANY_ID
  JOIN EPF_ROLES             r  ON r.ROLE_ID          = ur.ROLE_ID
 WHERE UPPER(u.EMAIL) = UPPER(:APP_USER)
   AND r.ROLE_CODE    = 'CORP_ADMIN'
   AND ur.IS_ACTIVE   = 'Y'
   AND u.USER_COMPANY_STATUS = 'ACTIVE'
   AND u.COMPANY_ID   = :APP_COMPANY_ID
```

### IS_CORP_MAKER / IS_CORP_CHECKER / IS_CORP_AUTHORIZER
Same pattern — replace `ROLE_CODE = 'CORP_MAKER'` / `'CORP_CHECKER'` / `'CORP_AUTHORIZER'`.

### IS_EMPLOYEE
```sql
-- ROLE_CODE = 'EMPLOYEE'
```

---

## 5. Login & Auth Pages

### Page 9999 — Login

**Authentication:** None (public page)  
**Template:** Login (Theme 42 minimal)  
**CSS Classes:** `epf-login-page`

#### Page Items

| Item | Type | Purpose |
|---|---|---|
| `P9999_USERNAME` | Text Field | Email input |
| `P9999_PASSWORD` | Password | Password input |
| `P9999_REMEMBER` | Checkbox | Remember me token |
| `P9999_LAT` | Hidden | Device geolocation latitude |
| `P9999_LONG` | Hidden | Device geolocation longitude |
| `P9999_USER_TYPE` | Hidden | Set by auth after login (for routing) |

#### Buttons

| Button Name | Request | Action |
|---|---|---|
| `LOGIN` | `LOGIN` | Submit page |
| `FORGOT` | `FORGOT` | Submit page |

#### Processes

**Process: LOGIN** (On Submit, Request = LOGIN)
```plsql
APEX_AUTHENTICATION.LOGIN(
    p_username => LOWER(TRIM(:P9999_USERNAME)),
    p_password => :P9999_PASSWORD
);
```

**Process: FORGOT_REDIRECT** (On Submit, Request = FORGOT)
```plsql
BEGIN
    APEX_UTIL.REDIRECT_URL(
        APEX_PAGE.GET_URL(p_page => 9901)
    );
END;
```

**Process: CLEAR_SESSIONS** (Before Header, always)
```plsql
BEGIN
    IF :P9999_USERNAME IS NOT NULL THEN
        FOR s IN (SELECT session_id FROM apex_workspace_sessions
                  WHERE UPPER(user_name) = UPPER(:P9999_USERNAME))
        LOOP
            APEX_SESSION.DELETE_SESSION(p_session_id => s.session_id);
        END LOOP;
    END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END;
```

#### Branches (After Processing)

1. **Force Password Change** → Page 9903  
   Condition: `NVL(:APP_ITEM_FORCE_PWD,'N') = 'Y'`

2. **Multiple Companies** → Page 100 (Company Selector)  
   Condition: `:APP_ITEM_COMP_COUNT > 1`

3. **AAML Role → AAML Home** → Page 10  
   Condition: `:APP_ROLE_CODE IN ('ALFALAH_MAKER','ALFALAH_CHECKER','ALFALAH_ADMIN','ALFALAH_OPS')`

4. **Corp Admin → Page 30**  
   Condition: `:APP_ROLE_CODE = 'CORP_ADMIN'`

5. **Corp Maker → Page 40**  
   Condition: `:APP_ROLE_CODE = 'CORP_MAKER'`

6. **Corp Checker → Page 50**  
   Condition: `:APP_ROLE_CODE = 'CORP_CHECKER'`

7. **Corp Authorizer → Page 70**  
   Condition: `:APP_ROLE_CODE = 'CORP_AUTHORIZER'`

8. **Employee → Page 80**  
   Condition: `:APP_ROLE_CODE = 'EMPLOYEE'`

---

### Page 9901 — Forgot Password

**Authentication:** None  
**Template:** Login

#### Items

| Item | Type | Purpose |
|---|---|---|
| `P9901_EMAIL` | Text Field | User email |
| `P9901_SUCCESS_MSG` | Hidden | Set to Y after submit |

#### Process: FORGOT_PASSWORD (On Submit, Request = FORGOT_PASSWORD)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.FORGOT_PASSWORD(
        p_email       => LOWER(TRIM(:P9901_EMAIL)),
        p_ip_address  => OWA_UTIL.GET_CGI_ENV('REMOTE_ADDR'),
        p_out_success => v_success,
        p_out_message => v_message
    );
    -- Always show success (security — prevents email enumeration)
    :P9901_SUCCESS_MSG := 'Y';
END;
```

**Conditional Display:** Show success panel when `P9901_SUCCESS_MSG = 'Y'`; show form otherwise.

---

### Page 9902 — Set / Reset Password

**Authentication:** None  
**Template:** Login

#### Items

| Item | Type | Purpose |
|---|---|---|
| `P9902_TOKEN` | Hidden | URL parameter from email link |
| `P9902_USER_ID` | Hidden | Resolved from token |
| `P9902_NEW_PASSWORD` | Password | New password |
| `P9902_CONFIRM_PASSWORD` | Password | Confirm password |
| `P9902_OTP_SENT` | Hidden | Y after step 1 |
| `P9902_OTP_CODE` | Text | 6-digit OTP |

#### Process: VALIDATE_TOKEN (Before Header, always)
```plsql
DECLARE
    v_uid NUMBER;
BEGIN
    v_uid := EPF_PKG_AUTH.VALIDATE_RESET_TOKEN(p_token => :P9902_TOKEN);
    IF NVL(v_uid, 0) = 0 THEN
        APEX_UTIL.REDIRECT_URL(
            APEX_PAGE.GET_URL(p_page => 9999) || '&P9999_MSG=INVALID_TOKEN'
        );
    END IF;
    :P9902_USER_ID := v_uid;
END;
```

#### Process: SET_PASSWORD_REQUEST (Request = SET_PASSWORD_REQUEST)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.SET_NEW_PASSWORD_REQUEST(
        p_user_id          => :P9902_USER_ID,
        p_new_password     => :P9902_NEW_PASSWORD,
        p_confirm_password => :P9902_CONFIRM_PASSWORD,
        p_out_success      => v_success,
        p_out_message      => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P9902_OTP_SENT := 'Y';
END;
```

#### Process: CONFIRM_SET_PASSWORD (Request = CONFIRM_SET_PASSWORD)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.CONFIRM_OTP_AND_SET_PASSWORD(
        p_user_id     => :P9902_USER_ID,
        p_otp         => :P9902_OTP_CODE,
        p_token       => :P9902_TOKEN,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    -- Redirect to login with success message
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 9999));
END;
```

#### Process: RESEND_OTP (Request = RESEND_OTP)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.RESEND_OTP(
        p_user_id     => :P9902_USER_ID,
        p_purpose     => 'FORGOT_PWD',
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
    END IF;
END;
```

---

### Page 9903 — Change Password

**Authentication:** Required  
**Authorization Scheme:** None (all authenticated users)

#### Items

| Item | Type | Purpose |
|---|---|---|
| `P9903_CURRENT_PASSWORD` | Password | Current password |
| `P9903_NEW_PASSWORD` | Password | New password |
| `P9903_CONFIRM_PASSWORD` | Password | Confirm |
| `P9903_OTP_SENT` | Hidden | Y after step 1 |
| `P9903_OTP_CODE` | Text | 6-digit OTP |

#### Process: CHANGE_PASSWORD_REQUEST (Request = CHANGE_PASSWORD_REQUEST)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.CHANGE_PASSWORD(
        p_user_id          => :APP_USER_ID,
        p_current_password => :P9903_CURRENT_PASSWORD,
        p_new_password     => :P9903_NEW_PASSWORD,
        p_confirm_password => :P9903_CONFIRM_PASSWORD,
        p_out_success      => v_success,
        p_out_message      => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P9903_OTP_SENT := 'Y';
    -- Clear FORCE_PWD_CHANGE session item
    APEX_UTIL.SET_SESSION_STATE('APP_ITEM_FORCE_PWD','N');
END;
```

#### Process: CONFIRM_CHANGE_PASSWORD (Request = CONFIRM_CHANGE_PASSWORD)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.CONFIRM_OTP_CHANGE_PASSWORD(
        p_user_id     => :APP_USER_ID,
        p_otp         => :P9903_OTP_CODE,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P9903_OTP_SENT  := NULL;
    :P9903_OTP_CODE  := NULL;
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'Password changed successfully.';
END;
```

#### Process: RESEND_OTP_CHG (Request = RESEND_OTP_CHG)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_PKG_AUTH.RESEND_OTP(
        p_user_id     => :APP_USER_ID,
        p_purpose     => 'PWD_CHANGE',
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
    END IF;
END;
```

---

## 6. AAML Maker Pages

**Authorization Scheme on all AAML Maker pages:** `IS_AAML_MAKER`

### Page 10 — AAML Maker Dashboard (Client List)

**Template:** Standard (left nav)  
**IR Source:**

```sql
SELECT
    c.COMPANY_ID,
    c.REF_NO,
    c.COMPANY_NAME,
    cg.GROUP_NAME,
    c.IS_PRIMARY,
    c.NTN,
    c.PRIMARY_EMAIL,
    c.CITY,
    TO_CHAR(c.ONBOARDING_DATE,'DD-Mon-YYYY') AS ONBOARDING_DATE,
    st.STATUS_CODE       AS CLIENT_STATUS_CODE,
    st.STATUS_LABEL      AS CLIENT_STATUS_LABEL,
    st.CSS_CLASS         AS STATUS_CSS,
    os.TAB1_COMPLETE, os.TAB2_COMPLETE, os.TAB3_COMPLETE, os.TAB4_COMPLETE,
    CASE st.STATUS_CODE
        WHEN 'DRAFT'            THEN 'CONTINUE'
        WHEN 'REVERTED'         THEN 'CONTINUE'
        WHEN 'PENDING_CHECKER'  THEN 'VIEW'
        WHEN 'ACTIVE'           THEN 'MANAGE'
        ELSE 'VIEW'
    END AS ROW_ACTION
FROM EPF_COMPANIES c
JOIN EPF_COMPANY_GROUPS cg ON cg.GROUP_ID  = c.GROUP_ID
JOIN EPF_STATUSES       st ON st.STATUS_ID = c.STATUS_ID
                           AND st.CATEGORY_CODE = 'CLIENT_STATUS'
LEFT JOIN EPF_ONBOARDING_SUBMISSIONS os ON os.COMPANY_ID = c.COMPANY_ID
ORDER BY c.CREATED_DATE DESC
```

**Buttons:**
- `CREATE_CLIENT` → Page 4 (new client onboarding)

**Row Actions:** Column link on COMPANY_ID → Page 4 with `P4_COMPANY_ID = #COMPANY_ID#`

---

### Page 4 — Client Onboarding Wizard (4 Tabs)

**Template:** Wizard with progress tabs  
**Authorization:** `IS_AAML_MAKER`

#### Page Items

| Item | Type | Purpose |
|---|---|---|
| `P4_COMPANY_ID` | Hidden | Current company (NULL = new) |
| `P4_ACTIVE_TAB` | Hidden | 1/2/3/4 |
| `P4_COMPANY_NAME` | Text | Tab 1 |
| `P4_GROUP_ID` | Select List | Tab 1 — existing group |
| `P4_NEW_GROUP_NAME` | Text | Tab 1 — create new group |
| `P4_IS_PRIMARY` | Radio | Tab 1 — primary/sub |
| `P4_FUND1_ID` | Select List | Tab 1 — Fund 1 |
| `P4_FUND2_ID` | Select List | Tab 1 — Fund 2 (optional) |
| `P4_NTN` | Text | Tab 1 |
| `P4_SECP_REG_NO` | Text | Tab 1 |
| `P4_REGISTERED_ADDRESS` | Textarea | Tab 1 |
| `P4_CITY` | Text | Tab 1 |
| `P4_COUNTRY` | Text | Tab 1 |
| `P4_PRIMARY_EMAIL` | Text | Tab 1 |
| `P4_PRIMARY_PHONE` | Text | Tab 1 |
| `P4_DFN_ACCOUNT_CODE` | Text | Tab 1 |
| `P4_LOAN_ENABLED` | Checkbox | Tab 1 Settings |
| `P4_INTEREST_TYPE_ID` | Select List | Tab 1 Settings |
| `P4_FLOAT_TENURE` | Number | Tab 1 Settings |
| `P4_INTEREST_RATE` | Number | Tab 1 Settings |
| `P4_LOAN_LIMIT_PCT` | Number | Tab 1 Settings |
| `P4_MAX_INSTALMENT_MO` | Number | Tab 1 Settings |
| `P4_REALLOC_ENABLED` | Checkbox | Tab 1 Settings |
| `P4_USER_COMPANY_ID` | Hidden | Tab 2 edit target |
| `P4_AUTH_GROUP_ID` | Hidden | Tab 3 group target |
| `P4_GROUP_NAME` | Text | Tab 3 |
| `P4_MIN_APPROVALS` | Number | Tab 3 |
| `P4_MEMBER_USER_IDS` | Hidden | Tab 3 colon-list |

#### Process: SAVE_CLIENT (Request = SAVE_CLIENT)
```plsql
DECLARE
    v_company_id NUMBER;
BEGIN
    v_company_id := EPF_AAML_PKG.SAVE_CLIENT(
        p_company_id          => :P4_COMPANY_ID,
        p_company_name        => :P4_COMPANY_NAME,
        p_group_id            => :P4_GROUP_ID,
        p_new_group_name      => :P4_NEW_GROUP_NAME,
        p_is_primary          => :P4_IS_PRIMARY,
        p_fund1_id            => :P4_FUND1_ID,
        p_fund2_id            => :P4_FUND2_ID,
        p_loan_enabled        => :P4_LOAN_ENABLED,
        p_interest_type_id    => :P4_INTEREST_TYPE_ID,
        p_float_tenure        => :P4_FLOAT_TENURE,
        p_interest_rate       => :P4_INTEREST_RATE,
        p_loan_limit_pct      => :P4_LOAN_LIMIT_PCT,
        p_max_instalment_mo   => :P4_MAX_INSTALMENT_MO,
        p_realloc_enabled     => :P4_REALLOC_ENABLED,
        p_mm_limit            => NULL,
        p_debt_limit          => NULL,
        p_equity_limit        => NULL,
        p_admin_user_id       => NULL,
        p_created_by          => :APP_USER_ID
    );
    :P4_COMPANY_ID := v_company_id;
    :P4_ACTIVE_TAB := '2';
END;
```

#### Process: SAVE_COMPANY_USER (Request = SAVE_USER, Tab 2)
```plsql
DECLARE
    v_user_id  NUMBER;
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.SAVE_COMPANY_USER(
        p_company_id      => :P4_COMPANY_ID,
        p_user_company_id => :P4_USER_COMPANY_ID,
        p_folio_id        => NULL,
        p_role_id         => :P4_ROLE_ID,
        p_full_name       => :P4_FULL_NAME,
        p_email           => :P4_EMAIL,
        p_cnic            => :P4_CNIC,
        p_mobile_no       => :P4_MOBILE_NO,
        p_employee_code   => :P4_EMPLOYEE_CODE,
        p_performed_by    => :APP_USER_ID,
        p_out_user_id     => v_user_id,
        p_out_success     => v_success,
        p_out_message     => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
    END IF;
END;
```

#### Process: SAVE_AUTHORIZER_GROUP (Request = SAVE_GROUP, Tab 3)
```plsql
DECLARE
    v_group_id NUMBER;
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.SAVE_AUTHORIZER_GROUP(
        p_group_id        => :P4_AUTH_GROUP_ID,
        p_company_id      => :P4_COMPANY_ID,
        p_group_name      => :P4_GROUP_NAME,
        p_min_approvals   => :P4_MIN_APPROVALS,
        p_member_user_ids => :P4_MEMBER_USER_IDS,
        p_performed_by    => :APP_USER_ID,
        p_out_group_id    => v_group_id,
        p_out_success     => v_success,
        p_out_message     => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P4_AUTH_GROUP_ID := v_group_id;
END;
```

#### Process: SUBMIT_TO_CHECKER (Request = SUBMIT_TO_CHECKER)
```plsql
BEGIN
    EPF_AAML_PKG.SUBMIT_TO_CHECKER(
        p_company_id   => :P4_COMPANY_ID,
        p_submitted_by => :APP_USER_ID
    );
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 10));
END;
```

**Tab 4 (Employees):** Read-only IR showing `EPF_EMP_API_STAGING` + `EPF_FOLIOS` for this company. Sync is automated via scheduler `EPF_EMP_DAILY_SYNC`. Manual trigger button calls `EPF_EMP_SYNC_PKG.PROCESS_STAGING_BATCH`.

---

### Page 11 — Search / Advanced Client Search

**Authorization:** `IS_AAML_ANY`  
**IR Source:**

```sql
SELECT
    c.COMPANY_ID,
    c.REF_NO,
    c.COMPANY_NAME,
    cg.GROUP_NAME,
    c.NTN,
    c.PRIMARY_EMAIL,
    c.CITY,
    st.STATUS_CODE     AS CLIENT_STATUS_CODE,
    st.STATUS_LABEL    AS CLIENT_STATUS_LABEL,
    st.CSS_CLASS       AS STATUS_CSS,
    (SELECT COUNT(*) FROM EPF_USER_COMPANIES uc2
      JOIN EPF_STATUSES st2 ON st2.STATUS_ID = uc2.STATUS_ID
     WHERE uc2.COMPANY_ID = c.COMPANY_ID
       AND st2.STATUS_CODE != 'DELETED'
       AND uc2.FOLIO_ID IS NULL)  AS USER_COUNT,
    (SELECT COUNT(*) FROM EPF_USER_COMPANIES uc2
      JOIN EPF_STATUSES st2 ON st2.STATUS_ID = uc2.STATUS_ID
     WHERE uc2.COMPANY_ID = c.COMPANY_ID
       AND st2.STATUS_CODE != 'DELETED'
       AND uc2.FOLIO_ID IS NOT NULL) AS EMP_COUNT
FROM EPF_COMPANIES      c
JOIN EPF_COMPANY_GROUPS cg ON cg.GROUP_ID  = c.GROUP_ID
JOIN EPF_STATUSES       st ON st.STATUS_ID = c.STATUS_ID
                           AND st.CATEGORY_CODE = 'CLIENT_STATUS'
```

---

### Page 12 — User Management (AAML view, all companies)

**Authorization:** `IS_AAML_ANY`

**IR Source:**
```sql
SELECT
    a.USER_ID,
    cg.USER_COMPANY_ID,
    a.FULL_NAME,
    a.EMAIL,
    a.CNIC,
    a.MOBILE_NO,
    c.COMPANY_NAME,
    r.ROLE_NAME,
    r.ROLE_CODE,
    EPF_STATUS_PKG.GET_CODE(cg.STATUS_ID) AS USER_STATUS
FROM EPF_USERS          a
JOIN EPF_USER_COMPANIES cg ON cg.USER_ID    = a.USER_ID
JOIN EPF_USER_COMP_ROLES b ON b.USER_COMPANY_ID = cg.USER_COMPANY_ID
JOIN EPF_ROLES           r ON r.ROLE_ID     = b.ROLE_ID
JOIN EPF_COMPANIES       c ON c.COMPANY_ID  = cg.COMPANY_ID
WHERE r.ROLE_CODE != 'EMPLOYEE'
  AND b.IS_ACTIVE = 'Y'
ORDER BY a.FULL_NAME
```

**Process: DELETE USERS** (Request = DELETE_USERS):
```plsql
DECLARE
    v_deleted_status NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS','DELETED');
BEGIN
    UPDATE EPF_USER_COMP_ROLES ucr
       SET ucr.IS_ACTIVE = 'N'
     WHERE ucr.USER_COMPANY_ID IN (
               SELECT uc.USER_COMPANY_ID
                 FROM EPF_USER_COMPANIES uc
                WHERE uc.USER_ID MEMBER OF
                      (SELECT APEX_STRING.SPLIT_NUMBERS(:P12_USER_ID,':') FROM DUAL)
                  AND uc.COMPANY_ID = :P12_COMPANY_ID
           );
    UPDATE EPF_USER_COMPANIES
       SET STATUS_ID = v_deleted_status
     WHERE USER_ID MEMBER OF
               (SELECT APEX_STRING.SPLIT_NUMBERS(:P12_USER_ID,':') FROM DUAL)
       AND COMPANY_ID = :P12_COMPANY_ID;
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User(s) deactivated.';
END;
```

---

### Page 13 — Company User Management (single company)

Same as Page 12, filtered by `:P13_COMPANY_ID`. Replace `P12_` with `P13_` in all item references.

---

### Page 14 — Change Request History

**Authorization:** `IS_AAML_ANY`

**IR Source:**
```sql
SELECT
    cr.CHANGE_REQ_ID,
    cr.CHANGE_REF_NO,
    c.COMPANY_NAME,
    cr.CHANGE_TYPE,
    cr.SECTION_CHANGED,
    cr.REMARKS,
    cr.CHECKER_REMARKS,
    st.STATUS_CODE   AS REQ_STATUS_CODE,
    st.STATUS_LABEL  AS REQ_STATUS_LABEL,
    st.CSS_CLASS     AS STATUS_CSS,
    TO_CHAR(cr.CREATED_DATE,'DD-Mon-YYYY HH:MI AM') AS CREATED_DISP,
    cr.CREATED_BY,
    TO_CHAR(cr.CHECKED_DATE,'DD-Mon-YYYY HH:MI AM') AS CHECKED_DISP
FROM EPF_CLIENT_CHANGE_REQUESTS cr
JOIN EPF_COMPANIES  c  ON c.COMPANY_ID  = cr.COMPANY_ID
JOIN EPF_STATUSES   st ON st.STATUS_ID  = cr.STATUS_ID
WHERE (:P14_COMPANY_ID IS NULL OR cr.COMPANY_ID = :P14_COMPANY_ID)
ORDER BY cr.CREATED_DATE DESC
```

---

### Page 15 — Maker: Create / Edit Change Request

**Authorization:** `IS_AAML_MAKER`  
**Tabs:** Account Info | Settings | Users | Authorizer Groups

#### Before Header Process: LOAD_CR_FORM_DATA
```plsql
DECLARE
    v_cr_id   NUMBER;
    v_ref_no  VARCHAR2(50);
BEGIN
    -- If editing existing CR
    IF :P15_CHANGE_REQ_ID IS NOT NULL THEN
        NULL; -- already loaded
    ELSE
        EPF_AAML_PKG.BEGIN_CHANGE_REQUEST(
            p_company_id      => :P15_COMPANY_ID,
            p_user_id         => :APP_USER_ID,
            p_out_change_req_id => v_cr_id,
            p_out_ref_no      => v_ref_no
        );
        :P15_CHANGE_REQ_ID := v_cr_id;
        :P15_CR_REF_NO     := v_ref_no;
    END IF;

    -- Load current live values into P15_CURR_* items
    SELECT c.COMPANY_NAME, c.NTN, c.PRIMARY_EMAIL, c.PRIMARY_PHONE, c.CITY,
           cs.LOAN_ENABLED, cs.INTEREST_RATE_PCT, cs.MAX_LOAN_PCT,
           cs.MAX_INSTALMENT_MONTHS, cs.WITHDRAWAL_ENABLED
      INTO :P15_CURR_COMPANY_NAME, :P15_CURR_NTN, :P15_CURR_EMAIL,
           :P15_CURR_PHONE, :P15_CURR_CITY, :P15_CURR_LOAN_ENABLED,
           :P15_CURR_INT_RATE, :P15_CURR_LOAN_PCT, :P15_CURR_MAX_MONTHS,
           :P15_CURR_WD_ENABLED
      FROM EPF_COMPANIES      c
      LEFT JOIN EPF_COMPANY_SETTINGS cs ON cs.COMPANY_ID = c.COMPANY_ID
     WHERE c.COMPANY_ID = :P15_COMPANY_ID;
END;
```

#### Process: SAVE_CR_SECTION_ACCOUNT (Request = SAVE_ACCOUNT)
```plsql
DECLARE
    v_json VARCHAR2(4000);
BEGIN
    v_json := JSON_OBJECT(
        'company_name' VALUE :P15_CR_COMPANY_NAME,
        'ntn'          VALUE :P15_CR_NTN,
        'primary_email' VALUE :P15_CR_EMAIL,
        'primary_phone' VALUE :P15_CR_PHONE,
        'city'         VALUE :P15_CR_CITY
    );
    EPF_AAML_PKG.SAVE_CR_SECTION(
        p_change_req_id  => :P15_CHANGE_REQ_ID,
        p_section_code   => 'ACCOUNT',
        p_new_values_json => v_json,
        p_change_summary => 'Account information updated',
        p_user_id        => :APP_USER_ID
    );
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'Account section saved.';
END;
```

#### Process: SAVE_CR_SECTION_SETTINGS (Request = SAVE_SETTINGS)
```plsql
-- Same pattern, section_code = 'SETTINGS', JSON includes loan_enabled, rates, etc.
```

#### Process: SUBMIT_CR_TO_CHECKER (Request = SUBMIT_CR)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_AAML_PKG.SUBMIT_CR_TO_CHECKER(
        p_change_req_id => :P15_CHANGE_REQ_ID,
        p_user_id       => :APP_USER_ID,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 14));
END;
```

---

## 7. AAML Checker Pages

**Authorization Scheme on all AAML Checker pages:** `IS_AAML_CHECKER`

### Page 20 — Checker Dashboard

**Before Header Process: LOAD_CHECKER_STATS**
```plsql
BEGIN
    SELECT COUNT(*)
      INTO :STAT_NEW_CLIENTS
      FROM EPF_ONBOARDING_SUBMISSIONS os
      JOIN EPF_COMPANIES c ON c.COMPANY_ID = os.COMPANY_ID
     WHERE EPF_STATUS_PKG.GET_CODE(c.STATUS_ID) = 'PENDING_CHECKER';

    SELECT COUNT(*)
      INTO :STAT_CHANGE_REQS
      FROM EPF_CLIENT_CHANGE_REQUESTS cr
     WHERE EPF_STATUS_PKG.GET_CODE(cr.STATUS_ID) = 'PENDING_CHECKER';

    :STAT_TOTAL_PENDING := NVL(:STAT_NEW_CLIENTS,0) + NVL(:STAT_CHANGE_REQS,0);
END;
```

**IR Source (Unified pending queue):**
```sql
SELECT 'ONBOARDING' AS QUEUE_TYPE, 'New Client'  AS TYPE_BADGE,
       c.COMPANY_ID AS REF_ID, c.COMPANY_NAME, c.REF_NO AS REF_NO,
       TO_CHAR(os.SUBMITTED_DATE,'DD-Mon-YYYY') AS SUBMITTED_DISP,
       u.FULL_NAME AS SUBMITTED_BY,
       APEX_PAGE.GET_URL(p_page => 22,
           p_items => 'P22_COMPANY_ID', p_values => c.COMPANY_ID) AS REVIEW_LINK
  FROM EPF_ONBOARDING_SUBMISSIONS os
  JOIN EPF_COMPANIES  c ON c.COMPANY_ID = os.COMPANY_ID
  JOIN EPF_USERS      u ON u.USER_ID    = os.SUBMITTED_BY
 WHERE EPF_STATUS_PKG.GET_CODE(c.STATUS_ID) = 'PENDING_CHECKER'
UNION ALL
SELECT 'CHANGE_REQUEST', 'Change Request',
       cr.CHANGE_REQ_ID, c2.COMPANY_NAME, cr.CHANGE_REF_NO,
       TO_CHAR(cr.CREATED_DATE,'DD-Mon-YYYY'),
       cr.CREATED_BY,
       APEX_PAGE.GET_URL(p_page => 23,
           p_items => 'P23_CHANGE_REQ_ID', p_values => cr.CHANGE_REQ_ID)
  FROM EPF_CLIENT_CHANGE_REQUESTS cr
  JOIN EPF_COMPANIES c2 ON c2.COMPANY_ID = cr.COMPANY_ID
 WHERE EPF_STATUS_PKG.GET_CODE(cr.STATUS_ID) = 'PENDING_CHECKER'
ORDER BY 6 DESC
```

---

### Page 22 — Client Detail Review (Checker)

**Item:** `P22_COMPANY_ID` (Hidden, URL parameter)  
**Authorization:** `IS_AAML_CHECKER`  

**Regions:** 5 sub-tabs matching Maker's 4 onboarding tabs + Summary.

**Process: CHECKER_APPROVE** (Request = APPROVE)
```plsql
DECLARE
    v_remarks VARCHAR2(4000) := :P22_REMARKS;
BEGIN
    IF v_remarks IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Remarks are required.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    EPF_AAML_PKG.CHECKER_APPROVE(
        p_company_id  => :P22_COMPANY_ID,
        p_remarks     => v_remarks,
        p_approved_by => :APP_USER_ID
    );
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
END;
```

**Process: CHECKER_REVERT** (Request = REVERT)
```plsql
DECLARE
    v_remarks VARCHAR2(4000) := :P22_REVERT_REMARKS;
BEGIN
    IF v_remarks IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Revert remarks are mandatory.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    EPF_AAML_PKG.CHECKER_REVERT(
        p_company_id  => :P22_COMPANY_ID,
        p_remarks     => v_remarks,
        p_reverted_by => :APP_USER_ID
    );
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
END;
```

**Process: CHECKER_REJECT** (Request = REJECT)
```plsql
DECLARE
    v_remarks VARCHAR2(4000) := :P22_REJECT_REMARKS;
BEGIN
    IF v_remarks IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Rejection remarks are mandatory.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    EPF_AAML_PKG.CHECKER_REJECT(
        p_company_id  => :P22_COMPANY_ID,
        p_remarks     => v_remarks,
        p_rejected_by => :APP_USER_ID
    );
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
END;
```

---

### Page 23 — Change Request Review (Checker)

**Item:** `P23_CHANGE_REQ_ID` (Hidden, URL parameter)  
**Template:** Load current + old values side-by-side (strikethrough-red old / green new)

**Process: CR_CHECKER_APPROVE** (Request = CR_APPROVE)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    IF :P23_REMARKS IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Remarks are required.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    EPF_AAML_PKG.CR_CHECKER_APPROVE(
        p_change_req_id => :P23_CHANGE_REQ_ID,
        p_checker_id    => :APP_USER_ID,
        p_remarks       => :P23_REMARKS,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
END;
```

**Process: CR_CHECKER_REVERT** (Request = CR_REVERT)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    IF :P23_REVERT_REMARKS IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Revert remarks are mandatory.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    EPF_AAML_PKG.CR_CHECKER_REVERT(
        p_change_req_id   => :P23_CHANGE_REQ_ID,
        p_checker_id      => :APP_USER_ID,
        p_revert_remarks  => :P23_REVERT_REMARKS,
        p_out_success     => v_success,
        p_out_message     => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    APEX_UTIL.REDIRECT_URL(APEX_PAGE.GET_URL(p_page => 20));
END;
```

---

## 8. AAML Admin & Ops Pages

### AAML Admin (ALFALAH_ADMIN)

**Authorization Scheme:** `IS_AAML_ADMIN`

| Page | Title | Purpose |
|---|---|---|
| 200 | Admin Dashboard | Overview: client counts, pending counts, user counts |
| 201 | Company Groups Management | Create/edit/delete EPF_COMPANY_GROUPS |
| 202 | All Clients | Read-only V_EPF_CLIENT_DASHBOARD IR |
| 203 | Fund Management | Create/edit EPF_FUNDS |
| 204 | Roles Management | View EPF_ROLES |
| 205 | Block / Unblock Users | Calls EPF_PKG_AUTH.ADMIN_BLOCK_USER / ADMIN_UNBLOCK_USER |
| 206 | Activity Logs | IR over EPF_ACTIVITY_LOG |
| 207 | AAML Queue | V_EPF_CHANGE_REQUESTS (AAML_QUEUE status) |

#### Page 205 — Block / Unblock Users

**Process: BLOCK_USER** (Request = BLOCK_USER)
```plsql
BEGIN
    EPF_PKG_AUTH.ADMIN_BLOCK_USER(
        p_email       => :P205_EMAIL,
        p_blocked_by  => :APP_USER_ID,
        p_reason      => :P205_REASON
    );
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User blocked.';
END;
```

**Process: UNBLOCK_USER** (Request = UNBLOCK_USER)
```plsql
BEGIN
    EPF_PKG_AUTH.ADMIN_UNBLOCK_USER(
        p_email         => :P205_EMAIL,
        p_unblocked_by  => :APP_USER_ID
    );
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User unblocked.';
END;
```

---

### AAML Ops (ALFALAH_OPS)

**Authorization Scheme:** `IS_AAML_OPS`

| Page | Title | Purpose |
|---|---|---|
| 210 | Ops Dashboard | Summary cards for authorized requests in AAML queue |
| 211 | AAML Queue — Contributions | IR from EPF_AAML_QUEUE type=CONTRIB |
| 212 | AAML Queue — Loans | IR from EPF_AAML_QUEUE type=LOAN |
| 213 | AAML Queue — Withdrawals | IR from EPF_AAML_QUEUE type=WITHDRAWAL |
| 214 | AAML Queue — Lien | IR from EPF_AAML_QUEUE type=LIEN |
| 215 | AAML Queue — NOC | IR from EPF_AAML_QUEUE type=NOC |

**Mark Processed Process** (on each queue page):
```plsql
BEGIN
    UPDATE EPF_AAML_QUEUE
       SET STATUS        = 'PROCESSED',
           PROCESSED_BY  = :APP_USER_ID,
           PROCESSED_DATE = SYSDATE
     WHERE QUEUE_ID = :P21X_QUEUE_ID;

    -- Update parent request to COMPLETED
    UPDATE EPF_CONTRIB_BATCHES  -- (or EPF_LOAN_REQUESTS etc.)
       SET STATUS_ID = EPF_STATUS_PKG.GET_ID('REQUEST','COMPLETED')
     WHERE BATCH_ID = (SELECT REQUEST_ID FROM EPF_AAML_QUEUE
                        WHERE QUEUE_ID = :P21X_QUEUE_ID);
    COMMIT;
END;
```

---

## 9. Corp Admin — Page 30

**Authorization Scheme:** `IS_CORP_ADMIN`

**IR Source:**
```sql
SELECT
    a.USER_ID,
    cg.USER_COMPANY_ID,
    a.FULL_NAME,
    a.EMAIL,
    a.MOBILE_NO,
    a.EMPLOYEE_CODE,
    r.ROLE_NAME,
    r.ROLE_CODE,
    EPF_STATUS_PKG.GET_CODE(cg.STATUS_ID)  AS USER_STATUS,
    st.CSS_CLASS                            AS STATUS_CSS,
    a.ACCOUNT_LOCKED                        AS IS_BLOCKED,
    TO_CHAR(a.CREATED_DATE,'DD-Mon-YYYY')  AS CREATED_DISP
FROM EPF_USERS           a
JOIN EPF_USER_COMPANIES  cg ON cg.USER_ID      = a.USER_ID
JOIN EPF_USER_COMP_ROLES b  ON b.USER_COMPANY_ID = cg.USER_COMPANY_ID
JOIN EPF_ROLES           r  ON r.ROLE_ID        = b.ROLE_ID
JOIN EPF_STATUSES        st ON st.STATUS_ID     = cg.STATUS_ID
WHERE cg.COMPANY_ID = :APP_COMPANY_ID
  AND r.ROLE_CODE IN ('CORP_MAKER','CORP_CHECKER')
  AND b.IS_ACTIVE = 'Y'
  AND EPF_STATUS_PKG.GET_CODE(cg.STATUS_ID) != 'DELETED'
ORDER BY r.ROLE_CODE, a.FULL_NAME
```

#### Hidden Page Items
`P30_ROLE_CODE`, `P30_FULL_NAME`, `P30_EMAIL`, `P30_MOBILE_NO`, `P30_EMPLOYEE_CODE`,
`P30_EDIT_USER_COMPANY_ID`, `P30_EDIT_ROLE_CODE`, `P30_EDIT_FULL_NAME`, `P30_EDIT_MOBILE_NO`,
`P30_EDIT_EMPLOYEE_CODE`, `P30_EDIT_STATUS_CODE`, `P30_SELECTED_USER_IDS`, `P30_HISTORY_USER_COMPANY_ID`

#### Process: CORP_ADMIN_CREATE_USER (Request = CREATE_USER)
```plsql
DECLARE
    v_ucid    NUMBER;
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_ADMIN_PKG.CREATE_USER(
        p_company_id   => :APP_COMPANY_ID,
        p_admin_ucid   => :APP_USER_COMPANY_ID,
        p_role_code    => :P30_ROLE_CODE,
        p_full_name    => :P30_FULL_NAME,
        p_email        => LOWER(TRIM(:P30_EMAIL)),
        p_mobile_no    => :P30_MOBILE_NO,
        p_emp_code     => :P30_EMPLOYEE_CODE,
        p_out_ucid     => v_ucid,
        p_out_success  => v_success,
        p_out_message  => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := v_message;
END;
```

#### Process: CORP_ADMIN_UPDATE_USER (Request = UPDATE_USER)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_ADMIN_PKG.UPDATE_USER(
        p_ucid         => :P30_EDIT_USER_COMPANY_ID,
        p_admin_ucid   => :APP_USER_COMPANY_ID,
        p_role         => :P30_EDIT_ROLE_CODE,
        p_full_name    => :P30_EDIT_FULL_NAME,
        p_mobile_no    => :P30_EDIT_MOBILE_NO,
        p_emp_code     => :P30_EDIT_EMPLOYEE_CODE,
        p_status       => :P30_EDIT_STATUS_CODE,
        p_out_success  => v_success,
        p_out_message  => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
    END IF;
END;
```

#### Process: CORP_ADMIN_DELETE_USERS (Request = DELETE_USERS)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_ADMIN_PKG.DELETE_USERS(
        p_ucids_csv    => :P30_SELECTED_USER_IDS,
        p_admin_ucid   => :APP_USER_COMPANY_ID,
        p_out_success  => v_success,
        p_out_message  => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
    END IF;
END;
```

#### Application Process: GET_USER_JSON (On Demand)
```plsql
DECLARE
    v_result CLOB;
    r EPF_USERS%ROWTYPE;
BEGIN
    SELECT u.FULL_NAME, u.EMAIL, u.MOBILE_NO, u.EMPLOYEE_CODE,
           EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID), r.ROLE_CODE
      INTO r.FULL_NAME, r.EMAIL, r.MOBILE_NO, r.EMPLOYEE_CODE,
           r.STATUS, r.ROLE_CODE -- use actual vars
      FROM EPF_USERS u
      JOIN EPF_USER_COMPANIES  uc ON uc.USER_ID = u.USER_ID
      JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
      JOIN EPF_ROLES rr ON rr.ROLE_ID = ucr.ROLE_ID
     WHERE uc.USER_COMPANY_ID = TO_NUMBER(APEX_APPLICATION.G_X01);

    -- Return JSON via HTP
    HTP.P('{"full_name":"'||r.FULL_NAME||'","email":"'||r.EMAIL||
          '","mobile_no":"'||r.MOBILE_NO||'","role_code":"'||
          r.ROLE_CODE||'"}');
END;
```

---

## 10. Corp Maker Pages (40–45)

**Authorization Scheme on all Corp Maker pages:** `IS_CORP_MAKER`

### Page 40 — Create Contribution Upload (4-Step Wizard)

**Items:** `P40_STEP`(1-4), `P40_FUND_ID`, `P40_CONTRIB_MONTH`, `P40_FILE`(file browse), `P40_BATCH_ID`, `P40_BATCH_NO`, `P40_FINISH_MSG`

**Alerts Summary Items:** `P40_VALID_COUNT`, `P40_ERROR_COUNT`, `P40_DUPLICATE_COUNT`, `P40_VARIANCE_AMT`, `P40_VARIANCE_EMP`

#### Process: PARSE_UPLOAD (Request = UPLOAD_FILE, Step 1→2)
```plsql
BEGIN
    -- Parse CSV file into APEX Collection CONTRIB_UPLOAD
    APEX_COLLECTION.CREATE_OR_TRUNCATE_COLLECTION('CONTRIB_UPLOAD');
    -- Loop through uploaded file rows
    -- C001=CNIC, C002=FOLIO_NO, C003=EMP_NAME, N001=EMP_AMT, N002=EMP_AMT
    -- (Implementation depends on file parsing approach — use APEX_DATA_PARSER)
    FOR rec IN (
        SELECT col001, col002, col003,
               TO_NUMBER(col004) AS emp_amt,
               TO_NUMBER(col005) AS er_amt
          FROM TABLE(APEX_DATA_PARSER.PARSE(
              p_content      => :P40_FILE,
              p_file_name    => APEX_APPLICATION.G_F01(1),
              p_skip_rows    => 1
          ))
    ) LOOP
        APEX_COLLECTION.ADD_MEMBER(
            p_collection_name => 'CONTRIB_UPLOAD',
            p_c001 => rec.col001,  -- CNIC
            p_c002 => rec.col002,  -- Folio
            p_c003 => rec.col003,  -- Name
            p_n001 => rec.emp_amt,
            p_n002 => rec.er_amt
        );
    END LOOP;
    :P40_STEP := '2';
END;
```

#### Process: CREATE_BATCH (Request = CREATE_BATCH, Step 2→3)
```plsql
DECLARE
    v_batch_id  NUMBER;
    v_batch_no  VARCHAR2(50);
    v_success   VARCHAR2(1);
    v_message   VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CREATE_CONTRIB_BATCH(
        p_company_id    => :APP_COMPANY_ID,
        p_maker_ucid    => :APP_USER_COMPANY_ID,
        p_fund_id       => :P40_FUND_ID,
        p_month         => TO_DATE(:P40_CONTRIB_MONTH,'YYYY-MM'),
        p_file_name     => APEX_APPLICATION.G_F01(1),
        p_out_batch_id  => v_batch_id,
        p_out_batch_no  => v_batch_no,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P40_BATCH_ID   := v_batch_id;
    :P40_BATCH_NO   := v_batch_no;
    :P40_FINISH_MSG := 'Contribution upload submitted for review.';
    :P40_STEP       := '4';
END;
```

---

### Page 41 — Create Loan Request (3-Step Wizard)

**Items:** `P41_STEP`(1-3), `P41_CNIC`, `P41_FOLIO_ID`, `P41_EMP_NAME`, `P41_CURRENT_BALANCE`, `P41_AMOUNT`, `P41_INSTALMENT_MONTHS`, `P41_PAY_MODE`, `P41_LOAN_NO`, `P41_FINISH_MSG`

#### Process: CREATE_LOAN (Request = CREATE_LOAN, Step 2→3)
```plsql
DECLARE
    v_loan_id  NUMBER;
    v_loan_no  VARCHAR2(50);
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CREATE_LOAN_REQUEST(
        p_company_id        => :APP_COMPANY_ID,
        p_maker_ucid        => :APP_USER_COMPANY_ID,
        p_folio_id          => :P41_FOLIO_ID,
        p_amount            => TO_NUMBER(:P41_AMOUNT),
        p_instalment_months => TO_NUMBER(:P41_INSTALMENT_MONTHS),
        p_current_balance   => TO_NUMBER(:P41_CURRENT_BALANCE),
        p_pay_mode          => :P41_PAY_MODE,
        p_out_loan_id       => v_loan_id,
        p_out_loan_no       => v_loan_no,
        p_out_success       => v_success,
        p_out_message       => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P41_LOAN_NO    := v_loan_no;
    :P41_FINISH_MSG := 'Loan request ' || v_loan_no || ' submitted.';
    :P41_STEP       := '3';
END;
```

---

### Page 42 — Create Withdrawal Request (3-Step Wizard)

**Items:** `P42_STEP`, `P42_FOLIO_ID`, `P42_AMOUNT`, `P42_FULL_WITHDRAWAL`(checkbox Y/N), `P42_PAY_MODE`, `P42_REASON`, `P42_WD_NO`, `P42_FINISH_MSG`

#### Process: CREATE_WITHDRAWAL (Request = CREATE_WITHDRAWAL)
```plsql
DECLARE
    v_wd_id   NUMBER;
    v_wd_no   VARCHAR2(50);
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CREATE_WITHDRAWAL_REQUEST(
        p_company_id    => :APP_COMPANY_ID,
        p_maker_ucid    => :APP_USER_COMPANY_ID,
        p_folio_id      => :P42_FOLIO_ID,
        p_amount        => CASE WHEN :P42_FULL_WITHDRAWAL = 'Y' THEN NULL
                               ELSE TO_NUMBER(:P42_AMOUNT) END,
        p_wd_type       => CASE WHEN :P42_FULL_WITHDRAWAL = 'Y'
                               THEN 'FULL' ELSE 'PARTIAL' END,
        p_reason        => :P42_REASON,
        p_out_wd_id     => v_wd_id,
        p_out_wd_no     => v_wd_no,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P42_WD_NO      := v_wd_no;
    :P42_FINISH_MSG := 'Withdrawal request ' || v_wd_no || ' submitted.';
    :P42_STEP       := '3';
END;
```

---

### Page 43 — Lien Mark / Unmark

**Items:** `P43_TOGGLE`(MARK/UNMARK), `P43_SELECTED_FOLIO_IDS`, `P43_REASON`, `P43_LOAN_WARNING`, `P43_ATTENTION_MSG`

#### IR Source (Employee selector):
```sql
SELECT f.FOLIO_ID, f.FOLIO_NUMBER, u.FULL_NAME AS EMP_NAME, u.CNIC,
       NVL(f.LIEN_MARKED,'N') AS LIEN_STATUS,
       NVL(f.IS_DISABLED,'N') AS IS_DISABLED,
       NVL(f.NOC_ISSUED,'N')  AS NOC_ISSUED
  FROM EPF_FOLIOS f
  JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
  JOIN EPF_USERS           u  ON u.USER_ID   = uc.USER_ID
 WHERE f.COMPANY_ID = :APP_COMPANY_ID
   AND NVL(f.IS_DISABLED,'N') = 'N'
 ORDER BY u.FULL_NAME
```

#### Process: CREATE_LIEN_REQUEST (Request IN MARK_LIEN, UNMARK_LIEN)
```plsql
DECLARE
    v_lien_no    VARCHAR2(50);
    v_loan_warn  NUMBER;
    v_success    VARCHAR2(1);
    v_message    VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CREATE_LIEN_REQUEST(
        p_company_id     => :APP_COMPANY_ID,
        p_maker_ucid     => :APP_USER_COMPANY_ID,
        p_folio_ids      => :P43_SELECTED_FOLIO_IDS,
        p_request_type   => CASE :REQUEST WHEN 'MARK_LIEN' THEN 'MARK'
                                          ELSE 'UNMARK' END,
        p_reason         => :P43_REASON,
        p_out_lien_no    => v_lien_no,
        p_out_loan_warning => v_loan_warn,
        p_out_success    => v_success,
        p_out_message    => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P43_LOAN_WARNING   := v_loan_warn;
    :P43_ATTENTION_MSG  := v_message;
END;
```

---

### Page 44 — NOC Issuance

**Items:** `P44_SELECTED_FOLIO_IDS`, `P44_ATTENTION_MSG`

#### IR Source: Same as Page 43 but filtered to `LIEN_MARKED='N'` and `NOC_ISSUED='N'`

#### Process: ISSUE_NOC (Request = ISSUE_NOC)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CREATE_NOC_REQUESTS(
        p_company_id  => :APP_COMPANY_ID,
        p_maker_ucid  => :APP_USER_COMPANY_ID,
        p_folio_ids   => :P44_SELECTED_FOLIO_IDS,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P44_ATTENTION_MSG := v_message;
END;
```

---

### Page 45 — Disable Employees

**Items:** `P45_SELECTED_FOLIO_IDS`

#### IR Source: Only NOC_ISSUED='Y' employees
```sql
SELECT f.FOLIO_ID, f.FOLIO_NUMBER, u.FULL_NAME AS EMP_NAME, u.CNIC,
       NVL(f.IS_DISABLED,'N') AS IS_DISABLED,
       CASE WHEN EXISTS (
           SELECT 1 FROM EPF_EMP_DISABLE_REQUESTS d
            WHERE d.FOLIO_ID = f.FOLIO_ID
              AND EPF_STATUS_PKG.GET_CODE(d.STATUS_ID) IN ('PENDING_CHECKER','PENDING_AUTHORIZER')
           ) THEN 'Y' ELSE 'N' END AS HAS_PENDING
  FROM EPF_FOLIOS f
  JOIN EPF_USER_COMPANIES uc ON uc.FOLIO_ID = f.FOLIO_ID
  JOIN EPF_USERS           u  ON u.USER_ID   = uc.USER_ID
 WHERE f.COMPANY_ID = :APP_COMPANY_ID
   AND NVL(f.NOC_ISSUED,'N') = 'Y'
   AND NVL(f.IS_DISABLED,'N') = 'N'
 ORDER BY u.FULL_NAME
```

#### Process: DISABLE_EMPLOYEES (Request = DISABLE_EMPLOYEES)
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_CORP_TXN_PKG.CREATE_DISABLE_REQUESTS(
        p_company_id  => :APP_COMPANY_ID,
        p_maker_ucid  => :APP_USER_COMPANY_ID,
        p_folio_ids   => :P45_SELECTED_FOLIO_IDS,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
    END IF;
END;
```

---

## 11. Corp Checker Pages (50–55, 60)

**Authorization Scheme on all Corp Checker pages:** `IS_CORP_CHECKER`

### Shared Checker Pattern

All checker pages (50–55) share the same structure:
- IR filtered by `STATUS_CODE = 'PENDING_CHECKER'` and `COMPANY_ID = :APP_COMPANY_ID`
- Items: `P5x_SELECTED_IDS`, `P5x_REMARKS`, `P5x_DECISION`
- Buttons: `APPROVE_SELECTED` / `REJECT_SELECTED`
- Reject opens a remarks modal (remarks mandatory)

#### Generic Checker Process Template:
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
    v_decision VARCHAR2(10) := CASE :REQUEST
        WHEN 'APPROVE_SELECTED' THEN 'APPROVE'
        WHEN 'REJECT_SELECTED'  THEN 'REJECT'
    END;
BEGIN
    IF v_decision = 'REJECT' AND :P5X_REMARKS IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Remarks are mandatory for rejection.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;

    EPF_CORP_TXN_PKG.CHECKER_DECIDE(
        p_request_type  => 'CONTRIB',   -- change per page
        p_request_ids   => :P5X_SELECTED_IDS,
        p_checker_ucid  => :APP_USER_COMPANY_ID,
        p_decision      => v_decision,
        p_remarks       => :P5X_REMARKS,
        p_out_success   => v_success,
        p_out_message   => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P5X_SELECTED_IDS := NULL;
    :P5X_REMARKS      := NULL;
END;
```

| Page | Request Type | IR Source View |
|---|---|---|
| 50 | `CONTRIB` | `V_EPF_CONTRIBUTION_BATCHES` |
| 51 | `LOAN` | `V_EPF_LOAN_REQUESTS` |
| 52 | `WITHDRAWAL` | `V_EPF_WITHDRAWAL_REQUESTS` |
| 53 | `LIEN` | `EPF_LIEN_REQUESTS` |
| 54 | `NOC` | `EPF_NOC_REQUESTS` |
| 55 | `DISABLE` | `EPF_EMP_DISABLE_REQUESTS` |

### Page 60 — Settings (Feature Access & Realloc Groups)

**Items:** `P60_FEATURE_CODE`(LOAN/WITHDRAWAL), `P60_SELECTED_FOLIO_IDS`, `P60_SELECTED_ACCESS_IDS`, `P60_REMARKS`, `P60_GROUP_ID`, `P60_GROUP_NAME`, `P60_MM_LIMIT`, `P60_DEBT_LIMIT`, `P60_EQUITY_LIMIT`, `P60_ADD_FOLIO_IDS`, `P60_REMOVE_FOLIO_IDS`

#### Process: FEATURE_ACCESS_ADD (Request = FEATURE_ADD)
```plsql
BEGIN
    EPF_CORP_TXN_PKG.REQUEST_FEATURE_ACCESS_CHANGE(
        p_company_id   => :APP_COMPANY_ID,
        p_maker_ucid   => :APP_USER_COMPANY_ID,
        p_feature_code => :P60_FEATURE_CODE,
        p_folio_ids    => :P60_SELECTED_FOLIO_IDS,
        p_action       => 'ADD',
        p_out_success  => v_success,
        p_out_message  => v_message
    );
END;
```

#### Process: SAVE_REALLOC_GROUP (Request = SAVE_GROUP)
```plsql
BEGIN
    EPF_CORP_TXN_PKG.SAVE_REALLOC_GROUP(
        p_group_id       => :P60_GROUP_ID,
        p_company_id     => :APP_COMPANY_ID,
        p_maker_ucid     => :APP_USER_COMPANY_ID,
        p_group_name     => :P60_GROUP_NAME,
        p_mm_limit       => :P60_MM_LIMIT,
        p_debt_limit     => :P60_DEBT_LIMIT,
        p_equity_limit   => :P60_EQUITY_LIMIT,
        p_add_folio_ids  => :P60_ADD_FOLIO_IDS,
        p_remove_folio_ids => :P60_REMOVE_FOLIO_IDS,
        p_out_success    => v_success,
        p_out_message    => v_message
    );
END;
```

---

## 12. Corp Authorizer Pages (70–76)

**Authorization Scheme on all pages:** `IS_CORP_AUTHORIZER`

### Page 70 — Authorize Requests Landing

**Before Header Process:** Load `P70_ACTIVE_COUNT` — count of requests pending this authorizer's decision (see `apex/corp_authorizer/page_processes.sql` for full query).

**Cards:** Contribution Uploads, Loan Requests, Withdrawal Requests, Lien Requests, NOC Requests, Loan Settings — each links to pages 71–76.

---

### Pages 71–75 — Authorize by Type

All follow the same pattern. See Section 12 processes in `apex/corp_authorizer/page_processes.sql`.

| Page | Type Token | Items |
|---|---|---|
| 71 | `CONTRIB` | `P71_SELECTED_IDS`, `P71_REMARKS`, `P71_SUCCESS_MSG` |
| 72 | `LOAN` | `P72_SELECTED_IDS`, `P72_REMARKS`, `P72_SUCCESS_MSG` |
| 73 | `WITHDRAWAL` | `P73_SELECTED_IDS`, `P73_REMARKS`, `P73_SUCCESS_MSG` |
| 74 | `LIEN` | `P74_SELECTED_IDS`, `P74_REMARKS`, `P74_SUCCESS_MSG` |
| 75 | `NOC` | `P75_SELECTED_IDS`, `P75_REMARKS`, `P75_SUCCESS_MSG` |

**IR Filter Pattern** (same for all — exclude requests already decided by THIS authorizer):
```sql
WHERE COMPANY_ID = :APP_COMPANY_ID
  AND EPF_STATUS_PKG.GET_CODE(STATUS_ID) = 'PENDING_AUTHORIZER'
  AND NOT EXISTS (
      SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
       WHERE d.REQUEST_TYPE    = '<TYPE>'
         AND d.REQUEST_ID      = <ID_COLUMN>
         AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
  )
```

**Decision Process** (replace type/ids per page):
```plsql
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_decision VARCHAR2(10) := CASE :REQUEST
        WHEN 'APPROVE_CONTRIB' THEN 'APPROVE'
        WHEN 'REJECT_CONTRIB'  THEN 'REJECT'
    END;
    -- loop over colon-separated IDs
    v_pos  PLS_INTEGER := 1;
    v_nxt  PLS_INTEGER;
    v_id   NUMBER;
    v_ids  VARCHAR2(4000) := :P71_SELECTED_IDS;
BEGIN
    IF v_ids IS NULL THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Please select at least one request.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    LOOP
        v_nxt := INSTR(v_ids, ':', v_pos);
        v_id  := TO_NUMBER(TRIM(CASE WHEN v_nxt=0 THEN SUBSTR(v_ids,v_pos)
                                     ELSE SUBSTR(v_ids,v_pos,v_nxt-v_pos) END));
        EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST(
            p_request_type    => 'CONTRIB',
            p_request_id      => v_id,
            p_authorizer_ucid => :APP_USER_COMPANY_ID,
            p_decision        => v_decision,
            p_remarks         => :P71_REMARKS,
            p_out_success     => v_success,
            p_out_message     => v_message
        );
        IF v_success = 'N' THEN
            APEX_ERROR.ADD_ERROR(p_message => v_message,
                p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        END IF;
        EXIT WHEN v_nxt = 0;
        v_pos := v_nxt + 1;
    END LOOP;
    :P71_SELECTED_IDS := NULL;
    :P71_REMARKS      := NULL;
END;
```

---

### Page 76 — Loan Settings Authorization

**IR Source:** See `apex/corp_authorizer/ir_queries.sql` — Page 76 query shows current vs pending settings.

**Process: AUTHORIZE_LOAN_SETTINGS** (Request IN APPROVE_LOAN_SETTINGS, REJECT_LOAN_SETTINGS):
```plsql
DECLARE
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_AUTHORIZER_PKG.AUTHORIZE_LOAN_SETTINGS(
        p_company_id      => :APP_COMPANY_ID,
        p_authorizer_ucid => :APP_USER_COMPANY_ID,
        p_decision        => CASE :REQUEST
                                 WHEN 'APPROVE_LOAN_SETTINGS' THEN 'APPROVE'
                                 ELSE 'REJECT'
                             END,
        p_remarks         => :P76_REMARKS,
        p_out_success     => v_success,
        p_out_message     => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P76_SUCCESS_MSG := v_message;
END;
```

---

## 13. Employee Self-Service Pages (80–85)

**Authorization Scheme:** `IS_EMPLOYEE`

> All employee pages bind to `:APP_FOLIO_ID` (set in POST_AUTH_SETUP from `EPF_USER_COMPANIES.FOLIO_ID`).

### Page 80 — Employee Dashboard

**Items:** `P80_DATE_FROM`, `P80_DATE_TO`, `P80_SEARCH_FLAG`

**Regions:**
1. **Fund Overview IR** — see `apex/employee/ir_queries.sql` (PAGE 80 Fund Overview Table)
2. **Pie Chart** — APEX Chart region, data from Dashboard Pie Chart query
3. **Date filter form** — P80_DATE_FROM, P80_DATE_TO, Search / Clear buttons

**Processes:** `P80_SET_SEARCH_FLAG` (Request=SEARCH), `P80_CLEAR_FILTERS` (Request=CLEAR_FILTERS)

---

### Page 81 — Account Statement

**Items:** `P81_PERIOD_TYPE`(Select: Last 30 Days/Last 90 Days/From Inception/Date Range), `P81_DATE_FROM`, `P81_DATE_TO`, `P81_FUND_ID`, `P81_SUCCESS_MSG`

**Buttons:** `VIEW_NOW` | `REQUEST_ON_EMAIL`

**IR Source:** See Account Statement query in `apex/employee/ir_queries.sql`

**Processes:** `P81_VIEW_STATEMENT` (Request=VIEW_NOW), `P81_REQUEST_ON_EMAIL` (Request=REQUEST_ON_EMAIL)

---

### Page 82 — Tax Certificates

**Items:** `P82_TAX_YEAR`(Select List from Fiscal Year LOV), `P82_CERT_HTML`(Display Only — Rich Text), `P82_SUCCESS_MSG`

**Process: GENERATE_CERT** (Request=GENERATE_CERT):
```plsql
DECLARE
    v_html    CLOB;
    v_success VARCHAR2(1);
    v_message VARCHAR2(4000);
BEGIN
    EPF_EMPLOYEE_PKG.GENERATE_TAX_CERTIFICATE(
        p_user_id     => :APP_USER_ID,
        p_folio_id    => :APP_FOLIO_ID,
        p_tax_year    => :P82_TAX_YEAR,
        p_out_html    => v_html,
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P82_CERT_HTML   := v_html;
    :P82_SUCCESS_MSG := v_message;
END;
```

---

### Page 83 — Portfolio Reallocation

**Items:** `P83_GROUP_ID`(Select List — employee's realloc group), `P83_MM_PCT`, `P83_DEBT_PCT`, `P83_EQUITY_PCT`, `P83_TOTAL_PCT`(Display, JS computed), `P83_SUCCESS_MSG`

**Current Allocation IR:** See `apex/employee/ir_queries.sql` PAGE 83 query

**JavaScript (Dynamic Action on pct fields):**
```javascript
var mm   = parseFloat($('#P83_MM_PCT').val())||0;
var debt = parseFloat($('#P83_DEBT_PCT').val())||0;
var eq   = parseFloat($('#P83_EQUITY_PCT').val())||0;
apex.item('P83_TOTAL_PCT').setValue((mm+debt+eq).toFixed(1));
```

**Process: VALIDATE_ALLOCATION** (Request=UPDATE_ALLOCATION)
```plsql
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
BEGIN
    IF TO_NUMBER(NVL(:P83_MM_PCT,'0'))+TO_NUMBER(NVL(:P83_DEBT_PCT,'0'))+
       TO_NUMBER(NVL(:P83_EQUITY_PCT,'0')) != 100 THEN
        APEX_ERROR.ADD_ERROR(p_message => 'Total must equal 100%.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    EPF_EMPLOYEE_PKG.CREATE_PORTFOLIO_REALLOC(
        p_folio_id    => :APP_FOLIO_ID,
        p_group_id    => :P83_GROUP_ID,
        p_mm_pct      => TO_NUMBER(:P83_MM_PCT),
        p_debt_pct    => TO_NUMBER(:P83_DEBT_PCT),
        p_equity_pct  => TO_NUMBER(:P83_EQUITY_PCT),
        p_out_success => v_success,
        p_out_message => v_message
    );
    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(p_message => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        RETURN;
    END IF;
    :P83_SUCCESS_MSG := v_message;
END;
```

---

### Page 84 — Create Loan Request (Employee, 3-Step)

**Items:** `P84_STEP`(1/2/3), `P84_AMOUNT`, `P84_INSTALMENT_MONTHS`, `P84_PAYMENT_MODE`(CHEQUE/ONLINE), `P84_LOAN_ID`, `P84_LOAN_NO`, `P84_SUBMIT_DATE`, `P84_FINISH_MSG`

**Step 2 Review Region:** Instalment schedule (from PAGE 84 loan schedule query in ir_queries.sql)

**Processes:** See `apex/employee/page_processes.sql` — P84_STEP1_NEXT, P84_STEP2_BACK, P84_STEP2_SUBMIT, P84_FINISH

---

### Page 85 — Create Withdrawal Request (Employee, 3-Step)

**Items:** `P85_STEP`, `P85_AMOUNT`, `P85_WD_TYPE`, `P85_FULL_FLAG`(checkbox), `P85_PAYMENT_MODE`, `P85_WD_ID`, `P85_WD_NO`, `P85_SUBMIT_DATE`, `P85_FINISH_MSG`

**Processes:** See `apex/employee/page_processes.sql` — P85_STEP1_NEXT, P85_STEP2_BACK, P85_STEP2_SUBMIT, P85_FINISH

**Dynamic Action — Full Withdrawal checkbox:**
- When `P85_FULL_FLAG` = `Y` → disable `P85_AMOUNT`, set value to 0
- When `P85_FULL_FLAG` = `N` → enable `P85_AMOUNT`

---

## 14. Shared APEX Components

### Application Process: GET_REQUEST_HISTORY_AJAX (On Demand)

```plsql
DECLARE
    v_cursor SYS_REFCURSOR;
    v_code   VARCHAR2(30)   := APEX_APPLICATION.G_X01;
    v_id     NUMBER         := TO_NUMBER(APEX_APPLICATION.G_X02);
    l_action_code VARCHAR2(200);
    l_narration   VARCHAR2(4000);
    l_perf_date   DATE;
    l_perf_name   VARCHAR2(200);
    l_json        CLOB := '[';
    l_first       BOOLEAN := TRUE;
BEGIN
    v_cursor := EPF_AUTHORIZER_PKG.GET_REQUEST_HISTORY(v_code, v_id);
    LOOP
        FETCH v_cursor INTO l_action_code, l_narration, l_perf_date, l_perf_name;
        EXIT WHEN v_cursor%NOTFOUND;
        IF NOT l_first THEN l_json := l_json || ','; END IF;
        l_json := l_json || '{"action":"' || l_action_code
               || '","narration":"' || REPLACE(l_narration,'"','\\"')
               || '","date":"' || TO_CHAR(l_perf_date,'DD-Mon-YYYY HH:MI AM')
               || '","by":"' || l_perf_name || '"}';
        l_first := FALSE;
    END LOOP;
    CLOSE v_cursor;
    l_json := l_json || ']';
    HTP.P(l_json);
END;
```

### LOV: FUND_LOV
```sql
SELECT FUND_NAME AS D, FUND_ID AS R FROM EPF_FUNDS WHERE IS_ACTIVE = 'Y' ORDER BY FUND_NAME
```

### LOV: COMPANY_GROUP_LOV
```sql
SELECT GROUP_NAME AS D, GROUP_ID AS R FROM EPF_COMPANY_GROUPS ORDER BY GROUP_NAME
```

### LOV: ROLE_CODE_LOV (Corp Admin scope)
```sql
SELECT ROLE_NAME AS D, ROLE_CODE AS R FROM EPF_ROLES
 WHERE ROLE_CODE IN ('CORP_MAKER','CORP_CHECKER') ORDER BY ROLE_NAME
```

### LOV: PERIOD_TYPE_LOV (Employee Account Statement)
```sql
SELECT 'Last 30 Days'   AS D, 'LAST30'     AS R FROM DUAL UNION ALL
SELECT 'Last 90 Days',          'LAST90'            FROM DUAL UNION ALL
SELECT 'From Inception',        'INCEPTION'         FROM DUAL UNION ALL
SELECT 'Date Range',            'DATE_RANGE'        FROM DUAL
```

### CSS: Status Badge Classes
```css
.epf-badge-success  { background-color: #28a745; color: #fff; padding: 2px 8px; border-radius: 12px; }
.epf-badge-danger   { background-color: #dc3545; color: #fff; padding: 2px 8px; border-radius: 12px; }
.epf-badge-warning  { background-color: #ffc107; color: #212529; padding: 2px 8px; border-radius: 12px; }
.epf-badge-info     { background-color: #17a2b8; color: #fff; padding: 2px 8px; border-radius: 12px; }
.epf-badge-neutral  { background-color: #6c757d; color: #fff; padding: 2px 8px; border-radius: 12px; }
.epf-row-greyed     { opacity: 0.5; pointer-events: none; }
```

Add to **Shared Components → User Interface Attributes → CSS**.

---

## 15. Status Code Reference

### Category: CLIENT_STATUS

| Code | Display | CSS Class | Meaning |
|---|---|---|---|
| `DRAFT` | Draft | epf-badge-neutral | Onboarding started, not submitted |
| `PENDING_CHECKER` | Pending Review | epf-badge-warning | Submitted, awaiting AAML Checker |
| `ACTIVE` | Active | epf-badge-success | Approved and live |
| `REJECTED` | Rejected | epf-badge-danger | Hard rejected by Checker |
| `REVERTED` | Reverted | epf-badge-warning | Sent back to Maker for changes |

### Category: USER_STATUS

| Code | Display | CSS Class | Meaning |
|---|---|---|---|
| `PENDING` | Pending | epf-badge-warning | User created, not approved |
| `PENDING_CHECKER` | Pending Checker | epf-badge-warning | Submitted with client |
| `ACTIVE` | Active | epf-badge-success | Live |
| `INACTIVE` | Inactive | epf-badge-neutral | Deactivated |
| `BLOCKED` | Blocked | epf-badge-danger | Account locked |
| `DELETED` | Deleted | epf-badge-danger | Soft-deleted |

### Category: REQUEST

| Code | Display | CSS Class | Meaning |
|---|---|---|---|
| `PENDING_MAKER` | Pending at Maker | epf-badge-info | Employee-created; waiting for Maker |
| `PENDING_CHECKER` | Pending at Checker | epf-badge-warning | Maker submitted; waiting for Checker |
| `PENDING_AUTHORIZER` | Pending Authorization | epf-badge-warning | Checker approved; waiting for Authorizer(s) |
| `AUTHORIZED` | Authorized | epf-badge-success | All Authorizers approved |
| `REJECTED` | Rejected | epf-badge-danger | Rejected at any stage |
| `COMPLETED` | Completed | epf-badge-success | AAML posted to DFN |
| `PENDING_AAML` | Pending at AAML | epf-badge-info | In AAML queue for DFN posting |

### Category: CHANGE_REQ_STATUS

| Code | Meaning |
|---|---|
| `DRAFT` | CR started by Maker |
| `PENDING_CHECKER` | Submitted for Checker review |
| `APPROVED` | Applied to live data |
| `REVERTED` | Sent back to Maker |
| `REJECTED` | Hard rejected |

---

## 16. Email Reference

**Package:** `EPF_EMAIL_PKG`  
All emails use `APEX_MAIL.SEND` and log to `EPF_EMAIL_LOGS`.

| # | Procedure | Subject | Trigger |
|---|---|---|---|
| 1 | `SEND_WELCOME_EMAIL` | Welcome to EPF Portal | New user created |
| 2 | `SEND_FORGOT_PWD_EMAIL` | Reset your password | Forgot password flow |
| 3 | `SEND_OTP_EMAIL` | Your OTP code | Password change / reset |
| 4 | `SEND_UNBLOCK_EMAIL` | Account Unblocked | Admin unblocks user |
| 5 | `SEND_DEACTIVATE_EMAIL` | Account Deactivated | Admin deactivates user |
| 6 | `SEND_PWD_CHANGED_EMAIL` | Password Changed | Successful password change |
| 8 | `SEND_UNSUCCESSFUL_LOGIN_EMAIL` | Unsuccessful Login Attempt | Bad password login |
| 9 | `SEND_SUCCESSFUL_LOGIN_EMAIL` | Successful Login | Every successful login |
| 16 | `SEND_TASK_REJECTED_EMAIL` | [Type] Request is Rejected | Any rejection |
| 19 | `SEND_REQUEST_PENDING_EMAIL` | [Type] Request is pending approval | Request lands at approver |
| 20 | `SEND_REQUEST_COMPLETED_EMAIL` | [Type] Request is Completed | All authorizers approved |
| 21 | `SEND_ACCOUNT_STATEMENT_EMAIL` | Your Account Statement | Employee requests statement email |

**Base URL Config:** Stored in `EPF_API_CONFIG` table, `CONFIG_KEY = 'APP_BASE_URL'`.  
**Password link format:** `{BASE_URL}/f?p=EPF:9902:::::P9902_TOKEN:{token}`

---

## 17. FSD Narration Formats

All narrations stored in `EPF_ACTIVITY_LOG.REMARKS`. Tag appended: `[Ref TYPE-ID]`.

### AAML Client Onboarding
```
Client [Company Name] created by AAML Maker [Name] on DD-Mon-YY, at HH:MI am
Client [Company Name] submitted for review by AAML Maker [Name] on DD-Mon-YY, at HH:MI am
Client [Company Name] approved by AAML Checker [Name] on DD-Mon-YY, at HH:MI am
Client [Company Name] reverted by AAML Checker [Name] on DD-Mon-YY, at HH:MI am
Client [Company Name] rejected by AAML Checker [Name] on DD-Mon-YY, at HH:MI am
```

### Corp Admin User Management
```
User created by Admin [Name] on DD-Mon-YY, at HH:MI am
User [field] updated by Admin [Name] on DD-Mon-YY, at HH:MI am
User deleted by Admin [Name] on DD-Mon-YY, at HH:MI am
Account unblocked by Admin [Name] on DD-Mon-YY, at HH:MI am
Account deactivated by Admin [Name] on DD-Mon-YY, at HH:MI am
```

### Corp Maker / Checker / Authorizer Transactions
| Code | Format |
|---|---|
| 2.1 | `[Name and Role]: Created contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 2.2/2.3 | `[Name and Role]: Approved contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 2.6a | `[Name and Role]: Rejected contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 3.1 | `[Name and Role]: Created loan request on [DD-Mon-YY], at [HH:MI am]` |
| 3.2/3.3 | `[Name and Role]: Approved loan request on [DD-Mon-YY], at [HH:MI am]` |
| 3.6a | `[Name and Role]: Rejected loan request on [DD-Mon-YY], at [HH:MI am]` |
| 4.1 | `[Name and Role]: Created withdrawal request on [DD-Mon-YY], at [HH:MI am]` |
| 4.3 | `[Name and Role]: Approved withdrawal request on [DD-Mon-YY], at [HH:MI am]` |
| 4.6a | `[Name and Role]: Rejected withdrawal request on [DD-Mon-YY], at [HH:MI am]` |
| 5.3 | `[Name and Role]: Approved lien marking request on [DD-Mon-YY], at [HH:MI am]` |
| 6.3a | `[Name and Role]: Approved lien unmarking request on [DD-Mon-YY], at [HH:MI am]` |
| 7.3 | `[Name and Role]: Approved NOC issuance request on [DD-Mon-YY], at [HH:MI am]` |
| 9.6 | `Loan Settings were [approved/rejected] by Authorizer [Name] (Interest Type: ...) on [DD-Mon-YY]` |

---

## 18. Master Implementation Checklist

### Phase 1 — Database
- [ ] Run `@db/install_all.sql` in SQL*Plus
- [ ] Run `@db/verify_all.sql` — confirm all VALID, no `*** INVALID ***` rows
- [ ] Confirm `EPF_PKG_AUTH` PACKAGE + PACKAGE BODY = VALID
- [ ] Confirm `EPF_CORP_TXN_PKG` PACKAGE + PACKAGE BODY = VALID
- [ ] Seed status categories: `CLIENT_STATUS`, `USER_STATUS`, `REQUEST`, `CHANGE_REQ_STATUS`
- [ ] Verify views: `V_EPF_LOAN_REQUESTS`, `V_EPF_WITHDRAWAL_REQUESTS` — no ORA-00904

### Phase 2 — APEX App Shared Components
- [ ] Create all Application Items (Section 3.4)
- [ ] Set Authentication Scheme to EPF Custom Auth (Section 3.1)
- [ ] Add Post-Authentication Procedure `EPF_POST_AUTH`
- [ ] Add Application Process `SET_SESSION_DETAILS` (On New Instance)
- [ ] Create all Authorization Schemes (Section 4)
- [ ] Create LOVs: FUND_LOV, COMPANY_GROUP_LOV, ROLE_CODE_LOV, PERIOD_TYPE_LOV
- [ ] Add CSS badge classes to app CSS
- [ ] Register On-Demand App Processes: `GET_REQUEST_HISTORY_AJAX`, `GET_USER_JSON`, `GET_USER_HISTORY`, `CHECKER_APPROVE_AJAX`, `CHECKER_REVERT_AJAX`, `CR_CHECKER_APPROVE_AJAX`, `CR_CHECKER_REVERT_AJAX`, `LOAD_GROUP_AJAX`

### Phase 3 — Auth / Password Pages
- [ ] Page 9999 — Login (items, processes, branches)
- [ ] Page 9901 — Forgot Password
- [ ] Page 9902 — Set/Reset Password
- [ ] Page 9903 — Change Password

### Phase 4 — AAML Pages
- [ ] Page 10 — Maker Dashboard (IR + CREATE button)
- [ ] Page 4 — Onboarding Wizard (4 tabs, all processes)
- [ ] Page 11 — Search Clients
- [ ] Page 12 — User Management (all companies)
- [ ] Page 13 — Company User Management
- [ ] Page 14 — Change Request History
- [ ] Page 15 — Maker CR Form (sections + submit)
- [ ] Page 20 — Checker Dashboard (stats + unified queue IR)
- [ ] Page 22 — Client Detail Review (approve/revert/reject)
- [ ] Page 23 — CR Review (approve/revert)
- [ ] Pages 200–207 — AAML Admin pages
- [ ] Pages 210–215 — AAML Ops queue pages

### Phase 5 — Corp Admin
- [ ] Page 30 — User Management (create/edit/delete/history)
- [ ] Fix DELETE USERS process (use EPF_USER_COMP_ROLES, not EPF_USERS_ROLES)

### Phase 6 — Corp Maker
- [ ] Page 40 — Contribution Upload Wizard
- [ ] Page 41 — Loan Request Wizard
- [ ] Page 42 — Withdrawal Request Wizard
- [ ] Page 43 — Lien Mark/Unmark
- [ ] Page 44 — NOC Issuance
- [ ] Page 45 — Disable Employees

### Phase 7 — Corp Checker
- [ ] Page 50 — Check Contribution Uploads
- [ ] Page 51 — Check Loan Requests
- [ ] Page 52 — Check Withdrawal Requests
- [ ] Page 53 — Check Lien Requests
- [ ] Page 54 — Check NOC Requests
- [ ] Page 55 — Check Disable Requests
- [ ] Page 60 — Settings (Feature Access + Realloc Groups)

### Phase 8 — Corp Authorizer
- [ ] Page 70 — Pending Count Dashboard
- [ ] Page 71 — Authorize Contribution Uploads
- [ ] Page 72 — Authorize Loan Requests
- [ ] Page 73 — Authorize Withdrawal Requests
- [ ] Page 74 — Authorize Lien Requests
- [ ] Page 75 — Authorize NOC Requests
- [ ] Page 76 — Loan Settings Authorization

### Phase 9 — Employee Self-Service
- [ ] Set `APP_FOLIO_ID` in POST_AUTH_SETUP for EMPLOYEE role
- [ ] Page 80 — Dashboard (fund table + chart + date filter)
- [ ] Page 81 — Account Statement (view + email)
- [ ] Page 82 — Tax Certificates
- [ ] Page 83 — Portfolio Reallocation
- [ ] Page 84 — Create Loan Request (3-step)
- [ ] Page 85 — Create Withdrawal Request (3-step)

### Phase 10 — Testing
- [ ] AAML Maker: create client → all 4 tabs → submit
- [ ] AAML Checker: approve → client goes ACTIVE, welcome emails sent
- [ ] AAML Checker: revert → Maker gets notification, can re-edit
- [ ] AAML Checker: reject → permanent REJECTED
- [ ] Corp Admin: create CORP_MAKER + CORP_CHECKER users
- [ ] Corp Maker: contribution upload → batch created → Checker page shows it
- [ ] Corp Checker: approve → moves to PENDING_AUTHORIZER
- [ ] Corp Authorizer: all approve → AUTHORIZED → AAML Queue populated
- [ ] Employee: create loan → appears in Corp Maker's PENDING_MAKER queue
- [ ] Password flows: forgot pwd → token link → OTP → reset
- [ ] Force-pwd-change: new user → login → redirected to 9903

---

*Guide generated: 22-Jun-2026. Based on EPF Portal App ID 51534, APEX 24.2.17, Oracle 19c.*  
*DB scripts: db/00 through db/20. Apex files: apex/ subdirectories.*
