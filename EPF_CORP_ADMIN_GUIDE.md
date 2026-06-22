# EPF Portal – Corporate Admin Module: Development Guide

## Overview

This guide covers the complete implementation of the Corporate Admin role in the EPF Portal (Oracle APEX App ID: f136). It includes database objects, PL/SQL packages, APEX pages, and all supporting authentication/email functionality.

---

## 1. Database Objects (`db/07_corp_admin_ddl.sql`)

Run once, in order, after `01_ddl_new_objects.sql`.

| Object | Purpose |
|--------|---------|
| `EPF_PASSWORD_TOKENS` | Stores set-password and reset-password tokens |
| `EPF_OTP_REQUESTS` | Stores OTP codes for pwd change, forgot pwd, and MFA |
| `ACT_LOG_REF_SEQ` | Sequence for activity log reference numbers |
| `EPF_ACTIVITY_LOGS` | Full audit trail for all user actions |
| `EPF_EMAIL_LOGS` | Email delivery audit trail |

### Token Purposes
- `SET_PASSWORD` — welcome email for new users; `EXPIRES_AT = NULL` (single-use, no time limit)
- `RESET_PASSWORD` — forgot-password flow; `EXPIRES_AT = SYSDATE + 2/24` (2-hour expiry)

### OTP Purposes
- `PWD_CHANGE` — change password flow
- `FORGOT_PWD` — reset password after token validation
- `LOGIN_MFA` — future login 2FA (reserved)

---

## 2. Email Package (`db/08_epf_email_pkg.sql`)

**Package:** `EPF_EMAIL_PKG`

All emails use `APEX_MAIL.SEND` with HTML body and automatically log to `EPF_EMAIL_LOGS`.

| Procedure | Trigger |
|-----------|---------|
| `SEND_WELCOME_EMAIL(user_id, token)` | New user created |
| `SEND_FORGOT_PWD_EMAIL(user_id, token)` | Forgot password requested |
| `SEND_OTP_EMAIL(user_id, otp, purpose)` | Password change/reset OTP |
| `SEND_UNBLOCK_EMAIL(user_id, unblocked_by_name)` | User unblocked by Admin |
| `SEND_DEACTIVATE_EMAIL(user_id)` | User deactivated by Admin |
| `SEND_PWD_CHANGED_EMAIL(user_id)` | Password successfully changed |

### Base URL Configuration
Stored in `EPF_API_CONFIG` table, `CONFIG_KEY = 'APP_BASE_URL'`.
Password links format: `{BASE_URL}/f?p=EPF:9902:::::P9902_TOKEN:{token}`

---

## 3. Authentication Package (`db/09_epf_auth_pkg.sql`)

**Package:** `EPF_AUTH_PKG`

### Procedures & Functions

| Name | Purpose |
|------|---------|
| `AUTHENTICATE(email, pwd, session_id, ...)` | Login with brute-force protection |
| `FORGOT_PASSWORD(email, ip, ...)` | Initiate password reset (always returns Y) |
| `VALIDATE_RESET_TOKEN(token)` | Returns `USER_ID` or `0` |
| `SET_NEW_PASSWORD_REQUEST(user_id, ...)` | Validate new pwd + send OTP (from reset link) |
| `CONFIRM_OTP_AND_SET_PASSWORD(user_id, otp, token, ...)` | Complete reset after OTP |
| `CHANGE_PASSWORD(user_id, current_pwd, ...)` | Change pwd from profile (verify current first) |
| `CONFIRM_OTP_CHANGE_PASSWORD(user_id, otp, ...)` | Complete change after OTP |
| `RESEND_OTP(user_id, purpose, ...)` | Resend OTP (max 4 resends) |
| `SET_FIRST_PASSWORD_TOKEN(user_id, ip)` | Called on user creation; sends welcome email |
| `LOG_ACTIVITY(user_id, company_id, ucid, action_code, detail, page)` | Write to `EPF_ACTIVITY_LOGS` |

### Security Rules
- **Login:** 5 wrong passwords → account blocked
- **OTP:** 5 wrong OTP attempts → account blocked
- **OTP Resend:** max 4 resends; 5th attempt → account blocked
- **Forgot Password:** always returns success (prevents email enumeration)
- **Password Policy:** min 8 chars, 1 upper, 1 lower, 1 digit, 1 special char
- **Hashing:** DBMS_CRYPTO SHA-512 with random 32-byte salt

---

