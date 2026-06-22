# EPF Portal – Authorizer & Employee Module: Development Guide

## Overview

This guide covers the complete implementation of the **Corporate Authorizer** role and the **Employee** self-service portal in the EPF Portal (Oracle APEX App ID: f136). It includes new DB objects, the `EPF_AUTHORIZER_PKG` and `EPF_EMPLOYEE_PKG` PL/SQL packages, email addons in `EPF_EMAIL_PKG`, and APEX pages 70–76 (Authorizer) and 80–85 (Employee).

It implements FSD validations **#336–345 (Authorizer)** and **#346–372 (Employee)**: Authorize Requests (Contribution Uploads, Loans, Withdrawals, Lien, NOC), Loan Settings Authorization, Employee Dashboard, Account Statement, Tax Certificates, Portfolio Reallocation, and Loan/Withdrawal request creation by employees.

---

## Run Order

Run scripts in this exact order after db/01–12 are applied:

| Order | File | Purpose |
|-------|------|---------|
| 1 | `db/13_authorizer_employee_ddl.sql` | New tables, guarded ALTERs, status seeds |
| 2 | `db/14_epf_email_pkg_addons.sql` | Full EPF_EMAIL_PKG rewrite (6 original + 6 new) |
| 3 | `db/15_epf_authorizer_pkg.sql` | EPF_AUTHORIZER_PKG |
| 4 | `db/16_epf_employee_pkg.sql` | EPF_EMPLOYEE_PKG |
| 5 | APEX import (pages 70–76) | `apex/corp_authorizer/` |
| 6 | APEX import (pages 80–85) | `apex/employee/` |

---

## 1. Database Objects (`db/13_authorizer_employee_ddl.sql`)

### New Tables

| Table | Purpose |
|-------|---------|
| `EPF_AUTHORIZER_DECISIONS` | Per-authorizer approve/reject decisions for multi-authorizer workflow |
| `EPF_AAML_QUEUE` | Authorized requests queued for AAML transaction posting in DFN |
| `EPF_REALLOC_REQUESTS` | Employee portfolio reallocation requests; direct to DFN |
| `EPF_ACCOUNT_STMT_LOG` | Audit log for account statement views and email requests |

### Guarded ALTER TABLE Additions

| Table | Columns Added |
|-------|--------------|
| `EPF_CONTRIB_BATCHES` | `AUTHORIZER_COUNT`, `AUTHORIZER_APPROVED_COUNT` |
| `EPF_LOAN_REQUESTS` | `AUTHORIZER_COUNT`, `AUTHORIZER_APPROVED_COUNT`, `CREATED_BY_EMPLOYEE_YN`, `PAYMENT_MODE` |
| `EPF_WITHDRAWAL_REQUESTS` | `AUTHORIZER_COUNT`, `AUTHORIZER_APPROVED_COUNT`, `CREATED_BY_EMPLOYEE_YN`, `PAYMENT_MODE` |
| `EPF_LIEN_REQUESTS` | `AUTHORIZER_COUNT`, `AUTHORIZER_APPROVED_COUNT` |
| `EPF_NOC_REQUESTS` | `AUTHORIZER_COUNT`, `AUTHORIZER_APPROVED_COUNT` |
| `EPF_COMPANY_SETTINGS` | `PENDING_*` loan settings columns, `LOAN_SETTINGS_STATUS`, `LOAN_SETTINGS_MAKER/CHECKER_UCID/DATE` |

### Status Seeds (MERGE, idempotent)

| Category | Code | Display |
|----------|------|---------|
| `REQUEST` | `PENDING_MAKER` | Pending at Maker |
| `REQUEST` | `COMPLETED` | Completed |
| `REQUEST` | `PENDING_AAML` | Pending at AAML |

---

## 2. Email Package (`db/14_epf_email_pkg_addons.sql`)

**Package:** `EPF_EMAIL_PKG` (full rewrite — canonical version replacing db/08)

### Existing Procedures (preserved verbatim)

