# EPF Portal — AAML Maker & Checker: Complete Development Guide
**Date:** 09-Jun-2026  **App:** f136 — EPF Portal (Oracle APEX 23.x / Oracle 19c+)

---

## Table of Contents
1. [Architecture & Key Objects](#1-architecture--key-objects)
2. [Error Fixes (from Application Dependencies)](#2-error-fixes)
3. [New DB Objects (DDL)](#3-new-db-objects)
4. [EPF_AAML_PKG — Confirmed Signatures](#4-epf_aaml_pkg--confirmed-signatures)
5. [EPF_EMP_SYNC_PKG — DFN Scheduler](#5-epf_emp_sync_pkg--dfn-scheduler)
6. [APEX Page Processes (PL/SQL blocks)](#6-apex-page-processes)
7. [APEX AJAX Application Processes](#7-apex-ajax-application-processes)
8. [IR / Classic Report SQL Queries](#8-ir--classic-report-sql-queries)
9. [Authorization Schemes](#9-authorization-schemes)
10. [HTML/CSS Templates](#10-htmlcss-templates)
11. [Implementation Checklist](#11-implementation-checklist)

---

## 1. Architecture & Key Objects

### Session State Items (set by EPF_PKG_AUTH.POST_AUTH_SETUP)
| Item | Description |
|---|---|
| `APP_USER_ID` | DB `EPF_USERS.USER_ID` of logged-in user |
| `APP_USER_COMPANY_ID` | `EPF_USER_COMPANIES.USER_COMPANY_ID` |
| `APP_COMPANY_ID` | `EPF_COMPANIES.COMPANY_ID` |
| `APP_COMPANY_NAME` | Company display name |
| `APP_ROLE_CODE` | Highest-priority role (from `EPF_ROLES.ROLE_CODE`) |
| `APP_FULL_NAME` | User's full name |

### Key Packages (existing)
| Package | Purpose |
|---|---|
| `EPF_PKG_AUTH` | Authentication + post-auth session setup |
| `EPF_STATUS_PKG` | `GET_CODE(id)`, `GET_ID(category,code)` — use everywhere |
| `EPF_UTIL` | `GET_COMPANY`, `GET_USER_COMPS`, `GET_USER_COMPANY_ID`, `GET_ROLE_CODE` |
| `EPF_AAML_PKG` | All AAML Maker/Checker business logic (this guide) |
| `EPF_EMP_SYNC_PKG` | DFN API employee sync (new) |

### Key Tables / Views
| Object | Type | Key Columns |
|---|---|---|
| `EPF_COMPANIES` | Table | `COMPANY_ID`, `COMPANY_NAME`, `GROUP_ID`, `IS_PRIMARY`, `REF_NO`, `STATUS_ID` |
| `EPF_COMPANY_SETTINGS` | Table | `COMPANY_ID`, `CONTRIBUTION_PCT`, `EMPLOYER_PCT`, `VESTING_MONTHS`, `LOAN_ENABLED`, `REALLOC_ENABLED`, `MM/DEBT/EQUITY_LIMIT` |
| `EPF_COMPANY_FUNDS` | Table | `COMPANY_ID`, `FUND_ID` |
| `EPF_USERS` | Table | `USER_ID`, `EMAIL`, `FULL_NAME`, `CNIC`, `MOBILE_NO`, `STATUS_ID`, `IS_ACTIVE`, `FORCE_PWD_CHANGE`, `PASSWORD_HASH`, `PASSWORD_SALT`, `DESIGNATION`, `DFN_INVESTOR_ID` |
| `EPF_USER_COMPANIES` | Table | `USER_COMPANY_ID` (PK), `USER_ID`, `COMPANY_ID`, `FOLIO_ID`, `STATUS_ID`, `IS_DEFAULT` |
| `EPF_USER_COMP_ROLES` | Table | `USER_COMPANY_ID` (FK), `ROLE_ID`, `IS_ACTIVE` — **join via USER_COMPANY_ID** |
| `EPF_ROLES` | Table | `ROLE_ID`, `ROLE_CODE`, `ROLE_NAME`, `ROLE_LEVEL` |
| `EPF_FOLIOS` | Table | `FOLIO_ID`, `COMPANY_ID`, `FOLIO_NUMBER`, `DFN_FOLIO_ID`, `STATUS_ID` |
| `EPF_FOLIO_FUND_MAPPING` | Table | `FOLIO_ID`, `FUND_ID` |
| `EPF_STATUSES` | Table | `STATUS_ID`, `STATUS_CODE`, `STATUS_LABEL`, `CSS_CLASS`, `CATEGORY_CODE` |
| `EPF_CLIENT_CHANGE_REQUESTS` | Table | `CHANGE_REQ_ID`, `CHANGE_REQ_REF_NO`, `COMPANY_ID`, `SECTION_CHANGED`, `STATUS_ID` |
| `EPF_V_USER_COMPANIES` | View | `USER_COMPANY_ID`, `USER_ID`, `COMPANY_ID`, `EMAIL`, `COMPANY_NAME`, `USER_COMPANY_STATUS`, `COMPANY_STATUS`, `IS_DEFAULT` |

### Role Codes
| Code | Description |
|---|---|
| `ALFALAH_ADMIN` | AAML Admin |
| `ALFALAH_MAKER` | AAML Maker |
| `ALFALAH_CHECKER` | AAML Checker |
| `ALFALAH_OPS` | AAML Operations |
| `CORP_ADMIN` | Corporate Admin |
| `CORP_MAKER` | Corporate Maker |
| `CORP_CHECKER` | Corporate Checker |
| `CORP_AUTHORIZER` | Corporate Authorizer |
| `EMPLOYEE` | Employee (managed by sync) |

---

## 2. Error Fixes

### Fix 1 — Pages 12 & 13: DELETE USERS (ORA-00942: EPF_USERS_ROLES)
**Root cause:** Table `EPF_USERS_ROLES` doesn't exist. The correct table is `EPF_USER_COMP_ROLES` with `USER_COMPANY_ID` FK.

**Corrected PL/SQL** (replace in Page 12 & 13 → Process → DELETE USERS):
```sql
DECLARE
    v_deleted_status NUMBER := EPF_STATUS_PKG.GET_ID('USER_STATUS','DELETED');
BEGIN
    -- Deactivate role assignments
    UPDATE EPF_USER_COMP_ROLES ucr
    SET    ucr.IS_ACTIVE = 'N'
    WHERE  ucr.USER_COMPANY_ID IN (
               SELECT uc.USER_COMPANY_ID
               FROM   EPF_USER_COMPANIES uc
               WHERE  uc.USER_ID MEMBER OF
                      (SELECT APEX_STRING.SPLIT_NUMBERS(:P12_USER_ID,':') FROM DUAL)
               AND    uc.COMPANY_ID = :P12_COMPANY_ID
           );
    -- Soft-delete user_company record
    UPDATE EPF_USER_COMPANIES
    SET    STATUS_ID    = v_deleted_status,
           UPDATED_BY   = :APP_USER_ID,
           UPDATED_DATE = SYSDATE
    WHERE  USER_ID MEMBER OF
               (SELECT APEX_STRING.SPLIT_NUMBERS(:P12_USER_ID,':') FROM DUAL)
    AND    COMPANY_ID = :P12_COMPANY_ID;

    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := 'User(s) deactivated.';
EXCEPTION WHEN OTHERS THEN
    APEX_ERROR.ADD_ERROR(p_message=>'Delete failed: '||SQLERRM,
        p_display_location=>APEX_ERROR.C_INLINE_IN_NOTIFICATION);
END;
```
> For Page 13: replace `:P12_USER_ID` → `:P13_USER_ID`, `:P12_COMPANY_ID` → `:P13_COMPANY_ID`

---

### Fix 2 — Page 11 Search Results: u2.folio invalid identifier
**Root cause:** `EPF_USERS` has no FOLIO column. Folio data lives in `EPF_USER_COMPANIES.FOLIO_ID`.

**Corrected subquery for user/emp counts:**
```sql
-- Non-employee users (no folio linked)
(SELECT COUNT(*) FROM EPF_USER_COMPANIES uc2
 JOIN EPF_STATUSES st2 ON st2.STATUS_ID = uc2.STATUS_ID
 WHERE uc2.COMPANY_ID = c.COMPANY_ID AND st2.STATUS_CODE != 'DELETED'
 AND uc2.FOLIO_ID IS NULL) AS user_count,

-- Employee count (has a folio)
(SELECT COUNT(*) FROM EPF_USER_COMPANIES uc2
 JOIN EPF_STATUSES st2 ON st2.STATUS_ID = uc2.STATUS_ID
 WHERE uc2.COMPANY_ID = c.COMPANY_ID AND st2.STATUS_CODE != 'DELETED'
 AND uc2.FOLIO_ID IS NOT NULL) AS emp_count,
```

---

### Fix 3 — Page 9999: Clear Sessions (ORA-00942: apex_240200.WWV_FLOW_SESSIONS$)
**Root cause:** Workspace-internal table name hardcoded — fails on deployment.

**Corrected PL/SQL:**
```sql
DECLARE
    v_username VARCHAR2(500) := :P9999_USERNAME;
BEGIN
    IF v_username IS NOT NULL THEN
        FOR s IN (SELECT session_id FROM apex_workspace_sessions
                  WHERE UPPER(user_name) = UPPER(v_username))
        LOOP
            APEX_SESSION.DELETE_SESSION(p_session_id => s.session_id);
        END LOOP;
    END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END;
```

---

### Fix 4 — EPF_SAVE_CLIENT: PLS-00306 Wrong Arguments
**Root cause:** `EPF_AAML_PKG.SAVE_CLIENT` didn't exist with the right signature.  
**Fix:** Deploy `06_epf_aaml_pkg_addons.sql` which defines `SAVE_CLIENT` as a FUNCTION returning `NUMBER` (company_id) with all parameters the existing process expects.

---

## 3. New DB Objects

Run `db/01_ddl_new_objects.sql` which creates:

| Object | Purpose |
|---|---|
| `EPF_COMPANY_SEQ` | Company ID generator |
| `EPF_CHG_REQ_SEQ` | Change request ID generator |
| `EPF_AUTH_GROUP_SEQ` | Authorizer group ID generator |
| `EPF_ONBOARDING_SUBMISSIONS` | 4-tab wizard completion tracking per company |
| `EPF_CR_SECTION_CHANGES` | Per-section OLD/NEW JSON for change requests |
| `EPF_EMP_API_STAGING` | DFN API raw response staging (daily sync) |
| ALTER `EPF_CLIENT_CHANGE_REQUESTS` | Adds: `SECTION_LABEL`, `REVERTED_DATE`, `REVERTED_BY`, `REVERT_REMARKS`, `MAKER_RESUBMIT_DATE`, `AAML_APPLIED_DATE` |

---

## 4. EPF_AAML_PKG — Confirmed Signatures

> **IMPORTANT:** Use `EPF_STATUS_PKG.GET_ID(category, code)` for status IDs and `EPF_STATUS_PKG.GET_CODE(status_id)` for status code lookups. Never hardcode status IDs.

### `SAVE_CLIENT` (FUNCTION → returns COMPANY_ID)
Called by existing APEX process `EPF_SAVE_CLIENT` on Page 4.
```sql
FUNCTION SAVE_CLIENT(
    p_company_id, p_company_name, p_group_id, p_new_group_name, p_is_primary,
    p_fund1_id, p_fund2_id, p_loan_enabled, p_interest_type_id, p_float_tenure,
    p_interest_rate, p_loan_limit_pct, p_max_instalment_mo, p_realloc_enabled,
    p_mm_limit, p_debt_limit, p_equity_limit, p_admin_user_id, p_created_by
) RETURN NUMBER
```

### `SUBMIT_TO_CHECKER` (PROCEDURE — 2 params)
```sql
PROCEDURE SUBMIT_TO_CHECKER(p_company_id IN NUMBER, p_submitted_by IN NUMBER)
```
Validates: Tab1+Tab2 complete, at least 1 CORP_ADMIN and 1 CORP_AUTHORIZER.

### `CHECKER_APPROVE` (PROCEDURE)
```sql
PROCEDURE CHECKER_APPROVE(p_company_id IN NUMBER, p_remarks IN VARCHAR2, p_approved_by IN NUMBER)
```
Actions: Company/Settings/Submission → ACTIVE; Users → ACTIVE; sends welcome emails.

### `CHECKER_REJECT` (PROCEDURE — hard reject)
```sql
PROCEDURE CHECKER_REJECT(p_company_id IN NUMBER, p_remarks IN VARCHAR2, p_rejected_by IN NUMBER)
```
Actions: Company/Settings/Submission → REJECTED. Remarks mandatory.

### `CHECKER_REVERT` (PROCEDURE — soft revert to Maker)
```sql
PROCEDURE CHECKER_REVERT(p_company_id IN NUMBER, p_remarks IN VARCHAR2, p_reverted_by IN NUMBER)
```
Actions: Company/Settings → DRAFT; Submission → DRAFT; UserCompanies → PENDING. Remarks mandatory.

### `SAVE_COMPANY_USER` (PROCEDURE)
```sql
PROCEDURE SAVE_COMPANY_USER(
    p_company_id, p_user_company_id, p_folio_id, p_role_id,
    p_full_name, p_email, p_cnic, p_mobile_no, p_employee_code,
    p_performed_by,
    p_out_user_id OUT, p_out_success OUT, p_out_message OUT
)
```
- Validates email/CNIC/mobile format
- Email duplicate check within company
- If user already exists globally by email → reuse, enrich missing fields
- New user: SHA-512 hash, temp pwd `EPF@2024!`, FORCE_PWD_CHANGE='Y'
- Joins via `EPF_USER_COMPANIES.USER_COMPANY_ID` → `EPF_USER_COMP_ROLES`
- Marks TAB2_COMPLETE='Y'

### `SAVE_AUTHORIZER_GROUP` (PROCEDURE)
```sql
PROCEDURE SAVE_AUTHORIZER_GROUP(
    p_group_id, p_company_id, p_group_name, p_min_approvals,
    p_member_user_ids (colon-separated USER_IDs),
    p_performed_by,
    p_out_group_id OUT, p_out_success OUT, p_out_message OUT
)
```
- Validates: name required, min_approvals >= 1, min_approvals <= member count
- Duplicate group name check within company
- Marks TAB3_COMPLETE='Y'

### Change Request Procedures
```sql
PROCEDURE BEGIN_CHANGE_REQUEST(p_company_id, p_user_id, p_out_change_req_id OUT, p_out_ref_no OUT)
PROCEDURE SAVE_CR_SECTION(p_change_req_id, p_section_code, p_new_values_json, p_change_summary, p_user_id)
PROCEDURE SUBMIT_CR_TO_CHECKER(p_change_req_id, p_user_id, p_out_success OUT, p_out_message OUT)
PROCEDURE CR_CHECKER_APPROVE(p_change_req_id, p_checker_id, p_remarks, p_out_success OUT, p_out_message OUT)
PROCEDURE CR_CHECKER_REVERT(p_change_req_id, p_checker_id, p_revert_remarks, p_out_success OUT, p_out_message OUT)
```

---

## 5. EPF_EMP_SYNC_PKG — DFN Scheduler

File: `db/04_epf_emp_sync_pkg.sql`

### How It Works
1. `FETCH_FROM_DFN_API(p_company_id)` — calls `GET /accounts/{code}/folios`, merges into `EPF_EMP_API_STAGING` (skips duplicates by COMPANY_ID + FOLIO_NUMBER + BATCH_DATE)
2. `PROCESS_STAGING_BATCH(p_company_id)` — for each PENDING staging row:
   - STEP 1: UPSERT `EPF_FOLIOS`
   - STEP 2: UPSERT `EPF_FOLIO_FUND_MAPPING` per fund code
   - STEP 3: Find/create `EPF_USERS` by email (enrich if existing)
   - STEP 4: UPSERT `EPF_USER_COMPANIES` (with USER_COMPANY_ID)
   - STEP 5: INSERT EMPLOYEE role in `EPF_USER_COMP_ROLES` via USER_COMPANY_ID if not already assigned
   - Per-row SAVEPOINT for error isolation
   - Marks TAB4_COMPLETE='Y' if rows processed
3. `RUN_DAILY_SYNC` — loops all ACTIVE/PENDING_CHECKER companies with DFN_ACCOUNT_CODE set
4. Scheduler: `EPF_EMP_DAILY_SYNC` runs at 2 AM daily

---

## 6. APEX Page Processes

File: `apex/processes/page_processes.sql`

| Process Name | Button/When | Action |
|---|---|---|
| `SAVE_AUTHORIZER_GROUP` | Tab 3, BTN_SAVE_GROUP | Calls `EPF_AAML_PKG.SAVE_AUTHORIZER_GROUP`, sets `:P_AUTH_GROUP_ID` |
| `SUBMIT_TO_CHECKER` | BTN_SUBMIT_CHECKER | Calls `EPF_AAML_PKG.SUBMIT_TO_CHECKER(p_company_id, p_submitted_by)` |
| `CHECKER_APPROVE` | Checker page, BTN_APPROVE | Calls `EPF_AAML_PKG.CHECKER_APPROVE(p_company_id, p_remarks, p_approved_by)` |
| `CHECKER_REVERT` | Checker page, BTN_REVERT | Validates remarks, calls `CHECKER_REVERT(p_company_id, p_remarks, p_reverted_by)` |
| `CHECKER_REJECT` | Checker page, BTN_REJECT | Validates remarks, calls `CHECKER_REJECT(p_company_id, p_remarks, p_rejected_by)` |
| `CR_CHECKER_APPROVE` | CR Checker page | Calls `CR_CHECKER_APPROVE(p_change_req_id, p_checker_id, p_remarks, ...)` |
| `CR_CHECKER_REVERT` | CR Checker page | Validates remarks, calls `CR_CHECKER_REVERT(...)` |
| `BEGIN_CHANGE_REQUEST` | Before Header, Maker CR page | Calls `BEGIN_CHANGE_REQUEST`, sets `:P_CHANGE_REQ_ID` and `:P_CR_REF_NO` |
| `SAVE_CR_SECTION_ACCOUNT` | BTN_SAVE_ACCOUNT_SECTION | Builds JSON from page items, calls `SAVE_CR_SECTION('ACCOUNT',...)` |
| `SAVE_CR_SECTION_SETTINGS` | BTN_SAVE_SETTINGS_SECTION | Builds JSON, calls `SAVE_CR_SECTION('SETTINGS',...)` |
| `SUBMIT_CR_TO_CHECKER` | BTN_SUBMIT_CR | Calls `SUBMIT_CR_TO_CHECKER(p_change_req_id, p_user_id, ...)` |
| `LOAD_CHECKER_STATS` | Before Header, Checker Dashboard | Sets `:STAT_NEW_CLIENTS`, `:STAT_CHANGE_REQS`, `:STAT_REVERTED`, `:STAT_TOTAL_PENDING` |
| `LOAD_CR_FORM_DATA` | Before Header, CR Form page | Loads current live values + calls `BEGIN_CHANGE_REQUEST` |

---

## 7. APEX AJAX Application Processes

File: `apex/templates/06_ajax_processes.sql`

Register each in **Shared Components → Application Processes (On Demand = Yes)**:

| Process Name | Called by JS | Action |
|---|---|---|
| `CHECKER_APPROVE_AJAX` | `epfConfirmApprove()` for ONBOARDING | `EPF_AAML_PKG.CHECKER_APPROVE(G_X01, G_X02, resolved_user_id)` |
| `CHECKER_REVERT_AJAX` | `epfConfirmRevert()` for ONBOARDING | `EPF_AAML_PKG.CHECKER_REVERT(...)` |
| `CR_CHECKER_APPROVE_AJAX` | `epfConfirmApprove()` for CHANGE_REQUEST | `EPF_AAML_PKG.CR_CHECKER_APPROVE(...)` |
| `CR_CHECKER_REVERT_AJAX` | `epfConfirmRevert()` for CHANGE_REQUEST | `EPF_AAML_PKG.CR_CHECKER_REVERT(...)` |
| `LOAD_GROUP_AJAX` | `epfOpenGroupModal(groupId)` | Returns group name, min_approvals, member_ids as JSON |

All return JSON: `{"success":"Y","message":"..."}` or `{"success":"N","message":"error..."}`.

---

## 8. IR / Classic Report SQL Queries

File: `apex/processes/ir_queries.sql`

| Region | Query Key Points |
|---|---|
| **Maker Client Dashboard (P10)** | Joins EPF_COMPANIES + EPF_STATUSES + EPF_COMPANY_GROUPS + EPF_ONBOARDING_SUBMISSIONS; derives ROW_ACTION (CONTINUE/EDIT/VIEW/MANAGE) by STATUS_CODE |
| **Checker Dashboard (P20)** | UNION: onboarding subs (PENDING_CHECKER) + CRs (PENDING_CHECKER); shows type badge, submitted by, review link |
| **Tab 2 Users IR** | EPF_USERS → EPF_USER_COMPANIES → EPF_USER_COMP_ROLES (via USER_COMPANY_ID) → EPF_ROLES; excludes EMPLOYEE role and DELETED |
| **Tab 3 Groups IR** | EPF_AUTHORIZER_GROUPS + LISTAGG members via EPF_AUTHORIZER_GROUP_MEMBERS |
| **Tab 4 Staging IR** | EPF_EMP_API_STAGING for today's batch; shows PROCESS_STATUS, PROCESS_MESSAGE |
| **CR History IR (P14)** | EPF_CLIENT_CHANGE_REQUESTS + EPF_STATUSES; all CRs for a company |
| **LOV: Member Selector** | EPF_USERS with CORP_ADMIN or CORP_AUTHORIZER roles for this company |

### Critical Pattern — User Management IR (Page 12/13)
The existing query uses this join correctly:
```sql
FROM EPF_USERS a
JOIN EPF_USER_COMPANIES cg ON cg.user_id = a.USER_ID
JOIN EPF_USER_COMP_ROLES b ON b.USER_COMPANY_ID = cg.USER_COMPANY_ID
JOIN EPF_ROLES r ON b.ROLE_ID = r.ROLE_ID
WHERE cg.COMPANY_ID = :P12_COMPANY_ID
AND r.ROLE_CODE != 'EMPLOYEE'
```
The role-visibility logic based on `APP_ROLE_CODE` is already implemented — preserve it.

---

## 9. Authorization Schemes

All authorization schemes follow this pattern (use in APEX → Shared Components → Authorization Schemes, type = SQL Query Returns At Least One Row):

### IS_AAML_MAKER
```sql
SELECT 1 FROM EPF_V_USER_COMPANIES u
JOIN epf_user_comp_roles ur ON u.user_company_id = ur.user_company_id
JOIN epf_roles r ON ur.role_id = r.role_id
JOIN epf_statuses st ON u.status_id = st.status_id
WHERE UPPER(u.email) = UPPER(:APP_USER)
  AND r.role_code = 'ALFALAH_MAKER'
  AND ur.is_active = 'Y'
  AND st.status_code = 'ACTIVE' AND st.category_code = 'USER_STATUS'
  AND (u.company_id = :APP_COMPANY_ID OR u.company_id IS NULL)
```

Replace `role_code = 'ALFALAH_MAKER'` with the target role for other schemes:
- `IS_AAML_CHECKER`: `'ALFALAH_CHECKER'`
- `IS_AAML_ANY`: `IN ('ALFALAH_MAKER','ALFALAH_CHECKER')`
- `IS_AAML_OPS`: `'ALFALAH_OPS'`
- `IS_ADMIN`: `IN ('ALFALAH_ADMIN','CORP_ADMIN')`
- `IS_CORP_ADMIN`: `'CORP_ADMIN'`
- `IS_CORP_AUTHORIZER`: `'CORP_AUTHORIZER'`
- `IS_CORP_CHECKER`: `'CORP_CHECKER'`

---

## 10. HTML/CSS Templates

All templates are in `apex/templates/`:

| File | APEX Page | Where to Paste |
|---|---|---|
| `01_checker_dashboard.html` | Checker Dashboard (P20) | Static Content region ABOVE the IR; include `<style>` once per app |
| `02_checker_client_detail.html` | Client Detail Review (P22) | Static Content region at top of page |
| `03_tab3_auth_group.html` | Onboarding Wizard Tab 3 | Static Content region; APEX page items: `P_AUTH_GROUP_ID`, `P_GROUP_NAME`, `P_MIN_APPROVALS`, `P_MEMBER_USER_IDS` |
| `04_cr_comparison.html` | CR Detail (P23/P30) | Static Content region; use `epfRenderSection()` from Classic Report row template |
| `05_maker_cr_form.html` | Maker CR Form (P15/P30) | Static Content region; page items prefixed `P_CR_*` and `P_CURR_*` |
| `06_ajax_processes.sql` | Application Processes | Shared Components → Application Processes (On Demand) |

### Key CSS Classes (matching existing EPF styles)
```css
epf-badge-success     /* ACTIVE */
epf-badge-danger      /* REJECTED/DELETED */
epf-badge-warning     /* PENDING_CHECKER */
epf-badge-neutral     /* DRAFT */
epf-badge-info        /* PENDING */
```

---

## 11. Implementation Checklist

### Step 1 — Run DDL (in order)
- [ ] `db/01_ddl_new_objects.sql` — new sequences, tables, ALTER

### Step 2 — Deploy Packages
- [ ] `db/06_epf_aaml_pkg_addons.sql` — **use this file** (it supersedes 02+03 with corrected signatures)
- [ ] `db/04_epf_emp_sync_pkg.sql` — DFN sync package + scheduler job

### Step 3 — Fix Existing APEX Errors
- [ ] Page 12 → Process → DELETE USERS → replace with Fix 1 SQL
- [ ] Page 13 → Process → DELETE USERS → replace with Fix 1 SQL (P13_ items)
- [ ] Page 11 → Region → Search Results → fix `u2.folio` subqueries (Fix 2)
- [ ] Page 9999 → Process → Clear Open Sessions → replace with Fix 3 SQL

### Step 4 — Register APEX Application Processes (On Demand)
- [ ] `CHECKER_APPROVE_AJAX`
- [ ] `CHECKER_REVERT_AJAX`
- [ ] `CR_CHECKER_APPROVE_AJAX`
- [ ] `CR_CHECKER_REVERT_AJAX`
- [ ] `LOAD_GROUP_AJAX`

### Step 5 — APEX Pages: Add Processes (from page_processes.sql)
- [ ] Tab 3 page: `SAVE_AUTHORIZER_GROUP`
- [ ] Wizard submit button: `SUBMIT_TO_CHECKER`
- [ ] Checker Client Detail page: `CHECKER_APPROVE`, `CHECKER_REVERT`, `CHECKER_REJECT`
- [ ] Checker CR page: `CR_CHECKER_APPROVE`, `CR_CHECKER_REVERT`
- [ ] Maker CR form Before Header: `LOAD_CR_FORM_DATA`
- [ ] Maker CR form: `SAVE_CR_SECTION_ACCOUNT`, `SAVE_CR_SECTION_SETTINGS`, `SUBMIT_CR_TO_CHECKER`
- [ ] Checker Dashboard Before Header: `LOAD_CHECKER_STATS`

### Step 6 — Build APEX Pages
- [ ] Page 20 — Checker Dashboard: paste Template 1 HTML, add IR (Checker Dashboard query)
- [ ] Page 22 — Client Detail Review: paste Template 2 HTML, add 5 IR sub-regions
- [ ] Page 23 — CR Checker Review: paste Template 4 HTML, add Classic Report with `epfRenderSection()`
- [ ] Page 15/30 — Maker CR Form: paste Template 5 HTML
- [ ] Tab 3 page — Authorizer Groups: paste Template 3 HTML, add IR (Groups query)

### Step 7 — Add Authorization Schemes
- [ ] `IS_AAML_MAKER`, `IS_AAML_CHECKER`, `IS_AAML_ANY`, `IS_AAML_OPS`
- [ ] Apply to pages: Checker pages require `IS_AAML_CHECKER`; Maker pages require `IS_AAML_MAKER`

### Step 8 — Test Workflow
- [ ] AAML Maker creates client (Page 4 → SAVE_CLIENT)
- [ ] Completes Tabs 1–4 of onboarding wizard
- [ ] Submits to Checker (SUBMIT_TO_CHECKER validates Admin + Authorizer roles)
- [ ] AAML Checker reviews all 4 tabs on Page 22
- [ ] Approve → client + users go ACTIVE, welcome emails sent
- [ ] Revert → back to Maker with remarks
- [ ] Reject → permanent REJECTED status
- [ ] Active client: Maker raises CR, edits sections, submits
- [ ] Checker reviews OLD vs NEW comparison on Page 23
- [ ] CR Approve → live data updated, CR closed as APPROVED
- [ ] CR Revert → back to Maker for corrections

---

## Appendix: Status Code Reference

| Category | Code | Meaning |
|---|---|---|
| `CLIENT_STATUS` | `DRAFT` | Onboarding started, not submitted |
| `CLIENT_STATUS` | `PENDING_CHECKER` | Submitted, awaiting AAML Checker |
| `CLIENT_STATUS` | `ACTIVE` | Approved and live |
| `CLIENT_STATUS` | `REJECTED` | Hard rejected by Checker |
| `USER_STATUS` | `PENDING` | User created, not yet approved |
| `USER_STATUS` | `PENDING_CHECKER` | Submitted with client |
| `USER_STATUS` | `ACTIVE` | Live |
| `USER_STATUS` | `DELETED` | Soft-deleted |
| `CHANGE_REQ_STATUS` | `DRAFT` | CR started by Maker |
| `CHANGE_REQ_STATUS` | `PENDING_CHECKER` | Submitted for review |
| `CHANGE_REQ_STATUS` | `APPROVED` | Applied to live data |
| `CHANGE_REQ_STATUS` | `REVERTED` | Sent back to Maker |
| `CHANGE_REQ_STATUS` | `REJECTED` | Hard rejected |
