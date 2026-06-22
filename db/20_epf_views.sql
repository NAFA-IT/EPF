-- ============================================================
-- FILE: /home/user/EPF/db/20_epf_views.sql
-- EPF PORTAL  –  Application Views
-- All views match the definitions confirmed in the live DB.
-- Depends on: EPF_COMPANIES, EPF_COMPANY_GROUPS, EPF_USERS,
--             EPF_USER_COMPANIES, EPF_USER_COMP_ROLES, EPF_ROLES,
--             EPF_STATUSES, EPF_STATUS_PKG, EPF_FOLIOS,
--             EPF_COMPANY_FUNDS, EPF_FUNDS, EPF_COMPANY_SETTINGS,
--             EPF_CLIENT_CHANGE_REQUESTS,
--             EPF_CONTRIBUTION_BATCHES, EPF_LOAN_REQUESTS,
--             EPF_WITHDRAWAL_REQUESTS
-- Run order: after all DDL scripts, before package compilation.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  1. EPF_V_USER_COMPANIES
--  Used by: EPF_POST_AUTH, SET_SESSION_DETAILS app process,
--           Page 100 (company/role selector), authorization schemes.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW EPF_V_USER_COMPANIES AS
SELECT
    uc.user_company_id,
    uc.user_id,
    u.email,
    u.full_name,
    u.status_id,
    uc.company_id,
    c.group_id,
    c.company_name,
    cg.group_name,
    uc.is_default,
    st_uc.status_code   AS user_company_status,
    st_co.status_code   AS company_status,
    (SELECT COUNT(*)
       FROM epf_user_comp_roles ur
      WHERE ur.user_company_id = uc.user_company_id
        AND ur.is_active = 'Y') AS role_count
  FROM epf_user_companies uc
  JOIN epf_users           u     ON uc.user_id    = u.user_id
  JOIN epf_companies       c     ON uc.company_id = c.company_id
  JOIN epf_company_groups  cg    ON c.group_id    = cg.group_id
  JOIN epf_statuses        st_uc ON uc.status_id  = st_uc.status_id
  JOIN epf_statuses        st_co ON c.status_id   = st_co.status_id;
/

-- ─────────────────────────────────────────────────────────────
--  2. EPF_V_USER_ROLES
--  Flat view of every active role assignment with role details.
--  Used by authorization schemes and role-selection page (100).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW EPF_V_USER_ROLES AS
SELECT
    ucr.user_company_id,
    uc.user_id,
    uc.company_id,
    ucr.role_id,
    r.role_code,
    r.role_name,
    r.role_level,
    ucr.is_active
  FROM epf_user_comp_roles ucr
  JOIN epf_user_companies  uc ON uc.user_company_id = ucr.user_company_id
  JOIN epf_roles            r ON r.role_id           = ucr.role_id
 WHERE ucr.is_active = 'Y';
/

-- ─────────────────────────────────────────────────────────────
--  3. V_EPF_CHANGE_REQUESTS
--  Used by: AAML Checker pages (CR review), client detail page.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_CHANGE_REQUESTS AS
WITH maker_mapping AS (
    SELECT email, full_name, user_id
      FROM (
               SELECT email, full_name, user_id,
                      ROW_NUMBER() OVER (PARTITION BY email ORDER BY user_id) AS rn
                 FROM epf_users
           )
     WHERE rn = 1
)
SELECT
    cr.change_req_id,
    cr.change_ref_no,
    cr.ref_no,
    cr.company_id,
    c.company_name,
    cr.change_type,
    cr.section_changed,
    cr.remarks,
    cr.checker_remarks,
    cr.status_id,
    st.status_code    AS req_status_code,
    st.status_label   AS req_status_label,
    st.css_class      AS req_status_css,
    cr.created_date,
    cr.created_by,
    cr.reviewed_date,
    cr.reviewed_by,
    cr.checked_date,
    cr.checker_id,
    u_maker.full_name AS maker_name,
    u_chkr.full_name  AS checker_name
  FROM epf_client_change_requests cr
  JOIN epf_companies  c      ON c.company_id  = cr.company_id
  JOIN epf_statuses   st     ON st.status_id  = cr.status_id
  LEFT JOIN maker_mapping u_maker ON u_maker.email  = cr.created_by
  LEFT JOIN epf_users     u_chkr  ON u_chkr.user_id = TO_NUMBER(cr.checker_id);