| Procedure | Purpose |
|-----------|---------|
| `SEND_WELCOME_EMAIL(user_id, token)` | Welcome + set-password link |
| `SEND_FORGOT_PWD_EMAIL(user_id, token)` | Password reset link (2h expiry) |
| `SEND_OTP_EMAIL(user_id, otp, purpose)` | OTP for pwd change / login MFA |
| `SEND_UNBLOCK_EMAIL(user_id, unblocked_by_name)` | Account unblocked notification |
| `SEND_DEACTIVATE_EMAIL(user_id)` | Account deactivated notification |
| `SEND_PWD_CHANGED_EMAIL(user_id)` | Password changed confirmation |

### New Procedures

| Procedure | FSD # | Subject |
|-----------|-------|---------|
| `SEND_UNSUCCESSFUL_LOGIN_EMAIL(user_id)` | #8 | Unsuccessful Login Attempt on EPF Platform |
| `SEND_SUCCESSFUL_LOGIN_EMAIL(user_id)` | #9 | Successful Login on EPF Platform |
| `SEND_TASK_REJECTED_EMAIL(maker_user_id, request_type, ref_no, remarks, rejected_by_name)` | #16 | [Request Type] Request is Rejected |
| `SEND_REQUEST_PENDING_EMAIL(approver_user_id, request_type, ref_no, created_by, created_on)` | #19 | [Request Type] Request is pending approval |
| `SEND_REQUEST_COMPLETED_EMAIL(maker_user_id, request_type, ref_no, created_on)` | #20 | [Request Type] Request is Completed |
| `SEND_ACCOUNT_STATEMENT_EMAIL(employee_user_id, folio, fund_name, date_from, date_to, attachment BLOB)` | #21 | Your Account Statement from EPF Platform |

---

## 3. Authorizer Package (`db/15_epf_authorizer_pkg.sql`)

**Package:** `EPF_AUTHORIZER_PKG`

### Private Helpers

| Name | Purpose |
|------|---------|
| `GET_AUTHORIZER_COUNT(company_id)` | Count of active CORP_AUTHORIZER role users for a company |
| `GET_APPROVAL_COUNT(request_type, request_id)` | Count of APPROVE decisions for a request |
| `GET_ACTOR_NAME(ucid)` | FULL_NAME for a USER_COMPANY_ID |
| `GET_ACTOR_EMAIL(ucid)` | EMAIL for a USER_COMPANY_ID |
| `GET_ACTOR_ROLE_LABEL(ucid)` | Role display label (e.g. 'authorizer') |
| `GET_MAKER_USER_ID(request_type, request_id)` | USER_ID of request creator |
| `GET_REQUEST_REF_NO(request_type, request_id)` | Reference number string |
| `GET_COMPANY_ID_FOR_REQUEST(request_type, request_id)` | COMPANY_ID for any request type |
| `NARRATE(company_id, ucid, action_code, narration, ref_type, ref_id)` | Autonomous FSD narration insert |
| `NOTIFY_UCID(company_id, ucid, title, message, ref_type, ref_id)` | Autonomous notification insert |
| `SEND_ACTION_REQUIRED(request_type, request_id, company_id, actor_ucid)` | Write Action Required narrations per pending authorizer + email #19 |
| `UPDATE_REQUEST_STATUS(request_type, request_id, status_code, authorizer_ucid)` | Update STATUS_ID on target table |
| `APPLY_AUTHORIZATION_SIDE_EFFECTS(request_type, request_id, company_id)` | Apply folio flags + queue to EPF_AAML_QUEUE |

### Public API

| Procedure / Function | Purpose |
|---------------------|---------|
| `AUTHORIZE_REQUEST(request_type, request_id, authorizer_ucid, decision, remarks, out_success, out_message)` | Core multi-authorizer decision. APPROVE: logs decision, checks if all approved → AUTHORIZED + AAML queue + email #20; or sends Action Required to remaining authorizers. REJECT: STATUS=REJECTED + email #16 |
| `AUTHORIZE_LOAN_SETTINGS(company_id, authorizer_ucid, decision, remarks, out_success, out_message)` | Approves/rejects pending loan settings; APPROVE copies pending→live columns; narration 9.6 |
| `GET_REQUEST_HISTORY(ref_type, ref_id)` | SYS_REFCURSOR from EPF_ACTIVITY_LOGS matching `[Ref TYPE-ID]` tag |
| `GET_AUTHORIZER_DECISIONS(request_type, request_id)` | SYS_REFCURSOR of all authorizers + their decision status (PENDING/APPROVE/REJECT) |

