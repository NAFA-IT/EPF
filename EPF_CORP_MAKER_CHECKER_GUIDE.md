# EPF Portal – Corporate Maker / Checker Module: Development Guide

## Overview

This guide covers the complete implementation of the Corporate **Maker** and **Checker** roles in the EPF Portal (Oracle APEX App ID: f136). It includes the transactional database objects, the `EPF_CORP_TXN_PKG` PL/SQL package, APEX pages 40–45 (Maker create journeys), 50–55 (Checker check journeys), and 60 (Settings), plus the notification subsystem.

It implements FSD validations **#203–#294 (Maker)** and **#295–#334 (Checker)**: Home, Employee Dashboard, Create Requests (Contribution Uploads, Loan, Withdrawal, Lien Mark/Unmark, NOC Issuance), View All Requests, Employee Management → Disable Employees, Settings, and all Checker counterparts.

---

## 1. Database Objects (`db/11_corp_txn_ddl.sql`)

Run once, in order, after `07_corp_admin_ddl.sql` (which provides `EPF_ACTIVITY_LOGS` and `ACT_LOG_REF_SEQ`).

| Object | Purpose |
|--------|---------|
| `EPF_NOTIFICATIONS` | System-generated alerts to users (FSD #299/#304/#308/#313/#317) |
| `EPF_CONTRIB_BATCHES` | One row per contribution upload file (FSD #213–#227, #255–#258) |
| `EPF_CONTRIB_BATCH_ROWS` | Per-employee rows of a batch, with error/duplicate flags |
| `EPF_LOAN_REQUESTS` | Loan requests incl. repayment tracking (FSD #228–#233, #259–#262) |
| `EPF_LOAN_SCHEDULE` | System-generated instalment schedule (FSD #232, #303) |
| `EPF_WITHDRAWAL_REQUESTS` | Partial/full withdrawal requests (FSD #234–#238) |
| `EPF_LIEN_REQUESTS` | Lien MARK / UNMARK requests (FSD #239–#250) |
| `EPF_NOC_REQUESTS` | NOC issuance requests (FSD #251–#253) |
| `EPF_EMP_DISABLE_REQUESTS` | Employee disablement — Maker→Checker only (FSD #273–#277) |
| `EPF_FEATURE_ACCESS` | Loan/Withdrawal access lists — Maker→Checker only (FSD #325–#331) |
| `EPF_REALLOC_GROUPS` | Portfolio reallocation custom groups (FSD #286–#294, #332–#335) |
| `EPF_REALLOC_GROUP_MEMBERS` | Group membership with pending statuses |
| `EPF_CONTRIB_BATCH_SEQ` … `EPF_NOC_REQ_SEQ` | Reference-number sequences |

### Reference Number Formats
- Contribution batch: `CB-YYYYMM-0001` · Loan: `LN-YYYYMM-0001` · Withdrawal: `WD-YYYYMM-0001` · Lien: `LM-YYYYMM-0001` · NOC: `NC-YYYYMM-0001`

### Folio / Settings Flag Columns (guarded ALTERs)
- `EPF_FOLIOS`: `LIEN_MARKED`, `IS_DISABLED`, `NOC_ISSUED` (default `'N'`). **May already exist** — skip ORA-01430.
- `EPF_COMPANY_SETTINGS`: `LOAN_INTEREST_TYPE`, `LOAN_INTEREST_RATE`, `LOAN_LIMIT_PCT`, `LOAN_MAX_INSTALMENT_MONTHS`, `FLOATING_RATE_TENURE` — used by `CREATE_LOAN_REQUEST`.

### Status Seeding
A `MERGE` seeds the `REQUEST` category in `EPF_STATUSES` if not present: `PENDING_CHECKER`, `PENDING_AUTHORIZER`, `AUTHORIZED`, `REJECTED`. They are always resolved via `EPF_STATUS_PKG` — never by ID.

---

## 2. Transaction Package (`db/12_epf_corp_txn_pkg.sql`)

**Package:** `EPF_CORP_TXN_PKG`

### Private Helpers

| Name | Purpose |
|------|---------|
| `HAS_ACTIVE_CHECKER(company_id)` | TRUE if company has an ACTIVE `CORP_CHECKER` with an active role |
| `INITIAL_STATUS(company_id)` | `PENDING_CHECKER` id, or `PENDING_AUTHORIZER` id when no Checker (FSD #4) |
| `NEXT_HOP_LABEL(company_id)` | `'Checker'` / `'Authorizer'` for FSD message text |
| `GET_ACTOR_NAME(ucid)` | FULL_NAME for a USER_COMPANY_ID |
| `GET_FOLIO_UCID / GET_FOLIO_NAME(folio_id)` | Resolve employee behind a folio |
| `NARRATE(...)` | FSD-exact narration + dual logging via `EPF_AUTH_PKG.LOG_ACTIVITY`, tags `[Ref TYPE-ID]` |
| `NOTIFY / NOTIFY_ROLE / NOTIFY_NEXT_HOP / NOTIFY_UCID` | Insert into `EPF_NOTIFICATIONS` (autonomous) |
| `OUTSTANDING_LOAN(folio_id)` | Sum of outstanding authorized loans |

### Public API

| Name | Purpose |
|------|---------|
| `CREATE_CONTRIB_BATCH(company_id, maker_ucid, fund_id, month, file_name, collection, ...)` | Validates rows from APEX collection `CONTRIB_UPLOAD` (C001=CNIC, C002=Folio, C003=Name, N001=Employee amt, N002=Employer amt); computes totals + variance vs last authorized batch; flags duplicates; blocks errors incl. NOC-issued folios as 'Employee does not exist' (FSD #227) |
| `CREATE_LOAN_REQUEST(..., amount, instalment_months, current_balance, ...)` | Validates amount > 0, loan limit % and max tenure from `EPF_COMPANY_SETTINGS`; blocks lien/NOC/disabled folios; builds equal-principal + flat-interest schedule (FSD #232) |
| `CREATE_WITHDRAWAL_REQUEST(..., amount, wd_type PARTIAL/FULL, reason, ...)` | Blocks lien/NOC/disabled folios |
| `CREATE_LIEN_REQUEST(..., folio_ids, request_type MARK/UNMARK, ...)` | Colon-list of folios; returns `p_out_loan_warning` = count with outstanding loans (manual settlement, FSD #244–#246) |
| `CREATE_NOC_REQUESTS(..., folio_ids, ...)` | Multi-select; skips folios with outstanding loans or lien (FSD #252) |
| `CREATE_DISABLE_REQUESTS(..., folio_ids, ...)` | Only `NOC_ISSUED='Y'` folios (FSD #275); no Checker = disabled instantly |
| `CHECKER_DECIDE(request_type, request_ids, checker_ucid, decision, remarks, ...)` | Types: CONTRIB/LOAN/WITHDRAWAL/LIEN/NOC/DISABLE; remarks mandatory on REJECT; APPROVE → `PENDING_AUTHORIZER` (DISABLE → applied + `AUTHORIZED`); REJECT → `REJECTED` + Maker notified |
| `REQUEST_FEATURE_ACCESS_CHANGE(..., feature_code LOAN/WITHDRAWAL, folio_ids, action ADD/REMOVE, ...)` | No Checker = instant apply (ENABLED / row delete); else PENDING_ADDITION / PENDING_DELETION |
| `CHECKER_DECIDE_FEATURE_ACCESS(access_ids, checker_ucid, decision, remarks, ...)` | Approve addition→ENABLED, approve deletion→row deleted; reject addition→row deleted, reject deletion→stays ENABLED |
| `SAVE_REALLOC_GROUP(..., group_id NULL=new, name, mm/debt/equity limits, add/remove folio_ids, ...)` | New group or pending-edit JSON; instant save when no Checker; Default Group blocked (AAML-managed) |
| `CHECKER_DECIDE_REALLOC_GROUP(group_id, checker_ucid, decision, remarks, ...)` | Reject new group = delete it; reject edit = discard `PENDING_CHANGES_JSON` (FSD #334) |
| `GET_REQUEST_HISTORY(ref_type, ref_id)` | SYS_REFCURSOR over `EPF_ACTIVITY_LOGS` matching the `[Ref TYPE-ID]` tag |

---

## 3. Workflow

```
                ┌──────────────────────────── Standard request flow ───────────────────────────┐
                │  Contribution Uploads · Loan · Withdrawal · Lien · NOC                        │
                │                                                                              │
   Maker creates ──► PENDING_CHECKER ──(Checker APPROVE)──► PENDING_AUTHORIZER ──► AUTHORIZED   │
        │                  │                                                                   │
        │                  └─(Checker REJECT + mandatory remarks)──► REJECTED (Maker notified) │
        │                                                                                      │
        └── NO ACTIVE CHECKER? ───────────────────────────► PENDING_AUTHORIZER (bypass, FSD #4)│
                └──────────────────────────────────────────────────────────────────────────────┘

                ┌──────────────────── Checker-terminal flows (NEVER reach Authorizer) ─────────┐
                │  Disable Employees (FSD #277/#321) · Loan/Withdrawal Feature Access          │
                │  (FSD #326/#330) · Portfolio Reallocation Groups (FSD #334)                  │
                │                                                                              │
   Maker creates ──► PENDING_CHECKER ──(APPROVE)──► applied immediately                        │
        │                  └─(REJECT + remarks)──► discarded / status restored                 │
        └── NO ACTIVE CHECKER? ──► applied INSTANTLY on Maker save                             │
                └──────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. APEX Pages

All processes in `apex/corp_maker_checker/page_processes.sql`; IR sources in `ir_queries.sql`; HTML/CSS/JS in `html_templates.html`. Binds: `:APP_COMPANY_ID`, `:APP_USER_COMPANY_ID`.

### Page 40 — Create Contribution Upload (4-step wizard, FSD #213–#227)

| Item | Purpose |
|------|---------|
| `P40_STEP` | Wizard step 1–4 (Create → Review → Alerts → Finish) |
| `P40_FUND_ID` | Fund (disabled when single fund) |
| `P40_CONTRIB_MONTH` | Contribution month |
| `P40_FILE` / `P40_INSTRUMENT` | CSV / instrument scan uploads |
| `P40_BATCH_ID`, `P40_BATCH_NO` | Output references |
| `P40_FINISH_MSG` | Finish page text (FSD #226) |

**Processes:** `P40_PARSE_UPLOAD` → Request = `UPLOAD_FILE` (CSV → collection `CONTRIB_UPLOAD`); `P40_CREATE_BATCH` → Request = `CREATE_BATCH`. Alerts step shows clickable cards (valid entries, variance amount/employees, duplicates, errors — popups per FSD #219–#225). Errors disable Next (FSD #225); variance/duplicates do not.

### Page 41 — Create Loan Request (3-step, FSD #228–#233)
Items: `P41_STEP`, `P41_CNIC`, `P41_FOLIO_ID`, `P41_EMP_NAME`, `P41_CURRENT_BALANCE`, `P41_AMOUNT`, `P41_INSTALMENT_MONTHS`, `P41_PAY_MODE`, `P41_LOAN_NO`, `P41_FINISH_MSG`.
**Process:** `P41_CREATE_LOAN` → Request = `CREATE_LOAN`. Review step renders the system-generated instalment schedule.

### Page 42 — Create Withdrawal Request (3-step, FSD #234–#238)
Items: `P42_STEP`, `P42_FOLIO_ID`, `P42_AMOUNT`, `P42_FULL_WITHDRAWAL`, `P42_PAY_MODE`, `P42_REASON`, `P42_WD_NO`, `P42_FINISH_MSG`.
**Process:** `P42_CREATE_WITHDRAWAL` → Request = `CREATE_WITHDRAWAL`.

### Page 43 — Lien Mark / Unmark (FSD #239–#250)
Items: `P43_TOGGLE` (`MARKED`/`UNMARKED`), `P43_SELECTED_FOLIO_IDS`, `P43_REASON`, `P43_LOAN_WARNING`, `P43_ATTENTION_MSG`.
**Process:** `P43_CREATE_LIEN_REQUEST` → Request IN (`MARK_LIEN`, `UNMARK_LIEN`). Confirmation modal includes the outstanding-loans manual-settlement alert (#244); attention popup after submit (#245/#250).

### Page 44 — NOC Issuance (FSD #251–#253)
Items: `P44_SELECTED_FOLIO_IDS`, `P44_ATTENTION_MSG`. **Process:** `P44_ISSUE_NOC` → Request = `ISSUE_NOC`. Checkboxes/Issue NOC buttons disabled for employees with outstanding loans (#252).

### Page 45 — Disable Employees (FSD #273–#277)
Items: `P45_SELECTED_FOLIO_IDS`. **Process:** `P45_DISABLE_EMPLOYEES` → Request = `DISABLE_EMPLOYEES`. Query restricted to `NOC_ISSUED='Y'` folios (#275); pending rows have disabled checkboxes (#274).

### Pages 50–55 — Check Requests (FSD #295–#321)

| Page | Type | FSD columns notes |
|------|------|-------------------|
| 50 | Contribution Uploads | Batch checkbox selects all rows; Review popup with Alerts + batch progress bar (#299) |
| 51 | Loan Requests | NO Amount Repaid / Outstanding / Authorized On / Repaid On; Status replaced by Instalment Schedule **View** button (#301/#303) |
| 52 | Withdrawal Requests | View All columns minus Status (#306) |
| 53 | Lien Requests | Lien Marking / Lien Unmarking Request toggle `P53_TOGGLE` (#309–#311) |
| 54 | NOC Requests | Columns per #315: Name, CNIC/NICOP, Folio, Fund, Loan Outstanding, Lien Status, Current Balance |
| 55 | Disabled Employees | Columns per #319: + NOC Issued (Yes); approval disables instantly (#321) |

Shared items: `P5x_SELECTED_IDS`, `P5x_REMARKS`. Shared processes `P5x_CHECKER_DECIDE` → Request IN (`APPROVE_SELECTED`, `REJECT_SELECTED`) calling `CHECKER_DECIDE` with the page's request type. Reject opens the remarks modal (mandatory); Approve opens "Are you sure you want to approve these requests?".

### Page 60 — Settings (FSD #281–#294, #322–#334)
Items: `P60_FEATURE_CODE`, `P60_SELECTED_FOLIO_IDS`, `P60_SELECTED_ACCESS_IDS`, `P60_REMARKS`, `P60_REQUEST_TYPE_FILTER`, `P60_GROUP_ID`, `P60_GROUP_NAME`, `P60_MM_LIMIT`, `P60_DEBT_LIMIT`, `P60_EQUITY_LIMIT`, `P60_ADD_FOLIO_IDS`, `P60_REMOVE_FOLIO_IDS`.

**Processes / Requests:**
- `P60_FEATURE_ACCESS_ADD` → `FEATURE_ADD` · `P60_FEATURE_ACCESS_REMOVE` → `FEATURE_REMOVE` (Maker)
- `P60_FEATURE_ACCESS_DECIDE` → `FEATURE_APPROVE` / `FEATURE_REJECT` (Checker)
- `P60_SAVE_REALLOC_GROUP` → `SAVE_GROUP` (Maker)
- `P60_REALLOC_GROUP_DECIDE` → `GROUP_APPROVE` / `GROUP_REJECT` (Checker)

Checker view shows changed settings as strikethrough-red old / green new values (#324); Pending Requests section is hidden when empty (#325); pending list rows are greyed with hover text "[Addition / Deletion] request is pending at Checker" (#327/#331).

**Application Process:** `GET_REQUEST_HISTORY_AJAX` — returns JSON history for status popups via `GET_REQUEST_HISTORY`.

---

## 5. FSD Narration Formats

All written by `NARRATE` with suffix `on DD-Mon-YY, at HH:MI am` and tag `[Ref TYPE-ID]`, dual-logged (actor + affected employee):

```
Contribution upload batch [batch_no] created by Maker [name] on DD-Mon-YY, at HH:MI am
Loan request [loan_no] for [employee] created by Maker [name] on DD-Mon-YY, at HH:MI am
Withdrawal request [wd_no] for [employee] created by Maker [name] on DD-Mon-YY, at HH:MI am
Lien marking request [lien_no] for [employee] created by Maker [name] on DD-Mon-YY, at HH:MI am
NOC issuance request [noc_no] for [employee] created by Maker [name] on DD-Mon-YY, at HH:MI am
Disablement request for [employee] created by Maker [name] on DD-Mon-YY, at HH:MI am
[Type] [ref_no] approved by Checker [name] on DD-Mon-YY, at HH:MI am
Loan request [ref_no] rejected by Checker [name] with remarks: [remarks] on DD-Mon-YY, at HH:MI am
Portfolio reallocation group [name] created/edited by Maker [name] on DD-Mon-YY, at HH:MI am
```

---

## 6. Status Lookup Rules

**Always use `EPF_STATUS_PKG` — never hardcode Status IDs.**

```sql
-- Get status ID from code (category REQUEST for this module)
v_status_id := EPF_STATUS_PKG.GET_ID('REQUEST', 'PENDING_CHECKER');

-- Get code from ID
v_code := EPF_STATUS_PKG.GET_CODE(v_status_id);
```

Status codes used in this module: `PENDING_CHECKER`, `PENDING_AUTHORIZER`, `AUTHORIZED`, `REJECTED` (category `REQUEST`). Feature-access / member statuses are plain check-constrained columns (`ENABLED`, `PENDING_ADDITION`, `PENDING_DELETION`) since they are list states, not workflow statuses.

---

## 7. Run Order

```
1.  db/01_ddl_new_objects.sql      (existing — run once)
2.  db/07_corp_admin_ddl.sql       (existing — activity logs, tokens)
3.  db/08_epf_email_pkg.sql        (existing — EPF_EMAIL_PKG)
4.  db/09_epf_auth_pkg.sql         (existing — EPF_AUTH_PKG / LOG_ACTIVITY)
5.  db/10_epf_corp_admin_pkg.sql   (existing — EPF_CORP_ADMIN_PKG)
6.  db/11_corp_txn_ddl.sql         (NEW — txn tables, sequences, seeds)
7.  db/12_epf_corp_txn_pkg.sql     (NEW — EPF_CORP_TXN_PKG)
```

---

## 8. File Inventory

| File | Description |
|------|-------------|
| `db/11_corp_txn_ddl.sql` | DDL: 12 tables, 5 sequences, indexes, guarded ALTERs, status seed |
| `db/12_epf_corp_txn_pkg.sql` | Maker/Checker transaction package (spec + body) |
| `apex/corp_maker_checker/page_processes.sql` | APEX PL/SQL processes for pages 40–45, 50–55, 60 + AJAX |
| `apex/corp_maker_checker/ir_queries.sql` | View All / Check page IR queries, page queries, LOVs |
| `apex/corp_maker_checker/html_templates.html` | Wizard, check-page, lien, settings templates + shared JS |
| `EPF_CORP_MAKER_CHECKER_GUIDE.md` | This guide |

---

## 9. Key Design Decisions

1. **Optional Checker enforced in one place:** `INITIAL_STATUS` / `HAS_ACTIVE_CHECKER` decide the entry status for every request, so the no-Checker bypass (FSD #4) can never be inconsistent between flows. Checker-terminal flows (Disable, Feature Access, Realloc) apply instantly when no Checker exists.

2. **Dual activity logging:** Every action is logged for both the actor (`USER_COMPANY_ID` of Maker/Checker) and the affected employee (resolved via `EPF_USER_COMPANIES.FOLIO_ID`), so both histories show the event — matching the status-popup history requirements (FSD #258/#261/#268/#271/#276).

3. **Request-scoped history via `[Ref TYPE-ID]` tag:** `EPF_ACTIVITY_LOGS` has no ref columns; `NARRATE` embeds a machine-readable tag that `GET_REQUEST_HISTORY` matches, keeping 07's table untouched.

4. **Notifications instead of e-mail:** the FSD says "system-generated alerts"; these are rows in `EPF_NOTIFICATIONS` (per-user, read flag) written by autonomous `NOTIFY`. `EPF_EMAIL_PKG` (db/08) is unchanged — none of its procedures fit these alert shapes.

5. **Errors block, alerts don't:** in contribution uploads only rows with `ROW_STATUS='ERROR'` block submission (FSD #225); duplicates and variance are informational. NOC-issued/disabled folios surface as 'Employee does not exist' (FSD #227).

6. **Flat-interest schedule:** the FSD extract does not prescribe amortization, so the schedule is equal principal + flat interest spread evenly, with the last instalment absorbing rounding residue (FSD #232 straight-line interpretation).

7. **Pending edits as JSON:** realloc-group edits live in `PENDING_CHANGES_JSON` while at the Checker so old data remains live; rejection simply discards the JSON (new groups are deleted outright, FSD #334).

8. **Soft state on folios:** `LIEN_MARKED`, `NOC_ISSUED`, `IS_DISABLED` flags on `EPF_FOLIOS` are only flipped by terminal events (authorizer completion / checker approval of disable), never by request creation.
