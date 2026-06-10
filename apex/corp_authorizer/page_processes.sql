-- ============================================================
-- FILE: /home/user/EPF/apex/corp_authorizer/page_processes.sql
-- EPF PORTAL  –  Corporate Authorizer Module – APEX Page Processes
-- All processes are PL/SQL Anonymous Blocks to be pasted into
-- APEX Application Builder as "Execute PL/SQL Code" processes.
-- Binds: :APP_COMPANY_ID, :APP_USER_COMPANY_ID (application items).
-- FSD validations: #336-345
-- Pages 70-76 (parallel to Checker pages 50-55).
-- ============================================================

-- ============================================================
-- PAGE 70  –  Authorize Requests (Cards / Landing)
-- Items: P70_ACTIVE_COUNT (display only)
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P70_LOAD_PENDING_COUNT
-- When:    Before Header
-- Purpose: Count of requests pending this authorizer's decision.
-- ------------------------------------------------------------
DECLARE
    v_count NUMBER := 0;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM (
        -- CONTRIB pending
        SELECT 'CONTRIB' AS RTYPE, cb.BATCH_ID AS RID
          FROM EPF_CONTRIB_BATCHES cb
         WHERE cb.COMPANY_ID = :APP_COMPANY_ID
           AND EPF_STATUS_PKG.GET_CODE(cb.STATUS_ID) = 'PENDING_AUTHORIZER'
           AND NOT EXISTS (
               SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
                WHERE d.REQUEST_TYPE    = 'CONTRIB'
                  AND d.REQUEST_ID      = cb.BATCH_ID
                  AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
           )
        UNION ALL
        -- LOAN pending
        SELECT 'LOAN', lr.LOAN_ID
          FROM EPF_LOAN_REQUESTS lr
         WHERE lr.COMPANY_ID = :APP_COMPANY_ID
           AND EPF_STATUS_PKG.GET_CODE(lr.STATUS_ID) = 'PENDING_AUTHORIZER'
           AND NOT EXISTS (
               SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
                WHERE d.REQUEST_TYPE = 'LOAN' AND d.REQUEST_ID = lr.LOAN_ID
                  AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
           )
        UNION ALL
        -- WITHDRAWAL pending
        SELECT 'WITHDRAWAL', wr.WD_ID
          FROM EPF_WITHDRAWAL_REQUESTS wr
         WHERE wr.COMPANY_ID = :APP_COMPANY_ID
           AND EPF_STATUS_PKG.GET_CODE(wr.STATUS_ID) = 'PENDING_AUTHORIZER'
           AND NOT EXISTS (
               SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
                WHERE d.REQUEST_TYPE = 'WITHDRAWAL' AND d.REQUEST_ID = wr.WD_ID
                  AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
           )
        UNION ALL
        -- LIEN pending
        SELECT 'LIEN', lr2.LIEN_ID
          FROM EPF_LIEN_REQUESTS lr2
         WHERE lr2.COMPANY_ID = :APP_COMPANY_ID
           AND EPF_STATUS_PKG.GET_CODE(lr2.STATUS_ID) = 'PENDING_AUTHORIZER'
           AND NOT EXISTS (
               SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
                WHERE d.REQUEST_TYPE = 'LIEN' AND d.REQUEST_ID = lr2.LIEN_ID
                  AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
           )
        UNION ALL
        -- NOC pending
        SELECT 'NOC', nr.NOC_ID
          FROM EPF_NOC_REQUESTS nr
         WHERE nr.COMPANY_ID = :APP_COMPANY_ID
           AND EPF_STATUS_PKG.GET_CODE(nr.STATUS_ID) = 'PENDING_AUTHORIZER'
           AND NOT EXISTS (
               SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
                WHERE d.REQUEST_TYPE = 'NOC' AND d.REQUEST_ID = nr.NOC_ID
                  AND d.AUTHORIZER_UCID = :APP_USER_COMPANY_ID
           )
      );
    :P70_ACTIVE_COUNT := v_count;
END;