---

## 4. Employee Package (`db/16_epf_employee_pkg.sql`)

**Package:** `EPF_EMPLOYEE_PKG`

### Private Helpers

| Name | Purpose |
|------|---------|
| `GET_FOLIO_INFO(folio_id, ...)` | Resolve company_id, fund_id, folio_no, lien/disabled/noc flags, user_id |
| `GET_EMPLOYEE_NAME(folio_id)` | Employee FULL_NAME |
| `GET_MAKER_UCID_FOR_COMPANY(company_id)` | First active CORP_MAKER for company (to notify of employee requests) |
| `NARRATE_EMPLOYEE(company_id, user_id, action_code, narration, ref_type, ref_id)` | Autonomous activity log insert |
| `NOTIFY_USER_ID(company_id, user_id, title, message, ref_type, ref_id)` | Autonomous notification insert |
| `COMPUTE_DATE_RANGE(period_type, date_from_in, date_to_in, date_from, date_to)` | Resolve LAST30/LAST90/INCEPTION/DATE_RANGE into actual dates |

### Public API

| Procedure / Function | FSD | Purpose |
|---------------------|-----|---------|
| `GET_DASHBOARD_DATA(folio_id, date_from, date_to)` | #346-350 | SYS_REFCURSOR of sub-fund rows: FUND_NAME, SUBFUND_NAME, UNITS, NAV, CURRENT_BALANCE, NET_INVESTMENT, PROFIT_LOSS |
| `GET_ACCOUNT_STATEMENT(folio_id, period_type, date_from, date_to)` | #351-352 | SYS_REFCURSOR of transactions; logs VIEW to EPF_ACCOUNT_STMT_LOG |
| `REQUEST_ACCOUNT_STATEMENT_EMAIL(user_id, folio_id, fund_id, date_from, date_to, out_success, out_message)` | #353 | Sends email #21; logs EMAIL to EPF_ACCOUNT_STMT_LOG |
| `GENERATE_TAX_CERTIFICATE(user_id, folio_id, tax_year, out_html, out_success, out_message)` | #354-355 | Builds styled HTML certificate (stub pending DFN integration) |
| `CREATE_PORTFOLIO_REALLOC(folio_id, group_id, mm_pct, debt_pct, equity_pct, out_success, out_message)` | #356-358 | Validates limits/membership; inserts EPF_REALLOC_REQUESTS |
| `CREATE_LOAN_REQUEST(folio_id, amount, instalment_months, payment_mode, out_success, out_message, out_loan_id)` | #359-364 | Validates feature enabled, limits, lien/disabled/NOC; creates PENDING_MAKER loan; narration 3.1; notifies Maker |
| `CREATE_WITHDRAWAL_REQUEST(folio_id, amount, wd_type, reason, payment_mode, out_success, out_message, out_wd_id)` | #365-369 | Same pattern for withdrawals; PENDING_MAKER status; narration 4.1 |

---

## 5. Multi-Authorizer Workflow

### Decision Flow

```
Maker creates request
       ↓
STATUS = PENDING_CHECKER (or PENDING_AUTHORIZER if no Checker)
       ↓
Checker approves → STATUS = PENDING_AUTHORIZER
       ↓
EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST called for each Authorizer
  ├─ Insert EPF_AUTHORIZER_DECISIONS (APPROVE)
  ├─ AUTHORIZER_APPROVED_COUNT ++
  ├─ If count < required: write Action Required narrations, email #19 to remaining
  └─ If count >= required:
       → STATUS = AUTHORIZED
       → Apply side effects (LIEN_MARKED, NOC_ISSUED flags)
       → Insert EPF_AAML_QUEUE (PENDING)
       → Email #20 (Request Completed) to Maker
  
  OR: REJECT
       → STATUS = REJECTED
       → Email #16 (Task Rejected) to Maker
       
EPF_AAML_QUEUE.STATUS = PENDING
       ↓
AAML Maker posts to DFN → PROCESSED
       ↓
STATUS = COMPLETED
```

### Key Rules (FSD #90-94)