/

-- ─────────────────────────────────────────────────────────────
--  4. V_EPF_CLIENT_DASHBOARD
--  Used by: AAML client list (pages 3, 207), dashboard widgets.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_CLIENT_DASHBOARD AS
SELECT
    c.company_id,
    c.ref_no,
    c.company_code,
    c.company_name,
    cg.group_name,
    c.is_primary,
    c.ntn,
    c.secp_reg_no,
    c.primary_email,
    c.primary_phone,
    c.city,
    c.onboarding_date,
    st.status_code   AS client_status_code,
    st.status_label  AS client_status_label,
    st.css_class     AS status_css_class,
    (SELECT f.fund_name
       FROM epf_company_funds cf
       JOIN epf_funds f ON f.fund_id = cf.fund_id
      WHERE cf.company_id    = c.company_id
        AND cf.display_order = 1
        AND ROWNUM = 1)  AS fund1_name,
    (SELECT f.fund_name
       FROM epf_company_funds cf
       JOIN epf_funds f ON f.fund_id = cf.fund_id
      WHERE cf.company_id    = c.company_id
        AND cf.display_order = 2
        AND ROWNUM = 1)  AS fund2_name,
    (SELECT COUNT(*)
       FROM epf_user_companies uc
      WHERE uc.company_id = c.company_id
        AND uc.status_id  = epf_status_pkg.get_id('USER_STATUS','ACTIVE')) AS active_user_count,
    c.created_date,
    c.updated_date,
    c.created_by
  FROM epf_companies      c
  JOIN epf_company_groups cg ON cg.group_id  = c.group_id
  JOIN epf_statuses       st ON st.status_id = c.status_id
                             AND st.category_code = 'CLIENT_STATUS';
/

-- ─────────────────────────────────────────────────────────────
--  5. V_EPF_CLIENT_DETAIL
--  Used by: client detail page (208/4), onboarding review.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_CLIENT_DETAIL AS
SELECT
    c.company_id,
    c.ref_no,
    c.company_name,
    c.company_full_name,
    c.company_code,
    c.ntn,
    c.secp_reg_no,
    c.registered_address,
    c.city,
    c.country,
    c.primary_email,
    c.primary_phone,
    c.dfn_account_code,
    c.group_id,
    cg.group_name,
    c.is_primary,
    c.onboarding_date,
    c.status_id,
    st.status_code     AS client_status_code,
    st.status_label    AS client_status_label,
    cf1.fund_id        AS fund1_id,
    f1.fund_name       AS fund1_name,
    f1.fund_code       AS fund1_code,
    cf2.fund_id        AS fund2_id,
    f2.fund_name       AS fund2_name,
    f2.fund_code       AS fund2_code,
    cs.loan_enabled,
    cs.interest_type_status_id,
    cs_int.status_label AS interest_type_label,
    cs.interest_rate_pct,
    cs.max_loan_pct,
    cs.max_instalment_months,
    cs.floating_rate_tenure_mo,
    cs.withdrawal_enabled,
    cs.withdrawal_avail_all_emp,
    cs.reallocation_enabled,
    c.allow_fund_switching,
    c.allow_loan_requests,
    c.allow_noc_requests,
    c.allow_withdrawals
  FROM epf_companies       c
  JOIN epf_company_groups  cg  ON cg.group_id  = c.group_id
  JOIN epf_statuses        st  ON st.status_id = c.status_id
                              AND st.category_code = 'CLIENT_STATUS'
  LEFT JOIN epf_company_funds cf1 ON cf1.company_id    = c.company_id
                                 AND cf1.display_order = 1
  LEFT JOIN epf_funds         f1  ON f1.fund_id = cf1.fund_id
  LEFT JOIN epf_company_funds cf2 ON cf2.company_id    = c.company_id
                                 AND cf2.display_order = 2
  LEFT JOIN epf_funds         f2  ON f2.fund_id = cf2.fund_id
  LEFT JOIN epf_company_settings cs    ON cs.company_id    = c.company_id
  LEFT JOIN epf_statuses         cs_int ON cs_int.status_id = cs.interest_type_status_id;
