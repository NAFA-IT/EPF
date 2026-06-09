CREATE OR REPLACE PACKAGE EPF_AAML_PKG AS
-- ============================================================
--  AAML Maker / Checker – Central Business Logic Package
-- ============================================================

-- ── Onboarding ───────────────────────────────────────────────
PROCEDURE INIT_ONBOARDING (
    p_company_id        IN  NUMBER,
    p_user_id           IN  NUMBER,
    p_out_submission_id OUT NUMBER,
    p_out_ref_no        OUT VARCHAR2
);

PROCEDURE SAVE_TAB1_ACCOUNT (
    p_company_id         IN  NUMBER,
    p_company_name       IN  VARCHAR2,
    p_company_code       IN  VARCHAR2,
    p_ntn                IN  VARCHAR2,
    p_address            IN  VARCHAR2,
    p_city               IN  VARCHAR2,
    p_contact_email      IN  VARCHAR2,
    p_contact_phone      IN  VARCHAR2,
    p_group_id           IN  NUMBER,
    p_group_name_new     IN  VARCHAR2,
    p_fund_ids           IN  VARCHAR2,   -- colon-separated fund IDs
    p_contribution_pct   IN  NUMBER,
    p_employer_pct       IN  NUMBER,
    p_vesting_months     IN  NUMBER,
    p_min_contrib        IN  NUMBER,
    p_max_contrib        IN  NUMBER,
    p_performed_by       IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE SAVE_COMPANY_USER (
    p_company_id         IN  NUMBER,
    p_user_company_id    IN  NUMBER,
    p_folio_id           IN  NUMBER,
    p_role_id            IN  NUMBER,
    p_full_name          IN  VARCHAR2,
    p_email              IN  VARCHAR2,
    p_cnic               IN  VARCHAR2,
    p_mobile_no          IN  VARCHAR2,
    p_employee_code      IN  VARCHAR2,
    p_performed_by       IN  NUMBER,
    p_out_user_id        OUT NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE SAVE_AUTHORIZER_GROUP (
    p_group_id           IN  NUMBER,
    p_company_id         IN  NUMBER,
    p_group_name         IN  VARCHAR2,
    p_min_approvals      IN  NUMBER,
    p_member_user_ids    IN  VARCHAR2,   -- colon-separated USER_IDs
    p_performed_by       IN  NUMBER,
    p_out_group_id       OUT NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE SUBMIT_TO_CHECKER (
    p_company_id         IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

-- ── AAML Checker – Initial Onboarding ────────────────────────
PROCEDURE CHECKER_APPROVE (
    p_company_id         IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_remarks            IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE CHECKER_REVERT (
    p_company_id         IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_revert_remarks     IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

-- ── Change Request Flow ───────────────────────────────────────
PROCEDURE BEGIN_CHANGE_REQUEST (
    p_company_id         IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_change_req_id  OUT NUMBER,
    p_out_ref_no         OUT VARCHAR2
);

PROCEDURE SAVE_CR_SECTION (
    p_change_req_id      IN  NUMBER,
    p_section_code       IN  VARCHAR2,
    p_new_values_json    IN  CLOB,
    p_change_summary     IN  VARCHAR2,
    p_user_id            IN  NUMBER
);

PROCEDURE SUBMIT_CR_TO_CHECKER (
    p_change_req_id      IN  NUMBER,
    p_user_id            IN  NUMBER,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE CR_CHECKER_APPROVE (
    p_change_req_id      IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_remarks            IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

PROCEDURE CR_CHECKER_REVERT (
    p_change_req_id      IN  NUMBER,
    p_checker_id         IN  NUMBER,
    p_revert_remarks     IN  VARCHAR2,
    p_out_success        OUT VARCHAR2,
    p_out_message        OUT VARCHAR2
);

END EPF_AAML_PKG;
/