- One Authorizer cannot exist in multiple groups.
- ALL active Authorizers of the company must approve before status = AUTHORIZED.
- `GET_AUTHORIZER_COUNT` queries `EPF_USER_COMP_ROLES` for `CORP_AUTHORIZER` role with `IS_ACTIVE='Y'` and user status `ACTIVE`.
- Per-authorizer decision tracked in `EPF_AUTHORIZER_DECISIONS` with unique constraint `(REQUEST_TYPE, REQUEST_ID, AUTHORIZER_UCID)`.

---

## 6. APEX Pages

### Authorizer Pages (70–76)

| Page | Title | Key Items | Process |
|------|-------|-----------|---------|
| 70 | Authorize Requests (Landing) | `P70_ACTIVE_COUNT` | Count pending per request type |
| 71 | Authorize Contribution Uploads | `P71_SELECTED_IDS`, `P71_REMARKS` | `AUTHORIZE_REQUEST('CONTRIB', ...)` |
| 72 | Authorize Loan Requests | `P72_SELECTED_IDS`, `P72_REMARKS` | `AUTHORIZE_REQUEST('LOAN', ...)` |
| 73 | Authorize Withdrawal Requests | `P73_SELECTED_IDS`, `P73_REMARKS` | `AUTHORIZE_REQUEST('WITHDRAWAL', ...)` |
| 74 | Authorize Lien Requests | `P74_SELECTED_IDS`, `P74_REMARKS` | `AUTHORIZE_REQUEST('LIEN', ...)` |
| 75 | Authorize NOC Requests | `P75_SELECTED_IDS`, `P75_REMARKS` | `AUTHORIZE_REQUEST('NOC', ...)` |
| 76 | Settings: Loan Settings Auth | `P76_REMARKS` | `AUTHORIZE_LOAN_SETTINGS(...)` |

### Employee Pages (80–85)

| Page | Title | Key Items | Process |
|------|-------|-----------|---------|
| 80 | My Dashboard | `P80_DATE_FROM`, `P80_DATE_TO` | Fund overview table + chart |
| 81 | Account Statement | `P81_PERIOD_TYPE`, `P81_DATE_FROM/TO` | VIEW_NOW / REQUEST_ON_EMAIL |
| 82 | Certificates | `P82_TAX_YEAR`, `P82_CERT_HTML` | `GENERATE_TAX_CERTIFICATE` |
| 83 | Portfolio Reallocation | `P83_MM/DEBT/EQUITY_PCT` | `CREATE_PORTFOLIO_REALLOC` |
| 84 | Create Loan Request | `P84_STEP` (1/2/3), `P84_AMOUNT`, etc. | 3-step wizard; `CREATE_LOAN_REQUEST` |
| 85 | Create Withdrawal Request | `P85_STEP` (1/2/3), `P85_AMOUNT`, etc. | 3-step wizard; `CREATE_WITHDRAWAL_REQUEST` |

---

## 7. FSD Narration Formats

All narrations must use the exact formats below. They are stored in `EPF_ACTIVITY_LOGS.ACTION_DETAIL` with a `[Ref TYPE-ID]` tag appended.