-- ============================================================
-- PAGE 71  –  Authorize Contribution Uploads
-- Items: P71_SELECTED_IDS (colon-separated BATCH_IDs),
--        P71_REMARKS, P71_DECISION (APPROVE/REJECT),
--        P71_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P71_AUTHORIZE_CONTRIB
-- When:    On Submit
-- Condition: Request IN ('APPROVE_CONTRIB','REJECT_CONTRIB')
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_ids      VARCHAR2(4000) := :P71_SELECTED_IDS;
    v_decision VARCHAR2(10)   := CASE :REQUEST
                                     WHEN 'APPROVE_CONTRIB' THEN 'APPROVE'
                                     WHEN 'REJECT_CONTRIB'  THEN 'REJECT'
                                 END;
    v_pos      PLS_INTEGER    := 1;
    v_nxt      PLS_INTEGER;
    v_id_str   VARCHAR2(30);
    v_batch_id NUMBER;
BEGIN
    IF v_ids IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one contribution upload to authorize.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    -- Iterate colon-separated IDs
    LOOP
        v_nxt := INSTR(v_ids, ':', v_pos);
        IF v_nxt = 0 THEN
            v_id_str := SUBSTR(v_ids, v_pos);
        ELSE
            v_id_str := SUBSTR(v_ids, v_pos, v_nxt - v_pos);
            v_pos    := v_nxt + 1;
        END IF;

        v_id_str := TRIM(v_id_str);
        IF v_id_str IS NOT NULL THEN
            v_batch_id := TO_NUMBER(v_id_str);
            EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST(
                p_request_type    => 'CONTRIB',
                p_request_id      => v_batch_id,
                p_authorizer_ucid => :APP_USER_COMPANY_ID,
                p_decision        => v_decision,
                p_remarks         => :P71_REMARKS,
                p_out_success     => v_success,
                p_out_message     => v_message
            );
            IF v_success = 'N' THEN
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'Batch ' || v_batch_id || ': ' || v_message,
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
            END IF;
        END IF;

        EXIT WHEN v_nxt = 0;
    END LOOP;

    :P71_SELECTED_IDS := NULL;
    :P71_REMARKS      := NULL;
    :P71_SUCCESS_MSG  := 'Contribution upload(s) ' || LOWER(v_decision) || 'd successfully.';
END;

-- ============================================================
-- PAGE 72  –  Authorize Loan Requests
-- Items: P72_SELECTED_IDS, P72_REMARKS, P72_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P72_AUTHORIZE_LOAN
-- When:    On Submit
-- Condition: Request IN ('APPROVE_LOAN','REJECT_LOAN')
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_ids      VARCHAR2(4000) := :P72_SELECTED_IDS;
    v_decision VARCHAR2(10)   := CASE :REQUEST
                                     WHEN 'APPROVE_LOAN' THEN 'APPROVE'
                                     WHEN 'REJECT_LOAN'  THEN 'REJECT'
                                 END;
    v_pos      PLS_INTEGER    := 1;
    v_nxt      PLS_INTEGER;
    v_id_str   VARCHAR2(30);
    v_loan_id  NUMBER;
BEGIN
    IF v_ids IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one loan request to authorize.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    LOOP
        v_nxt := INSTR(v_ids, ':', v_pos);
        IF v_nxt = 0 THEN v_id_str := SUBSTR(v_ids, v_pos);
        ELSE v_id_str := SUBSTR(v_ids, v_pos, v_nxt - v_pos); v_pos := v_nxt + 1; END IF;

        v_id_str := TRIM(v_id_str);
        IF v_id_str IS NOT NULL THEN
            v_loan_id := TO_NUMBER(v_id_str);
            EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST(
                p_request_type    => 'LOAN',
                p_request_id      => v_loan_id,
                p_authorizer_ucid => :APP_USER_COMPANY_ID,
                p_decision        => v_decision,
                p_remarks         => :P72_REMARKS,
                p_out_success     => v_success,
                p_out_message     => v_message
            );
            IF v_success = 'N' THEN
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'Loan ' || v_loan_id || ': ' || v_message,
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
            END IF;
        END IF;
        EXIT WHEN v_nxt = 0;
    END LOOP;

    :P72_SELECTED_IDS := NULL;
    :P72_REMARKS      := NULL;
    :P72_SUCCESS_MSG  := 'Loan request(s) ' || LOWER(v_decision) || 'd successfully.';