## 4. Corporate Admin Package (`db/10_epf_corp_admin_pkg.sql`)

**Package:** `EPF_CORP_ADMIN_PKG`

### Procedures & Functions

| Name | Purpose |
|------|---------|
| `CREATE_USER(company_id, admin_ucid, role_code, name, email, mobile, emp_code, ...)` | Create Maker/Checker |
| `UPDATE_USER(ucid, admin_ucid, role, name, mobile, emp_code, status, ...)` | Update Maker/Checker |
| `DELETE_USERS(ucids_colon_separated, admin_ucid, ...)` | Soft-delete multiple users |
| `GET_USER_HISTORY(ucid)` | Returns SYS_REFCURSOR of activity log |

### Role Scope
Corporate Admin can **only** create and manage:
- `CORP_MAKER`
- `CORP_CHECKER`

> **CORP_ADMIN** and **CORP_AUTHORIZER** are created by AAML Maker — outside the Admin's scope.

### Create User Validations
1. Role must be `CORP_MAKER` or `CORP_CHECKER`
2. Full Name: alphabets and spaces only (`REGEXP_LIKE`)
3. Email: valid format with `@` and domain
4. Mobile: numeric digits only
5. Duplicate check: same role cannot exist for same company (active record)
6. If email belongs to an existing Authorizer → add role to that user (no new `EPF_USERS` row)

### Activity Log Narration Format (FSD-exact)
```
Created: "User created by Admin [Name] on DD-Mon-YY, at HH:MI am"
Updated: "User [field] updated by Admin [Name] on DD-Mon-YY, at HH:MI am"
Deleted: "User deleted by Admin [Name] on DD-Mon-YY, at HH:MI am"
Unblocked: "Account unblocked by Admin [Name] on DD-Mon-YY, at HH:MI am"
Deactivated: "Account deactivated by Admin [Name] on DD-Mon-YY, at HH:MI am"
```

---

## 5. APEX Pages

### Page 30 — User Management

**Authentication:** Required (Corporate Admin role)

**Page Items (Hidden):**
| Item | Purpose |
|------|---------|
| `P30_ROLE_CODE` | New user role |
| `P30_FULL_NAME` | New user name |
| `P30_EMAIL` | New user email |
| `P30_MOBILE_NO` | New user mobile |
| `P30_EMPLOYEE_CODE` | New user emp code |
| `P30_CREATED_USER_ID` | Output: newly created user ID |
| `P30_SUCCESS_MSG` | Output: success message |
| `P30_EDIT_USER_COMPANY_ID` | Target UCID for edit |
| `P30_EDIT_ROLE_CODE` | Edit: role |
| `P30_EDIT_FULL_NAME` | Edit: name |
| `P30_EDIT_MOBILE_NO` | Edit: mobile |
| `P30_EDIT_EMPLOYEE_CODE` | Edit: emp code |
| `P30_EDIT_STATUS_CODE` | Edit: status |
| `P30_SELECTED_USER_IDS` | Colon-separated UCIDs for delete |
| `P30_HISTORY_USER_COMPANY_ID` | Target UCID for history popup |

**Processes (see `apex/corp_admin/page_processes.sql`):**
- `CORP_ADMIN_CREATE_USER` → Request = `CREATE_USER`
- `CORP_ADMIN_UPDATE_USER` → Request = `UPDATE_USER`
- `CORP_ADMIN_DELETE_USERS` → Request = `DELETE_USERS`

**Application Process (`GET_USER_JSON`):** Returns JSON for Edit popup population.
**Application Process (`GET_USER_HISTORY`):** Returns JSON array for History popup.

**IR Source:** See `apex/corp_admin/ir_queries.sql` — User Management section.

---

### Page 9901 — Forgot Password

**Authentication:** None (public page)

| Item | Purpose |
|------|---------|
| `P9901_EMAIL` | User enters email |
| `P9901_SUCCESS_MSG` | Set to `'Y'` after submit |

**Process:** `FORGOT_PASSWORD` → Request = `FORGOT_PASSWORD`
- Calls `EPF_AUTH_PKG.FORGOT_PASSWORD`
- Always sets `P9901_SUCCESS_MSG = 'Y'` (security)

---

### Page 9902 — Set / Reset Password

**Authentication:** None (public page; authenticated via token)