/

-- ─────────────────────────────────────────────────────────────
--  6. V_EPF_COMPANY_EMPLOYEES
--  Used by: Corp Maker employee selection (loan/withdrawal/lien/
--           NOC/disable pages), AAML employee details page (5).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_COMPANY_EMPLOYEES AS
SELECT
    u.user_id,
    uc.user_company_id,
    uc.company_id,
    c.company_name,
    u.full_name,
    u.email,
    u.cnic,
    u.mobile_no,
    u.employee_code,
    u.designation,
    u.date_of_joining,
    u.date_of_birth,
    u.gender,
    u.dfn_investor_id,
    st_u.status_code   AS user_status_code,
    st_u.status_label  AS user_status_label,
    st_u.css_class     AS user_status_css,
    uc.folio_id,
    fo.folio_number,
    fo.is_lien_marked,
    fo.lien_amount,
    (SELECT LISTAGG(r.role_name, ', ') WITHIN GROUP (ORDER BY r.role_name)
       FROM epf_user_comp_roles ucr
       JOIN epf_roles r ON r.role_id = ucr.role_id
      WHERE ucr.user_company_id = uc.user_company_id
        AND ucr.is_active = 'Y') AS roles_list,
    uc.created_date    AS enrolled_date
  FROM epf_users          u
  JOIN epf_user_companies uc   ON uc.user_id   = u.user_id
  JOIN epf_companies      c    ON c.company_id = uc.company_id
  JOIN epf_statuses       st_u ON st_u.status_id = uc.status_id
  LEFT JOIN epf_folios    fo   ON fo.folio_id  = uc.folio_id;
/

-- ─────────────────────────────────────────────────────────────
--  7. V_EPF_CONTRIBUTION_BATCHES
--  Used by: Corp Maker batch list (402), Checker/Authorizer
--           pending request pages (501, 601).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_CONTRIBUTION_BATCHES AS
SELECT
    cb.batch_id,
    cb.batch_ref,
    cb.company_id,
    c.company_name,
    cb.fund_id,
    f.fund_name,
    cb.contribution_month,
    TO_CHAR(cb.contribution_month, 'Mon-YYYY') AS contrib_period,
    cb.total_employees,
    cb.total_amount,
    cb.file_name,
    cb.status_id,
    st.status_code  AS batch_status_code,
    st.status_label AS batch_status_label,
    st.css_class    AS status_css,
    cb.checker_remarks,
    cb.authorizer_remarks,
    cb.aaml_remarks,
    cb.created_date,
    cb.created_by
  FROM epf_contribution_batches cb
  JOIN epf_companies c  ON c.company_id = cb.company_id
  JOIN epf_funds     f  ON f.fund_id    = cb.fund_id
  JOIN epf_statuses  st ON st.status_id = cb.status_id;
/