END;

-- ============================================================
-- PAGE 73  –  Authorize Withdrawal Requests
-- Items: P73_SELECTED_IDS, P73_REMARKS, P73_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P73_AUTHORIZE_WITHDRAWAL
-- When:    On Submit
-- Condition: Request IN ('APPROVE_WD','REJECT_WD')
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_ids      VARCHAR2(4000) := :P73_SELECTED_IDS;
    v_decision VARCHAR2(10)   := CASE :REQUEST
                                     WHEN 'APPROVE_WD' THEN 'APPROVE'
                                     WHEN 'REJECT_WD'  THEN 'REJECT'
                                 END;
    v_pos      PLS_INTEGER    := 1;
    v_nxt      PLS_INTEGER;
    v_id_str   VARCHAR2(30);
    v_wd_id    NUMBER;
BEGIN
    IF v_ids IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one withdrawal request to authorize.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    LOOP
        v_nxt := INSTR(v_ids, ':', v_pos);
        IF v_nxt = 0 THEN v_id_str := SUBSTR(v_ids, v_pos);
        ELSE v_id_str := SUBSTR(v_ids, v_pos, v_nxt - v_pos); v_pos := v_nxt + 1; END IF;

        v_id_str := TRIM(v_id_str);
        IF v_id_str IS NOT NULL THEN
            v_wd_id := TO_NUMBER(v_id_str);
            EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST(
                p_request_type    => 'WITHDRAWAL',
                p_request_id      => v_wd_id,
                p_authorizer_ucid => :APP_USER_COMPANY_ID,
                p_decision        => v_decision,
                p_remarks         => :P73_REMARKS,
                p_out_success     => v_success,
                p_out_message     => v_message
            );
            IF v_success = 'N' THEN
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'Withdrawal ' || v_wd_id || ': ' || v_message,
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
            END IF;
        END IF;
        EXIT WHEN v_nxt = 0;
    END LOOP;

    :P73_SELECTED_IDS := NULL;
    :P73_REMARKS      := NULL;
    :P73_SUCCESS_MSG  := 'Withdrawal request(s) ' || LOWER(v_decision) || 'd successfully.';
END;

-- ============================================================
-- PAGE 74  –  Authorize Lien Requests
-- Items: P74_SELECTED_IDS, P74_REMARKS, P74_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P74_AUTHORIZE_LIEN
-- When:    On Submit
-- Condition: Request IN ('APPROVE_LIEN','REJECT_LIEN')
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_ids      VARCHAR2(4000) := :P74_SELECTED_IDS;
    v_decision VARCHAR2(10)   := CASE :REQUEST
                                     WHEN 'APPROVE_LIEN' THEN 'APPROVE'
                                     WHEN 'REJECT_LIEN'  THEN 'REJECT'
                                 END;
    v_pos      PLS_INTEGER    := 1;
    v_nxt      PLS_INTEGER;
    v_id_str   VARCHAR2(30);
    v_lien_id  NUMBER;
BEGIN
    IF v_ids IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one lien request to authorize.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    LOOP
        v_nxt := INSTR(v_ids, ':', v_pos);
        IF v_nxt = 0 THEN v_id_str := SUBSTR(v_ids, v_pos);
        ELSE v_id_str := SUBSTR(v_ids, v_pos, v_nxt - v_pos); v_pos := v_nxt + 1; END IF;

        v_id_str := TRIM(v_id_str);
        IF v_id_str IS NOT NULL THEN
            v_lien_id := TO_NUMBER(v_id_str);
            EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST(
                p_request_type    => 'LIEN',
                p_request_id      => v_lien_id,
                p_authorizer_ucid => :APP_USER_COMPANY_ID,
                p_decision        => v_decision,
                p_remarks         => :P74_REMARKS,
                p_out_success     => v_success,
                p_out_message     => v_message
            );
            IF v_success = 'N' THEN
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'Lien ' || v_lien_id || ': ' || v_message,
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
            END IF;
        END IF;
        EXIT WHEN v_nxt = 0;
    END LOOP;

    :P74_SELECTED_IDS := NULL;
    :P74_REMARKS      := NULL;
    :P74_SUCCESS_MSG  := 'Lien request(s) ' || LOWER(v_decision) || 'd successfully.';
