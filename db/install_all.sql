-- ============================================================
-- FILE: /home/user/EPF/db/install_all.sql
-- EPF PORTAL  –  Master Install Script
-- Runs all DDL and package scripts in dependency order.
-- Execute from the db/ directory in SQL*Plus:
--   SQL> @install_all.sql
-- Or from the repo root:
--   SQL> @db/install_all.sql
-- ============================================================

-- Stop on first unhandled error (SQL*Plus)
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT EPF PORTAL  –  Full Install
PROMPT ============================================================

-- ── Step 00: Pure-PL/SQL crypto (replaces DBMS_CRYPTO) ───────
PROMPT
PROMPT [00] UC_CRYPTO package ...
@@00_uc_crypto_pkg.sql

-- ── Step 01: Core DDL (tables, sequences) ────────────────────
PROMPT
PROMPT [01] Core DDL ...
@@01_ddl_new_objects.sql

-- ── Step 05b: Table corrections / missing columns ─────────────
PROMPT
PROMPT [05b] Table corrections ...
@@05b_table_corrections.sql

-- ── Step 03: AAML package body ───────────────────────────────
PROMPT
PROMPT [03] EPF_AAML_PKG body ...
@@03_epf_aaml_pkg_body.sql

-- ── Step 04: Employee sync package ───────────────────────────
PROMPT
PROMPT [04] EPF_EMP_SYNC_PKG ...
@@04_epf_emp_sync_pkg.sql

-- ── Step 06: AAML package addons ─────────────────────────────
PROMPT
PROMPT [06] EPF_AAML_PKG addons ...
@@06_epf_aaml_pkg_addons.sql

-- ── Step 07: Corporate admin DDL ─────────────────────────────
PROMPT
PROMPT [07] Corporate admin DDL ...
@@07_corp_admin_ddl.sql

-- ── Step 08: Email package ───────────────────────────────────
PROMPT
PROMPT [08] EPF_EMAIL_PKG ...
@@08_epf_email_pkg.sql

-- ── Step 09: Auth package ────────────────────────────────────
PROMPT
PROMPT [09] EPF_AUTH_PKG ...
@@09_epf_auth_pkg.sql

-- ── Step 10: Corporate admin package ─────────────────────────
PROMPT
PROMPT [10] EPF_CORP_ADMIN_PKG ...
@@10_epf_corp_admin_pkg.sql

-- ── Step 11: Corporate transaction DDL ───────────────────────
PROMPT
PROMPT [11] Corporate transaction DDL ...
@@11_corp_txn_ddl.sql

-- ── Step 12: Corporate transaction package ────────────────────
PROMPT
PROMPT [12] EPF_CORP_TXN_PKG ...
@@12_epf_corp_txn_pkg.sql

-- ── Step 13: Authorizer / employee DDL ───────────────────────
PROMPT
PROMPT [13] Authorizer / employee DDL ...
@@13_authorizer_employee_ddl.sql

-- ── Step 14: Email package addons ────────────────────────────
PROMPT
PROMPT [14] EPF_EMAIL_PKG addons ...
@@14_epf_email_pkg_addons.sql

-- ── Step 15: Authorizer package ──────────────────────────────
PROMPT
PROMPT [15] EPF_AUTHORIZER_PKG ...
@@15_epf_authorizer_pkg.sql

-- ── Step 16: Employee package ────────────────────────────────
PROMPT
PROMPT [16] EPF_EMPLOYEE_PKG ...
@@16_epf_employee_pkg.sql

-- ── Final: Verify everything compiled OK ─────────────────────
PROMPT
PROMPT [VERIFY] Running post-install checks ...
@@verify_all.sql

PROMPT
PROMPT ============================================================
PROMPT Install complete.
PROMPT ============================================================