-- ─────────────────────────────────────────────────────────────
--  8. V_EPF_LOAN_REQUESTS
--  Used by: Corp Maker loan list (404), Checker/Authorizer
--           pending request pages (501, 601).
--  Note: EPF_LOAN_REQUESTS links via FOLIO_ID → EPF_FOLIOS →
--        EPF_USER_COMPANIES → EPF_USERS for employee details.
--        Actual table columns: LOAN_NO, AMOUNT, INTEREST_RATE,
--        MONTHLY_INSTALMENT, INTEREST_TYPE, MAKER_UCID.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_LOAN_REQUESTS AS
SELECT
    lr.loan_id,
    lr.loan_no                          AS loan_ref,
    lr.company_id,
    c.company_name,
    uc.user_id                          AS employee_id,
    u.full_name                         AS employee_name,
    u.employee_code,
    NVL(u.cnic, fo.cnic)                AS cnic,
    lr.amount                           AS loan_amount,
    lr.interest_rate                    AS interest_rate_pct,
    lr.instalment_months,
    lr.monthly_instalment               AS instalment_amount,
    lr.interest_type                    AS loan_purpose,
    lr.status_id,
    st.status_code                      AS loan_status_code,
    st.status_label                     AS loan_status_label,
    st.css_class                        AS status_css,
    lr.checker_remarks,
    NULL                                AS authorizer_remarks,
    NULL                                AS aaml_remarks,
    lr.authorized_date                  AS disbursement_date,
    lr.maker_date                       AS created_date,
    mu.email                            AS created_by
  FROM epf_loan_requests lr
  JOIN epf_companies      c   ON c.company_id      = lr.company_id
  JOIN epf_folios         fo  ON fo.folio_id        = lr.folio_id
  JOIN epf_statuses       st  ON st.status_id       = lr.status_id
  JOIN epf_user_companies uc  ON uc.folio_id        = lr.folio_id
  JOIN epf_users          u   ON u.user_id          = uc.user_id
  JOIN epf_user_companies muc ON muc.user_company_id = lr.maker_ucid
  JOIN epf_users          mu  ON mu.user_id         = muc.user_id;
/

-- ─────────────────────────────────────────────────────────────
--  9. V_EPF_WITHDRAWAL_REQUESTS
--  Used by: Corp Maker withdrawal list (406), Checker/Authorizer
--           pending request pages (501, 601).
--  Note: EPF_WITHDRAWAL_REQUESTS links via FOLIO_ID.
--        Actual table columns: WD_NO, AMOUNT, WD_TYPE, REASON,
--        MAKER_UCID.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW V_EPF_WITHDRAWAL_REQUESTS AS
SELECT
    wr.wd_id                            AS withdrawal_id,
    wr.wd_no                            AS withdrawal_ref,
    wr.company_id,
    c.company_name,
    uc.user_id                          AS employee_id,
    u.full_name                         AS employee_name,
    u.employee_code,
    NVL(u.cnic, fo.cnic)                AS cnic,
    wr.amount                           AS withdrawal_amount,
    wr.reason                           AS withdrawal_reason,
    NULL                                AS bank_name,
    NULL                                AS account_title,
    NULL                                AS iban,
    wr.status_id,
    st.status_code                      AS wd_status_code,
    st.status_label                     AS wd_status_label,
    st.css_class                        AS status_css,
    wr.checker_remarks,
    NULL                                AS authorizer_remarks,
    NULL                                AS aaml_remarks,
    wr.maker_date                       AS created_date,
    mu.email                            AS created_by
  FROM epf_withdrawal_requests wr
  JOIN epf_companies      c   ON c.company_id       = wr.company_id
  JOIN epf_folios         fo  ON fo.folio_id         = wr.folio_id
  JOIN epf_statuses       st  ON st.status_id        = wr.status_id
  JOIN epf_user_companies uc  ON uc.folio_id         = wr.folio_id
  JOIN epf_users          u   ON u.user_id           = uc.user_id
  JOIN epf_user_companies muc ON muc.user_company_id = wr.maker_ucid
  JOIN epf_users          mu  ON mu.user_id          = muc.user_id;
/

-- ============================================================
-- End of 20_epf_views.sql
-- ============================================================