END;

-- ============================================================
-- PAGE 75  –  Authorize NOC Requests
-- Items: P75_SELECTED_IDS, P75_REMARKS, P75_SUCCESS_MSG
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P75_AUTHORIZE_NOC
-- When:    On Submit
-- Condition: Request IN ('APPROVE_NOC','REJECT_NOC')
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_ids      VARCHAR2(4000) := :P75_SELECTED_IDS;
    v_decision VARCHAR2(10)   := CASE :REQUEST
                                     WHEN 'APPROVE_NOC' THEN 'APPROVE'
                                     WHEN 'REJECT_NOC'  THEN 'REJECT'
                                 END;
    v_pos      PLS_INTEGER    := 1;
    v_nxt      PLS_INTEGER;
    v_id_str   VARCHAR2(30);
    v_noc_id   NUMBER;
BEGIN
    IF v_ids IS NULL THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => 'Please select at least one NOC request to authorize.',
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    LOOP
        v_nxt := INSTR(v_ids, ':', v_pos);
        IF v_nxt = 0 THEN v_id_str := SUBSTR(v_ids, v_pos);
        ELSE v_id_str := SUBSTR(v_ids, v_pos, v_nxt - v_pos); v_pos := v_nxt + 1; END IF;

        v_id_str := TRIM(v_id_str);
        IF v_id_str IS NOT NULL THEN
            v_noc_id := TO_NUMBER(v_id_str);
            EPF_AUTHORIZER_PKG.AUTHORIZE_REQUEST(
                p_request_type    => 'NOC',
                p_request_id      => v_noc_id,
                p_authorizer_ucid => :APP_USER_COMPANY_ID,
                p_decision        => v_decision,
                p_remarks         => :P75_REMARKS,
                p_out_success     => v_success,
                p_out_message     => v_message
            );
            IF v_success = 'N' THEN
                APEX_ERROR.ADD_ERROR(
                    p_message          => 'NOC ' || v_noc_id || ': ' || v_message,
                    p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
                );
            END IF;
        END IF;
        EXIT WHEN v_nxt = 0;
    END LOOP;

    :P75_SELECTED_IDS := NULL;
    :P75_REMARKS      := NULL;
    :P75_SUCCESS_MSG  := 'NOC request(s) ' || LOWER(v_decision) || 'd successfully.';
END;

-- ============================================================
-- PAGE 76  –  Settings: Loan Settings Authorization
-- Items: P76_REMARKS, P76_SUCCESS_MSG, P76_DECISION
-- FSD #339-340: Authorizer reviews pending loan settings changes
-- ============================================================

-- ------------------------------------------------------------
-- PROCESS: P76_AUTHORIZE_LOAN_SETTINGS
-- When:    On Submit
-- Condition: Request IN ('APPROVE_LOAN_SETTINGS','REJECT_LOAN_SETTINGS')
-- ------------------------------------------------------------
DECLARE
    v_success  VARCHAR2(1);
    v_message  VARCHAR2(4000);
    v_decision VARCHAR2(10) := CASE :REQUEST
                                   WHEN 'APPROVE_LOAN_SETTINGS' THEN 'APPROVE'
                                   WHEN 'REJECT_LOAN_SETTINGS'  THEN 'REJECT'
                               END;
BEGIN
    EPF_AUTHORIZER_PKG.AUTHORIZE_LOAN_SETTINGS(
        p_company_id      => :APP_COMPANY_ID,
        p_authorizer_ucid => :APP_USER_COMPANY_ID,
        p_decision        => v_decision,
        p_remarks         => :P76_REMARKS,
        p_out_success     => v_success,
        p_out_message     => v_message
    );

    IF v_success = 'N' THEN
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION
        );
        RETURN;
    END IF;

    :P76_REMARKS     := NULL;
    :P76_SUCCESS_MSG := v_message;
END;

-- ============================================================
-- END of corp_authorizer/page_processes.sql
-- ============================================================