| Item | Purpose |
|------|---------|
| `P9902_TOKEN` | URL parameter (token from email link) |
| `P9902_USER_ID` | Resolved from token on page load |
| `P9902_NEW_PASSWORD` | New password input |
| `P9902_CONFIRM_PASSWORD` | Confirm password input |
| `P9902_OTP_SENT` | `'Y'` after step 1; shows OTP panel |
| `P9902_OTP_CODE` | 6-digit OTP from user |

**Processes:**
- `VALIDATE_TOKEN` (page load, before header) → `EPF_AUTH_PKG.VALIDATE_RESET_TOKEN`; redirect to login if returns 0
- `SET_PASSWORD_REQUEST` → Request = `SET_PASSWORD_REQUEST`
- `CONFIRM_SET_PASSWORD` → Request = `CONFIRM_SET_PASSWORD`
- `RESEND_OTP` → Request = `RESEND_OTP`

---

### Page 9903 — Change Password

**Authentication:** Required

| Item | Purpose |
|------|---------|
| `P9903_CURRENT_PASSWORD` | Current password |
| `P9903_NEW_PASSWORD` | New password |
| `P9903_CONFIRM_PASSWORD` | Confirm new password |
| `P9903_OTP_SENT` | `'Y'` after step 1 |
| `P9903_OTP_CODE` | 6-digit OTP |

**Processes:**
- `CHANGE_PASSWORD_REQUEST` → Request = `CHANGE_PASSWORD_REQUEST`
- `CONFIRM_CHANGE_PASSWORD` → Request = `CONFIRM_CHANGE_PASSWORD`
- `RESEND_OTP_CHG` → Request = `RESEND_OTP_CHG`

---

## 6. Status Lookup Rules

**Always use `EPF_STATUS_PKG` — never hardcode Status IDs.**

```sql
-- Get status ID from code
v_status_id := EPF_STATUS_PKG.GET_ID('USER', 'ACTIVE');

-- Get code from ID
v_code := EPF_STATUS_PKG.GET_CODE(v_status_id);
```

Status codes used in this module:
- `ACTIVE`, `INACTIVE`, `BLOCKED`, `DELETED`

---

## 7. Run Order

```
1.  db/01_ddl_new_objects.sql      (existing — run once)
2.  db/07_corp_admin_ddl.sql       (new tables + sequence)
3.  db/08_epf_email_pkg.sql        (EPF_EMAIL_PKG)
4.  db/09_epf_auth_pkg.sql         (EPF_AUTH_PKG)
5.  db/10_epf_corp_admin_pkg.sql   (EPF_CORP_ADMIN_PKG)
```

---

## 8. File Inventory

| File | Description |
|------|-------------|
| `db/07_corp_admin_ddl.sql` | DDL: tables, sequence, indexes |
| `db/08_epf_email_pkg.sql` | Email package (spec + body) |
| `db/09_epf_auth_pkg.sql` | Authentication package (spec + body) |
| `db/10_epf_corp_admin_pkg.sql` | Corporate Admin package (spec + body) |
| `apex/corp_admin/page_processes.sql` | APEX PL/SQL processes for pages 30, 9901, 9902, 9903 |
| `apex/corp_admin/ir_queries.sql` | IR queries, history query, and LOVs |
| `apex/corp_admin/html_templates.html` | HTML/CSS/JS for all 4 pages |
| `demo_data/epf_demo_employees.sql` | 100-row demo employee INSERT script |
| `demo_data/epf_demo_employees.csv` | CSV version of demo data |

---

## 9. Key Design Decisions

1. **Dual activity logging:** Every Admin action is logged for both the Admin (by `APP_USER_COMPANY_ID`) and the target user (by `USER_COMPANY_ID`), so both parties see the event in their own activity log.

2. **Soft delete only:** Users are never physically deleted. `STATUS = 'DELETED'`, `IS_ACTIVE = 'N'`.

3. **Unblock via Status change:** Setting status to `ACTIVE` in Edit User automatically resets `ACCOUNT_LOCKED = 'N'` and `FAILED_LOGIN_COUNT = 0`, and sends an unblock notification email.

4. **Single-use welcome tokens:** `EXPIRES_AT = NULL` in `EPF_PASSWORD_TOKENS` means the token has no time expiry but is invalidated on first use (`USED_YN = 'Y'`).

5. **OTP 5-minute expiry:** `EXPIRES_AT = SYSDATE + (5/1440)` in `EPF_OTP_REQUESTS`.

6. **Security on forgot password:** The procedure always returns `p_out_success = 'Y'` and a generic message to prevent email enumeration attacks.