### Contribution Upload (Category 2)
| Code | Narration |
|------|-----------|
| 2.1 | `[Name and Role]: Created contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 2.2 | `[Name and Role]: Approved contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 2.3 | `[Name and Role]: Approved contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 2.6a | `[Name and Role]: Rejected contribution upload on [DD-Mon-YY], at [HH:MI am]` |
| 2.7a | `[Name and Role]: Contribution upload pending at [name (email address)]` |
| 2.7b | `Alfalah Investments: Contribution upload pending at Alfalah Investments` |

### Loan Request (Category 3)
| Code | Narration |
|------|-----------|
| 3.1 | `[Name and Role]: Created loan request on [DD-Mon-YY], at [HH:MI am]` (employee: `[name] (employee): Created loan request...`) |
| 3.2 | `[Name and Role]: Approved loan request on [DD-Mon-YY], at [HH:MI am]` |
| 3.3 | `[Name and Role]: Approved loan request on [DD-Mon-YY], at [HH:MI am]` |
| 3.6a | `[Name and Role]: Rejected loan request on [DD-Mon-YY], at [HH:MI am]` |
| 3.7a | `[Name and Role]: Loan request pending at [name (email address)]` |

### Withdrawal Request (Category 4)
| Code | Narration |
|------|-----------|
| 4.1 | `[Name and Role]: Created withdrawal request on [DD-Mon-YY], at [HH:MI am]` |
| 4.3 | `[Name and Role]: Approved withdrawal request on [DD-Mon-YY], at [HH:MI am]` |
| 4.6a | `[Name and Role]: Rejected withdrawal request on [DD-Mon-YY], at [HH:MI am]` |
| 4.7a | `[Name and Role]: Withdrawal request pending at [name (email address)]` |

### Lien Marking/Unmarking (Categories 5-6)
| Code | Narration |
|------|-----------|
| 5.3 | `[Name and Role]: Approved lien marking request on [DD-Mon-YY], at [HH:MI am]` |
| 5.4 | `[Name and Role]: Rejected lien marking request on [DD-Mon-YY], at [HH:MI am]` |
| 5.6 | `[Name and Role]: Lien marking request pending at [name (email address)]` |
| 6.3a | `[Name and Role]: Approved lien unmarking request on [DD-Mon-YY], at [HH:MI am]` |
| 6.3b | `[Name and Role]: Approved lien unmarking request and manual loan settlement request (for outstanding loan of [amount]) on [DD-Mon-YY], at [HH:MI am]` |
| 6.4a | `[Name and Role]: Rejected lien unmarking request on [DD-Mon-YY], at [HH:MI am]` |
| 6.5a | `[Name and Role]: Lien unmarking request pending at [name (email address)]` |

### NOC Issuance (Category 7)
| Code | Narration |
|------|-----------|
| 7.3 | `[Name and Role]: Approved NOC issuance request on [DD-Mon-YY], at [HH:MI am]` |
| 7.4 | `[Name and Role]: Rejected NOC issuance request on [DD-Mon-YY], at [HH:MI am]` |
| 7.5 | `[Name and Role]: NOC Issuance request pending at [name (email address)]` |

### Loan Settings (Category 9)
| Code | Narration |
|------|-----------|
| 9.6 | `Loan Settings were [approved/rejected] by Authorizer [Name] (Interest Type: [fixed/floating], Floating Rate Tenure: [number] months, Interest Rate: [number]%, Loan Limit: [number]%, Max Instalment Period: [number] months)` |

---

## 8. Email Scenarios

### New Emails Added in db/14

| # | Subject | Recipient | Trigger |
|---|---------|-----------|---------|
| 8 | `Unsuccessful Login Attempt on EPF Platform` | User | Incorrect password login attempt |
| 9 | `Successful Login on EPF Platform` | User | Every successful login |
| 16 | `[Request Type] Request is Rejected` | Maker/AAML Maker | Any request rejected by any user |
| 19 | `[Request Type] Request is pending approval` | Checker/Authorizer | Request lands at user for approval |
| 20 | `[Request Type] Request is Completed` | Maker | All required approvals complete |
| 21 | `Your Account Statement from EPF Platform` | Employee | Employee clicks "Request on Email" |

### Email #16 – Task Rejected
- **Subject:** `[Request Type, e.g. Contribution Upload] Request is Rejected`
- **Body:** Name, rejection by [user role and user name], timestamp, Request Type, Reference No., Remarks

### Email #19 – Request Pending Approval
- **Subject:** `[Request Type] Request is pending approval`
- **Body:** Request Type, Reference No., Created By, Created On, login link

### Email #20 – Request Completed
- **Subject:** `[Request Type] Request is Completed`
- **Body:** Timestamp, Request Type, Reference No., Created On

### Email #21 – Account Statement
- **Subject:** `Your Account Statement from EPF Platform`
- **Body:** Period (date from/to), Folio, Fund; PDF attachment (stub)

---

## 9. Status Code Lookup Rules

**NEVER hardcode a STATUS_ID number.** Always use:
```sql
EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_AUTHORIZER')
EPF_STATUS_PKG.GET_CODE(some_status_id)
```

| Code | Display | Used By |
|------|---------|---------|
| `PENDING_MAKER` | Pending at Maker | Employee-created loan/withdrawal requests |
| `PENDING_CHECKER` | Pending at Checker | After Maker submits (when Checker exists) |
| `PENDING_AUTHORIZER` | Pending at Authorizer | After Checker approves (or direct from Maker) |
| `AUTHORIZED` | Authorized | After all Authorizers approve |
| `REJECTED` | Rejected | After any Checker or Authorizer rejects |
| `COMPLETED` | Completed | After AAML Checker signs off |
| `PENDING_AAML` | Pending at AAML | In EPF_AAML_QUEUE waiting for posting |

---

## 10. File Inventory

| # | File | Description |
|---|------|-------------|
| 1 | `db/13_authorizer_employee_ddl.sql` | DDL: 4 new tables + guarded ALTERs + status seeds |
| 2 | `db/14_epf_email_pkg_addons.sql` | EPF_EMAIL_PKG full rewrite (12 procedures) |
| 3 | `db/15_epf_authorizer_pkg.sql` | EPF_AUTHORIZER_PKG spec + body |
| 4 | `db/16_epf_employee_pkg.sql` | EPF_EMPLOYEE_PKG spec + body |
| 5 | `apex/corp_authorizer/page_processes.sql` | Pages 70–76 APEX processes |
| 6 | `apex/corp_authorizer/ir_queries.sql` | IR queries + LOV for authorizer pages |
| 7 | `apex/corp_authorizer/html_templates.html` | HTML/CSS/JS for authorizer UI |
| 8 | `apex/employee/page_processes.sql` | Pages 80–85 APEX processes |
| 9 | `apex/employee/ir_queries.sql` | IR queries for employee pages |
| 10 | `apex/employee/html_templates.html` | HTML/CSS/JS for employee UI |
| 11 | `EPF_AUTHORIZER_EMPLOYEE_GUIDE.md` | This document |

---

## 11. Key Design Decisions

1. **Multi-Authorizer tracking** uses `EPF_AUTHORIZER_DECISIONS` (one row per authorizer per request) with a unique constraint `(REQUEST_TYPE, REQUEST_ID, AUTHORIZER_UCID)`. This prevents double-voting and allows partial-approval state queries.

2. **AUTHORIZER_COUNT** is stored on each request table at submission time (from `GET_AUTHORIZER_COUNT`). This freezes the required count even if authorizers are added/removed later, matching the authorization group snapshot at creation time.

3. **AAML Queue** (`EPF_AAML_QUEUE`) is populated by `APPLY_AUTHORIZATION_SIDE_EFFECTS` only after ALL required authorizers approve. AAML Maker picks from this table for DFN transaction posting (FSD #370–371).

4. **Loan Settings** follow the same Maker→Checker→Authorizer hierarchy. Pending changes are stored in `EPF_COMPANY_SETTINGS.PENDING_*` columns; on AUTHORIZE they are promoted to the live columns; on REJECT they are discarded.

5. **Employee Loan/Withdrawal requests** use status `PENDING_MAKER` (not `PENDING_CHECKER`/`PENDING_AUTHORIZER`) so they appear in the Maker's "Create Requests" queue for normal workflow entry. The `CREATED_BY_EMPLOYEE_YN='Y'` flag distinguishes them from Maker-created requests.

6. **Portfolio Reallocation by Employee** inserts directly to `EPF_REALLOC_REQUESTS` with `STATUS='PENDING'`; per FSD #372, these go to DFN automatically at day end. No Maker/Checker/Authorizer approval needed.

7. **Tax Certificates** (`GENERATE_TAX_CERTIFICATE`) produce HTML stubs. Actual PKR values are pending DFN data feed integration. The certificate HTML uses the same `BUILD_EMAIL_HTML`-compatible styling as the email package.

8. **`EPF_FOLIO_FUND_MAPPING`** is referenced in dashboard and reallocation queries. This table is expected to be populated by the DFN data synchronization feed (out of scope for this module but assumed to exist based on existing codebase patterns).

9. All procedures use `PRAGMA AUTONOMOUS_TRANSACTION` only in logging/notification helpers, not in the main business logic, to ensure proper rollback behavior.

10. Status codes are NEVER hardcoded as integers — always resolved via `EPF_STATUS_PKG.GET_ID(category, code)`.
