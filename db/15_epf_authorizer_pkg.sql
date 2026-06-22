-- ============================================================
-- FILE: /home/user/EPF/db/15_epf_authorizer_pkg.sql
-- EPF PORTAL  –  Authorizer Package (Spec + Body)
-- EPF_AUTHORIZER_PKG  –  Multi-Authorizer workflow engine
-- FSD validations: #336-345 (Authorize Requests, Settings),
--   multi-authorizer matrix rules (#90-#94).
-- Depends on: 11_corp_txn_ddl.sql, 12_epf_corp_txn_pkg.sql,
--             13_authorizer_employee_ddl.sql,
--             14_epf_email_pkg_addons.sql, EPF_STATUS_PKG,
--             EPF_AUTH_PKG.
-- NOTE: Do NOT recreate EPF_CORP_TXN_PKG here.
-- ============================================================

-- ── Package Specification ─────────────────────────────────────
CREATE OR REPLACE PACKAGE EPF_AUTHORIZER_PKG AS
-- ============================================================
--  EPF_AUTHORIZER_PKG  –  Authorizer workflow for EPF Portal
--  Multi-Authorizer: ALL active authorizers of a company must
--  approve a request before it becomes AUTHORIZED.
-- ============================================================

    -- ── Main decision procedure (FSD #336-337) ─────────────────
    -- p_request_type: CONTRIB | LOAN | WITHDRAWAL | LIEN | NOC
    -- p_decision    : APPROVE | REJECT (remarks mandatory on reject)
    PROCEDURE AUTHORIZE_REQUEST (
        p_request_type    IN  VARCHAR2,
        p_request_id      IN  NUMBER,
        p_authorizer_ucid IN  NUMBER,
        p_decision        IN  VARCHAR2,
        p_remarks         IN  VARCHAR2 DEFAULT NULL,
        p_out_success     OUT VARCHAR2,
        p_out_message     OUT VARCHAR2
    );

    -- ── Loan Settings authorization (FSD #339-340, narration 9.6)
    PROCEDURE AUTHORIZE_LOAN_SETTINGS (
        p_company_id      IN  NUMBER,
        p_authorizer_ucid IN  NUMBER,
        p_decision        IN  VARCHAR2,
        p_remarks         IN  VARCHAR2 DEFAULT NULL,
        p_out_success     OUT VARCHAR2,
        p_out_message     OUT VARCHAR2
    );

    -- ── Request history (FSD #258/#261/#268/#271) ───────────────
    -- Same pattern as EPF_CORP_TXN_PKG.GET_REQUEST_HISTORY
    FUNCTION GET_REQUEST_HISTORY (
        p_ref_type IN VARCHAR2,
        p_ref_id   IN NUMBER
    ) RETURN SYS_REFCURSOR;

    -- ── Authorizer decisions view for a request ─────────────────
    -- Returns who has approved/rejected and who is still pending
    FUNCTION GET_AUTHORIZER_DECISIONS (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER
    ) RETURN SYS_REFCURSOR;

END EPF_AUTHORIZER_PKG;
/

-- ── Package Body ──────────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY EPF_AUTHORIZER_PKG AS
-- ============================================================
--  EPF_AUTHORIZER_PKG  –  Body
-- ============================================================

    -- ═══════════════════════════════════════════════════════════
    --  PRIVATE HELPERS
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────
    --  GET_AUTHORIZER_COUNT
    --  Returns the count of required authorizers for a company.
    --  Uses EPF_AUTHORIZER_GROUPS + EPF_AUTHORIZER_GROUP_MEMBERS
    --  where is_active = 'Y' and status active (FSD #90-94).
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_AUTHORIZER_COUNT (
        p_company_id IN NUMBER
    ) RETURN NUMBER IS
        v_cnt NUMBER := 0;
    BEGIN
        -- Count all active CORP_AUTHORIZER role assignments for the company
        SELECT COUNT(DISTINCT uc.USER_COMPANY_ID)
          INTO v_cnt
          FROM EPF_USER_COMPANIES  uc
          JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
          JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
         WHERE uc.COMPANY_ID = p_company_id
           AND ucr.IS_ACTIVE  = 'Y'
           AND r.ROLE_CODE    = 'CORP_AUTHORIZER'
           AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE';
        RETURN GREATEST(v_cnt, 1);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 1;
    END GET_AUTHORIZER_COUNT;

    -- ─────────────────────────────────────────────────────────
    --  GET_APPROVAL_COUNT
    --  Count of APPROVE decisions recorded for a request.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_APPROVAL_COUNT (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER
    ) RETURN NUMBER IS
        v_cnt NUMBER := 0;
    BEGIN
        SELECT COUNT(*)
          INTO v_cnt
          FROM EPF_AUTHORIZER_DECISIONS
         WHERE REQUEST_TYPE = p_request_type
           AND REQUEST_ID   = p_request_id
           AND DECISION     = 'APPROVE';
        RETURN v_cnt;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END GET_APPROVAL_COUNT;

    -- ─────────────────────────────────────────────────────────
    --  GET_ACTOR_NAME
    --  Returns FULL_NAME for a USER_COMPANY_ID.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_ACTOR_NAME (
        p_ucid IN NUMBER
    ) RETURN VARCHAR2 IS
        v_name VARCHAR2(200);
    BEGIN
        SELECT u.FULL_NAME
          INTO v_name
          FROM EPF_USER_COMPANIES uc
          JOIN EPF_USERS          u ON u.USER_ID = uc.USER_ID
         WHERE uc.USER_COMPANY_ID = p_ucid;
        RETURN v_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'Unknown';
    END GET_ACTOR_NAME;

    -- ─────────────────────────────────────────────────────────
    --  GET_ACTOR_EMAIL
    --  Returns EMAIL for a USER_COMPANY_ID.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_ACTOR_EMAIL (
        p_ucid IN NUMBER
    ) RETURN VARCHAR2 IS
        v_email VARCHAR2(200);
    BEGIN
        SELECT u.EMAIL
          INTO v_email
          FROM EPF_USER_COMPANIES uc
          JOIN EPF_USERS          u ON u.USER_ID = uc.USER_ID
         WHERE uc.USER_COMPANY_ID = p_ucid;
        RETURN v_email;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END GET_ACTOR_EMAIL;

    -- ─────────────────────────────────────────────────────────
    --  GET_ACTOR_ROLE_LABEL
    --  Returns the display role label for narrations
    --  (e.g. 'authorizer').
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_ACTOR_ROLE_LABEL (
        p_ucid IN NUMBER
    ) RETURN VARCHAR2 IS
        v_label VARCHAR2(50) := 'authorizer';
    BEGIN
        SELECT LOWER(r.ROLE_NAME)
          INTO v_label
          FROM EPF_USER_COMP_ROLES ucr
          JOIN EPF_ROLES           r  ON r.ROLE_ID = ucr.ROLE_ID
         WHERE ucr.USER_COMPANY_ID = p_ucid
           AND ucr.IS_ACTIVE = 'Y'
           AND ROWNUM = 1;
        RETURN v_label;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'authorizer';
    END GET_ACTOR_ROLE_LABEL;

    -- ─────────────────────────────────────────────────────────
    --  GET_MAKER_USER_ID
    --  Returns the USER_ID of the maker for a given request.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_MAKER_USER_ID (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER
    ) RETURN NUMBER IS
        v_maker_ucid NUMBER;
        v_user_id    NUMBER;
    BEGIN
        CASE p_request_type
            WHEN 'CONTRIB' THEN
                SELECT MAKER_UCID INTO v_maker_ucid
                  FROM EPF_CONTRIB_BATCHES WHERE BATCH_ID = p_request_id;
            WHEN 'LOAN' THEN
                SELECT MAKER_UCID INTO v_maker_ucid
                  FROM EPF_LOAN_REQUESTS WHERE LOAN_ID = p_request_id;
            WHEN 'WITHDRAWAL' THEN
                SELECT MAKER_UCID INTO v_maker_ucid
                  FROM EPF_WITHDRAWAL_REQUESTS WHERE WD_ID = p_request_id;
            WHEN 'LIEN' THEN
                SELECT MAKER_UCID INTO v_maker_ucid
                  FROM EPF_LIEN_REQUESTS WHERE LIEN_ID = p_request_id;
            WHEN 'NOC' THEN
                SELECT MAKER_UCID INTO v_maker_ucid
                  FROM EPF_NOC_REQUESTS WHERE NOC_ID = p_request_id;
            ELSE
                RETURN NULL;
        END CASE;

        SELECT USER_ID INTO v_user_id
          FROM EPF_USER_COMPANIES
         WHERE USER_COMPANY_ID = v_maker_ucid;
        RETURN v_user_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END GET_MAKER_USER_ID;

    -- ─────────────────────────────────────────────────────────
    --  GET_REQUEST_REF_NO
    --  Returns the reference number string for a request.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_REQUEST_REF_NO (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER
    ) RETURN VARCHAR2 IS
        v_ref VARCHAR2(30);
    BEGIN
        CASE p_request_type
            WHEN 'CONTRIB'    THEN SELECT BATCH_NO INTO v_ref FROM EPF_CONTRIB_BATCHES      WHERE BATCH_ID = p_request_id;
            WHEN 'LOAN'       THEN SELECT LOAN_NO  INTO v_ref FROM EPF_LOAN_REQUESTS        WHERE LOAN_ID  = p_request_id;
            WHEN 'WITHDRAWAL' THEN SELECT WD_NO    INTO v_ref FROM EPF_WITHDRAWAL_REQUESTS  WHERE WD_ID    = p_request_id;
            WHEN 'LIEN'       THEN SELECT LIEN_NO  INTO v_ref FROM EPF_LIEN_REQUESTS        WHERE LIEN_ID  = p_request_id;
            WHEN 'NOC'        THEN SELECT NOC_NO   INTO v_ref FROM EPF_NOC_REQUESTS         WHERE NOC_ID   = p_request_id;
            ELSE v_ref := p_request_type || '-' || p_request_id;
        END CASE;
        RETURN v_ref;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN p_request_type || '-' || p_request_id;
    END GET_REQUEST_REF_NO;

    -- ─────────────────────────────────────────────────────────
    --  GET_COMPANY_ID_FOR_REQUEST
    --  Returns the COMPANY_ID for any request.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_COMPANY_ID_FOR_REQUEST (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER
    ) RETURN NUMBER IS
        v_company_id NUMBER;
    BEGIN
        CASE p_request_type
            WHEN 'CONTRIB'    THEN SELECT COMPANY_ID INTO v_company_id FROM EPF_CONTRIB_BATCHES     WHERE BATCH_ID = p_request_id;
            WHEN 'LOAN'       THEN SELECT COMPANY_ID INTO v_company_id FROM EPF_LOAN_REQUESTS       WHERE LOAN_ID  = p_request_id;
            WHEN 'WITHDRAWAL' THEN SELECT COMPANY_ID INTO v_company_id FROM EPF_WITHDRAWAL_REQUESTS WHERE WD_ID    = p_request_id;
            WHEN 'LIEN'       THEN SELECT COMPANY_ID INTO v_company_id FROM EPF_LIEN_REQUESTS       WHERE LIEN_ID  = p_request_id;
            WHEN 'NOC'        THEN SELECT COMPANY_ID INTO v_company_id FROM EPF_NOC_REQUESTS        WHERE NOC_ID   = p_request_id;
            ELSE v_company_id := NULL;
        END CASE;
        RETURN v_company_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END GET_COMPANY_ID_FOR_REQUEST;

    -- ─────────────────────────────────────────────────────────
    --  NARRATE
    --  Insert FSD-exact narration into EPF_ACTIVITY_LOGS.
    --  Tags '[Ref TYPE-ID]' for GET_REQUEST_HISTORY.
    --  PRAGMA AUTONOMOUS_TRANSACTION.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE NARRATE (
        p_company_id  IN NUMBER,
        p_user_ucid   IN NUMBER,
        p_action_code IN VARCHAR2,
        p_narration   IN VARCHAR2,
        p_ref_type    IN VARCHAR2,
        p_ref_id      IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_user_id NUMBER;
    BEGIN
        SELECT USER_ID INTO v_user_id
          FROM EPF_USER_COMPANIES
         WHERE USER_COMPANY_ID = p_user_ucid;

        INSERT INTO EPF_ACTIVITY_LOG (
            ENTITY_TYPE, ENTITY_ID, ACTION_CODE, REMARKS, PERFORMED_BY, PERFORMED_DATE
        ) VALUES (
            p_ref_type, p_ref_id,
            p_action_code,
            p_narration || ' [Ref ' || p_ref_type || '-' || p_ref_id || ']',
            v_user_id,
            SYSDATE
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END NARRATE;

    -- ─────────────────────────────────────────────────────────
    --  NOTIFY_UCID
    --  Insert a notification for a USER_COMPANY_ID.
    --  PRAGMA AUTONOMOUS_TRANSACTION.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE NOTIFY_UCID (
        p_company_id IN NUMBER,
        p_ucid       IN NUMBER,
        p_title      IN VARCHAR2,
        p_message    IN VARCHAR2,
        p_ref_type   IN VARCHAR2,
        p_ref_id     IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_user_id NUMBER;
    BEGIN
        SELECT USER_ID INTO v_user_id
          FROM EPF_USER_COMPANIES
         WHERE USER_COMPANY_ID = p_ucid;

        INSERT INTO EPF_NOTIFICATIONS (
            COMPANY_ID, USER_ID, TITLE, MESSAGE, REF_TYPE, REF_ID
        ) VALUES (
            p_company_id, v_user_id, p_title, p_message, p_ref_type, p_ref_id
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
    END NOTIFY_UCID;

    -- ─────────────────────────────────────────────────────────
    --  SEND_ACTION_REQUIRED
    --  Write "Action Required" narrations (FSD 2.7a/3.7a etc.)
    --  for all authorizers who have not yet decided.
    --  Called at submission time AND after each partial approval.
    --  Narration format:
    --    [Name and Role]: [request type] pending at [name (email)]
    -- ─────────────────────────────────────────────────────────
    PROCEDURE SEND_ACTION_REQUIRED (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER,
        p_company_id   IN NUMBER,
        p_actor_ucid   IN NUMBER
    ) IS
        v_actor_name   VARCHAR2(200);
        v_actor_role   VARCHAR2(50);
        v_req_label    VARCHAR2(100);
        v_narration    VARCHAR2(4000);
    BEGIN
        v_actor_name := GET_ACTOR_NAME(p_actor_ucid);
        v_actor_role := GET_ACTOR_ROLE_LABEL(p_actor_ucid);

        v_req_label := CASE p_request_type
            WHEN 'CONTRIB'    THEN 'contribution upload'
            WHEN 'LOAN'       THEN 'loan request'
            WHEN 'WITHDRAWAL' THEN 'withdrawal request'
            WHEN 'LIEN'       THEN 'lien marking request'
            WHEN 'NOC'        THEN 'NOC Issuance request'
            ELSE LOWER(p_request_type) || ' request'
        END;

        -- Write one Action Required narration per pending authorizer
        FOR auth_rec IN (
            SELECT uc.USER_COMPANY_ID,
                   u.FULL_NAME,
                   u.EMAIL
              FROM EPF_USER_COMPANIES  uc
              JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
              JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
              JOIN EPF_USERS           u   ON u.USER_ID           = uc.USER_ID
             WHERE uc.COMPANY_ID = p_company_id
               AND ucr.IS_ACTIVE  = 'Y'
               AND r.ROLE_CODE    = 'CORP_AUTHORIZER'
               AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE'
               -- Exclude authorizers who have already decided
               AND NOT EXISTS (
                   SELECT 1 FROM EPF_AUTHORIZER_DECISIONS d
                    WHERE d.REQUEST_TYPE    = p_request_type
                      AND d.REQUEST_ID      = p_request_id
                      AND d.AUTHORIZER_UCID = uc.USER_COMPANY_ID
               )
        ) LOOP
            -- FSD narration format: [Name and Role]: [req type] pending at [name (email)]
            v_narration := v_actor_name || ' (' || v_actor_role || '): '
                        || v_req_label || ' pending at '
                        || auth_rec.FULL_NAME
                        || ' (' || auth_rec.EMAIL || ')';

            NARRATE(
                p_company_id  => p_company_id,
                p_user_ucid   => p_actor_ucid,
                p_action_code => 'ACTION_REQUIRED',
                p_narration   => v_narration,
                p_ref_type    => p_request_type,
                p_ref_id      => p_request_id
            );

            -- Also send email #19 to the pending authorizer
            EPF_EMAIL_PKG.SEND_REQUEST_PENDING_EMAIL(
                p_approver_user_id => auth_rec.USER_COMPANY_ID,   -- will be resolved inside
                p_request_type     => INITCAP(REPLACE(v_req_label,' request','')),
                p_ref_no           => GET_REQUEST_REF_NO(p_request_type, p_request_id),
                p_created_by       => v_actor_name,
                p_created_on       => SYSDATE
            );
        END LOOP;
    END SEND_ACTION_REQUIRED;

    -- ─────────────────────────────────────────────────────────
    --  UPDATE_REQUEST_STATUS
    --  Update STATUS_ID on the target request table.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE UPDATE_REQUEST_STATUS (
        p_request_type  IN VARCHAR2,
        p_request_id    IN NUMBER,
        p_status_code   IN VARCHAR2,
        p_authorizer_ucid IN NUMBER
    ) IS
    BEGIN
        CASE p_request_type
            WHEN 'CONTRIB' THEN
                UPDATE EPF_CONTRIB_BATCHES
                   SET STATUS_ID       = EPF_STATUS_PKG.GET_ID('REQUEST', p_status_code),
                       AUTHORIZER_UCID = p_authorizer_ucid,
                       AUTHORIZED_DATE = CASE WHEN p_status_code IN ('AUTHORIZED','REJECTED') THEN SYSDATE END
                 WHERE BATCH_ID = p_request_id;
            WHEN 'LOAN' THEN
                UPDATE EPF_LOAN_REQUESTS
                   SET STATUS_ID       = EPF_STATUS_PKG.GET_ID('REQUEST', p_status_code),
                       AUTHORIZER_UCID = p_authorizer_ucid,
                       AUTHORIZED_DATE = CASE WHEN p_status_code IN ('AUTHORIZED','REJECTED') THEN SYSDATE END
                 WHERE LOAN_ID = p_request_id;
            WHEN 'WITHDRAWAL' THEN
                UPDATE EPF_WITHDRAWAL_REQUESTS
                   SET STATUS_ID       = EPF_STATUS_PKG.GET_ID('REQUEST', p_status_code),
                       AUTHORIZER_UCID = p_authorizer_ucid,
                       AUTHORIZED_DATE = CASE WHEN p_status_code IN ('AUTHORIZED','REJECTED') THEN SYSDATE END
                 WHERE WD_ID = p_request_id;
            WHEN 'LIEN' THEN
                UPDATE EPF_LIEN_REQUESTS
                   SET STATUS_ID       = EPF_STATUS_PKG.GET_ID('REQUEST', p_status_code),
                       AUTHORIZER_UCID = p_authorizer_ucid,
                       AUTHORIZED_DATE = CASE WHEN p_status_code IN ('AUTHORIZED','REJECTED') THEN SYSDATE END
                 WHERE LIEN_ID = p_request_id;
            WHEN 'NOC' THEN
                UPDATE EPF_NOC_REQUESTS
                   SET STATUS_ID       = EPF_STATUS_PKG.GET_ID('REQUEST', p_status_code),
                       AUTHORIZER_UCID = p_authorizer_ucid,
                       AUTHORIZED_DATE = CASE WHEN p_status_code IN ('AUTHORIZED','REJECTED') THEN SYSDATE END
                 WHERE NOC_ID = p_request_id;
        END CASE;
    END UPDATE_REQUEST_STATUS;

    -- ─────────────────────────────────────────────────────────
    --  APPLY_AUTHORIZATION_SIDE_EFFECTS
    --  When status becomes AUTHORIZED: apply business side effects
    --  and queue to EPF_AAML_QUEUE.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE APPLY_AUTHORIZATION_SIDE_EFFECTS (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER,
        p_company_id   IN NUMBER
    ) IS
    BEGIN
        -- Apply folio-level flags for lien and NOC
        CASE p_request_type
            WHEN 'LIEN' THEN
                DECLARE
                    v_req_type VARCHAR2(10);
                    v_folio_id NUMBER;
                BEGIN
                    SELECT REQUEST_TYPE, FOLIO_ID
                      INTO v_req_type, v_folio_id
                      FROM EPF_LIEN_REQUESTS
                     WHERE LIEN_ID = p_request_id;
                    IF v_req_type = 'MARK' THEN
                        UPDATE EPF_FOLIOS SET LIEN_MARKED = 'Y' WHERE FOLIO_ID = v_folio_id;
                    ELSE
                        UPDATE EPF_FOLIOS SET LIEN_MARKED = 'N' WHERE FOLIO_ID = v_folio_id;
                    END IF;
                END;
            WHEN 'NOC' THEN
                DECLARE
                    v_folio_id NUMBER;
                BEGIN
                    SELECT FOLIO_ID INTO v_folio_id
                      FROM EPF_NOC_REQUESTS WHERE NOC_ID = p_request_id;
                    UPDATE EPF_FOLIOS
                       SET NOC_ISSUED = 'Y', LIEN_MARKED = 'N'
                     WHERE FOLIO_ID = v_folio_id;
                    UPDATE EPF_NOC_REQUESTS
                       SET ISSUED_DATE = SYSDATE
                     WHERE NOC_ID = p_request_id;
                END;
            ELSE
                NULL;  -- CONTRIB/LOAN/WITHDRAWAL side effects handled by AAML posting
        END CASE;

        -- Queue to AAML for transaction posting (FSD #370-371)
        -- LIEN and NOC also need AAML processing
        INSERT INTO EPF_AAML_QUEUE (
            REQUEST_TYPE, REQUEST_ID, COMPANY_ID,
            STATUS, QUEUED_DATE
        ) VALUES (
            p_request_type, p_request_id, p_company_id,
            'PENDING', SYSDATE
        );
    END APPLY_AUTHORIZATION_SIDE_EFFECTS;

    -- ═══════════════════════════════════════════════════════════
    --  PUBLIC PROCEDURES
    -- ═══════════════════════════════════════════════════════════

    -- ─────────────────────────────────────────────────────────
    --  AUTHORIZE_REQUEST
    --  Core multi-authorizer decision handler.
    --  FSD #336-337: ALL active Authorizers must approve.
    --  On APPROVE:
    --    - Record decision in EPF_AUTHORIZER_DECISIONS
    --    - If all required Authorizers have approved:
    --        STATUS → AUTHORIZED
    --        Apply side effects (lien flags, NOC, etc.)
    --        Queue to EPF_AAML_QUEUE
    --        Email #20 (Request Completed) to Maker
    --    - If partial approval:
    --        Write Action Required narrations for remaining Authorizers
    --        Email #19 (Request Pending) to remaining Authorizers
    --  On REJECT:
    --    - STATUS → REJECTED
    --    - Email #16 (Task Rejected) to Maker
    --  Both: FSD-exact narrations written for authorizer AND Maker
    -- ─────────────────────────────────────────────────────────
    PROCEDURE AUTHORIZE_REQUEST (
        p_request_type    IN  VARCHAR2,
        p_request_id      IN  NUMBER,
        p_authorizer_ucid IN  NUMBER,
        p_decision        IN  VARCHAR2,
        p_remarks         IN  VARCHAR2 DEFAULT NULL,
        p_out_success     OUT VARCHAR2,
        p_out_message     OUT VARCHAR2
    ) IS
        v_company_id     NUMBER;
        v_auth_count     NUMBER;
        v_approved_count NUMBER;
        v_actor_name     VARCHAR2(200);
        v_actor_role     VARCHAR2(50);
        v_req_label      VARCHAR2(100);
        v_narration      VARCHAR2(4000);
        v_ref_no         VARCHAR2(30);
        v_maker_user_id  NUMBER;
        v_maker_date     DATE;
        v_req_display    VARCHAR2(100);
        v_existing_cnt   NUMBER := 0;
    BEGIN
        p_out_success := 'N';

        -- Input validation
        IF p_request_type NOT IN ('CONTRIB','LOAN','WITHDRAWAL','LIEN','NOC') THEN
            p_out_message := 'Invalid request type: ' || p_request_type;
            RETURN;
        END IF;
        IF p_decision NOT IN ('APPROVE','REJECT') THEN
            p_out_message := 'Decision must be APPROVE or REJECT.';
            RETURN;
        END IF;
        IF p_decision = 'REJECT' AND TRIM(p_remarks) IS NULL THEN
            p_out_message := 'Remarks are mandatory when rejecting a request.';
            RETURN;
        END IF;

        -- Check request exists and is PENDING_AUTHORIZER
        DECLARE
            v_status_code VARCHAR2(30);
            v_sid         NUMBER;
        BEGIN
            CASE p_request_type
                WHEN 'CONTRIB'    THEN SELECT STATUS_ID INTO v_sid FROM EPF_CONTRIB_BATCHES     WHERE BATCH_ID = p_request_id;
                WHEN 'LOAN'       THEN SELECT STATUS_ID INTO v_sid FROM EPF_LOAN_REQUESTS       WHERE LOAN_ID  = p_request_id;
                WHEN 'WITHDRAWAL' THEN SELECT STATUS_ID INTO v_sid FROM EPF_WITHDRAWAL_REQUESTS WHERE WD_ID    = p_request_id;
                WHEN 'LIEN'       THEN SELECT STATUS_ID INTO v_sid FROM EPF_LIEN_REQUESTS       WHERE LIEN_ID  = p_request_id;
                WHEN 'NOC'        THEN SELECT STATUS_ID INTO v_sid FROM EPF_NOC_REQUESTS        WHERE NOC_ID   = p_request_id;
            END CASE;
            v_status_code := EPF_STATUS_PKG.GET_CODE(v_sid);
            IF v_status_code != 'PENDING_AUTHORIZER' THEN
                p_out_message := 'Request is not pending authorization (current status: ' || v_status_code || ').';
                RETURN;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Request not found: ' || p_request_type || ' ' || p_request_id;
                RETURN;
        END;

        -- Check this authorizer has not already decided
        SELECT COUNT(*) INTO v_existing_cnt
          FROM EPF_AUTHORIZER_DECISIONS
         WHERE REQUEST_TYPE    = p_request_type
           AND REQUEST_ID      = p_request_id
           AND AUTHORIZER_UCID = p_authorizer_ucid;
        IF v_existing_cnt > 0 THEN
            p_out_message := 'You have already submitted a decision for this request.';
            RETURN;
        END IF;

        v_company_id    := GET_COMPANY_ID_FOR_REQUEST(p_request_type, p_request_id);
        v_actor_name    := GET_ACTOR_NAME(p_authorizer_ucid);
        v_actor_role    := GET_ACTOR_ROLE_LABEL(p_authorizer_ucid);
        v_ref_no        := GET_REQUEST_REF_NO(p_request_type, p_request_id);
        v_maker_user_id := GET_MAKER_USER_ID(p_request_type, p_request_id);
        v_auth_count    := GET_AUTHORIZER_COUNT(v_company_id);

        v_req_label := CASE p_request_type
            WHEN 'CONTRIB'    THEN 'contribution upload'
            WHEN 'LOAN'       THEN 'loan request'
            WHEN 'WITHDRAWAL' THEN 'withdrawal request'
            WHEN 'LIEN'       THEN 'lien marking request'
            WHEN 'NOC'        THEN 'NOC issuance request'
            ELSE LOWER(p_request_type) || ' request'
        END;
        v_req_display := CASE p_request_type
            WHEN 'CONTRIB'    THEN 'Contribution Upload'
            WHEN 'LOAN'       THEN 'Loan'
            WHEN 'WITHDRAWAL' THEN 'Withdrawal'
            WHEN 'LIEN'       THEN 'Lien'
            WHEN 'NOC'        THEN 'NOC'
            ELSE p_request_type
        END;

        -- Record the decision
        INSERT INTO EPF_AUTHORIZER_DECISIONS (
            REQUEST_TYPE, REQUEST_ID, AUTHORIZER_UCID,
            DECISION, DECISION_DATE, REMARKS
        ) VALUES (
            p_request_type, p_request_id, p_authorizer_ucid,
            p_decision, SYSDATE, p_remarks
        );

        IF p_decision = 'APPROVE' THEN
            -- FSD narration 2.3/3.3/4.3/5.3/6.3a/7.3:
            -- [Name and Role]: Approved [req type] on [date], at [time]
            v_narration := v_actor_name || ' (' || v_actor_role || '): Approved '
                        || v_req_label || ' on '
                        || TO_CHAR(SYSDATE, 'DD-Mon-YY') || ', at '
                        || TO_CHAR(SYSDATE, 'HH:MI am');

            NARRATE(v_company_id, p_authorizer_ucid,
                    'AUTHORIZER_APPROVED', v_narration, p_request_type, p_request_id);

            v_approved_count := GET_APPROVAL_COUNT(p_request_type, p_request_id);

            -- Update the rolling approved count on the request table
            CASE p_request_type
                WHEN 'CONTRIB'    THEN UPDATE EPF_CONTRIB_BATCHES     SET AUTHORIZER_APPROVED_COUNT = v_approved_count WHERE BATCH_ID = p_request_id;
                WHEN 'LOAN'       THEN UPDATE EPF_LOAN_REQUESTS       SET AUTHORIZER_APPROVED_COUNT = v_approved_count WHERE LOAN_ID  = p_request_id;
                WHEN 'WITHDRAWAL' THEN UPDATE EPF_WITHDRAWAL_REQUESTS SET AUTHORIZER_APPROVED_COUNT = v_approved_count WHERE WD_ID    = p_request_id;
                WHEN 'LIEN'       THEN UPDATE EPF_LIEN_REQUESTS       SET AUTHORIZER_APPROVED_COUNT = v_approved_count WHERE LIEN_ID  = p_request_id;
                WHEN 'NOC'        THEN UPDATE EPF_NOC_REQUESTS        SET AUTHORIZER_APPROVED_COUNT = v_approved_count WHERE NOC_ID   = p_request_id;
            END CASE;

            IF v_approved_count >= v_auth_count THEN
                -- ALL authorizers approved → AUTHORIZED
                UPDATE_REQUEST_STATUS(p_request_type, p_request_id,
                                      'AUTHORIZED', p_authorizer_ucid);

                APPLY_AUTHORIZATION_SIDE_EFFECTS(p_request_type, p_request_id, v_company_id);

                -- Email #20: Request Completed to Maker
                IF v_maker_user_id IS NOT NULL THEN
                    -- Fetch maker date
                    CASE p_request_type
                        WHEN 'LOAN' THEN SELECT MAKER_DATE INTO v_maker_date FROM EPF_LOAN_REQUESTS WHERE LOAN_ID = p_request_id;
                        ELSE v_maker_date := SYSDATE;
                    END CASE;
                    EPF_EMAIL_PKG.SEND_REQUEST_COMPLETED_EMAIL(
                        p_maker_user_id => v_maker_user_id,
                        p_request_type  => v_req_display,
                        p_ref_no        => v_ref_no,
                        p_created_on    => NVL(v_maker_date, SYSDATE)
                    );
                END IF;

                NOTIFY_UCID(
                    p_company_id => v_company_id,
                    p_ucid       => p_authorizer_ucid,
                    p_title      => v_req_display || ' Authorized',
                    p_message    => 'All authorizers have approved ' || v_req_label
                                 || ' (Ref: ' || v_ref_no || '). Submitted to AAML for processing.',
                    p_ref_type   => p_request_type,
                    p_ref_id     => p_request_id
                );

                p_out_message := v_req_display || ' request authorized and queued for AAML processing.';
            ELSE
                -- Partial approval: notify remaining authorizers
                SEND_ACTION_REQUIRED(p_request_type, p_request_id,
                                     v_company_id, p_authorizer_ucid);
                p_out_message := 'Approval recorded (' || v_approved_count
                              || ' of ' || v_auth_count || ' authorizers). '
                              || 'Remaining authorizers notified.';
            END IF;

        ELSE
            -- REJECT
            -- FSD narration 2.6a/3.6a/4.6a/5.4/6.4a/7.4:
            -- [Name and Role]: Rejected [req type] on [date], at [time]
            v_narration := v_actor_name || ' (' || v_actor_role || '): Rejected '
                        || v_req_label || ' on '
                        || TO_CHAR(SYSDATE, 'DD-Mon-YY') || ', at '
                        || TO_CHAR(SYSDATE, 'HH:MI am');

            NARRATE(v_company_id, p_authorizer_ucid,
                    'AUTHORIZER_REJECTED', v_narration, p_request_type, p_request_id);

            UPDATE_REQUEST_STATUS(p_request_type, p_request_id,
                                  'REJECTED', p_authorizer_ucid);

            -- Email #16: Task Rejected to Maker
            IF v_maker_user_id IS NOT NULL THEN
                EPF_EMAIL_PKG.SEND_TASK_REJECTED_EMAIL(
                    p_maker_user_id    => v_maker_user_id,
                    p_request_type     => v_req_display,
                    p_ref_no           => v_ref_no,
                    p_remarks          => p_remarks,
                    p_rejected_by_name => v_actor_name || ' (authorizer)'
                );
            END IF;

            p_out_message := v_req_display || ' request rejected.';
        END IF;

        p_out_success := 'Y';
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Unexpected error in AUTHORIZE_REQUEST: ' || SQLERRM;
    END AUTHORIZE_REQUEST;

    -- ─────────────────────────────────────────────────────────
    --  AUTHORIZE_LOAN_SETTINGS
    --  FSD #339-340.  Approves or rejects pending loan settings
    --  changes for a company.  Narration: 9.6.
    --  On APPROVE: new settings copied to live columns; pending
    --              columns cleared.
    --  On REJECT: pending columns cleared; old settings intact.
    -- ─────────────────────────────────────────────────────────
    PROCEDURE AUTHORIZE_LOAN_SETTINGS (
        p_company_id      IN  NUMBER,
        p_authorizer_ucid IN  NUMBER,
        p_decision        IN  VARCHAR2,
        p_remarks         IN  VARCHAR2 DEFAULT NULL,
        p_out_success     OUT VARCHAR2,
        p_out_message     OUT VARCHAR2
    ) IS
        v_actor_name    VARCHAR2(200);
        v_actor_role    VARCHAR2(50);
        v_narration     VARCHAR2(4000);
        v_status        VARCHAR2(30);
        v_pend_itype    EPF_COMPANY_SETTINGS.PENDING_INTEREST_TYPE%TYPE;
        v_pend_irate    EPF_COMPANY_SETTINGS.PENDING_INTEREST_RATE%TYPE;
        v_pend_limit    EPF_COMPANY_SETTINGS.PENDING_LOAN_LIMIT_PCT%TYPE;
        v_pend_months   EPF_COMPANY_SETTINGS.PENDING_MAX_INSTALMENT_MONTHS%TYPE;
        v_pend_frt      EPF_COMPANY_SETTINGS.PENDING_FLOATING_RATE_TENURE%TYPE;
        v_decision_text VARCHAR2(10);
    BEGIN
        p_out_success := 'N';

        IF p_decision NOT IN ('APPROVE','REJECT') THEN
            p_out_message := 'Decision must be APPROVE or REJECT.';
            RETURN;
        END IF;
        IF p_decision = 'REJECT' AND TRIM(p_remarks) IS NULL THEN
            p_out_message := 'Remarks are mandatory when rejecting loan settings.';
            RETURN;
        END IF;

        -- Fetch current pending settings
        BEGIN
            SELECT LOAN_SETTINGS_STATUS,
                   PENDING_INTEREST_TYPE, PENDING_INTEREST_RATE,
                   PENDING_LOAN_LIMIT_PCT, PENDING_MAX_INSTALMENT_MONTHS,
                   PENDING_FLOATING_RATE_TENURE
              INTO v_status, v_pend_itype, v_pend_irate,
                   v_pend_limit, v_pend_months, v_pend_frt
              FROM EPF_COMPANY_SETTINGS
             WHERE COMPANY_ID = p_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_out_message := 'Company settings not found for company_id: ' || p_company_id;
                RETURN;
        END;

        IF v_status NOT IN ('PENDING_AUTHORIZER','PENDING_CHECKER') THEN
            p_out_message := 'No pending loan settings changes to authorize.';
            RETURN;
        END IF;

        v_actor_name  := GET_ACTOR_NAME(p_authorizer_ucid);
        v_actor_role  := 'Authorizer';
        v_decision_text := CASE WHEN p_decision = 'APPROVE' THEN 'approved' ELSE 'rejected' END;

        -- FSD narration 9.6: Loan Settings were [approved/rejected] by Authorizer [Name] (...)
        v_narration :=
            'Loan Settings were ' || v_decision_text || ' by ' || v_actor_role
         || ' ' || v_actor_name
         || ' (Interest Type: ' || NVL(v_pend_itype, '—')
         || ', Floating Rate Tenure: ' || NVL(TO_CHAR(v_pend_frt),'N/A') || ' months'
         || ', Interest Rate: ' || NVL(TO_CHAR(v_pend_irate),'—') || '%'
         || ', Loan Limit: ' || NVL(TO_CHAR(v_pend_limit),'—') || '%'
         || ', Max Instalment Period: ' || NVL(TO_CHAR(v_pend_months),'—') || ' months)';

        IF p_decision = 'APPROVE' THEN
            -- Apply pending settings to live columns; clear pending columns
            UPDATE EPF_COMPANY_SETTINGS
               SET LOAN_INTEREST_TYPE         = v_pend_itype,
                   LOAN_INTEREST_RATE         = v_pend_irate,
                   LOAN_LIMIT_PCT             = v_pend_limit,
                   LOAN_MAX_INSTALMENT_MONTHS = v_pend_months,
                   FLOATING_RATE_TENURE       = v_pend_frt,
                   PENDING_INTEREST_TYPE         = NULL,
                   PENDING_INTEREST_RATE         = NULL,
                   PENDING_LOAN_LIMIT_PCT        = NULL,
                   PENDING_MAX_INSTALMENT_MONTHS = NULL,
                   PENDING_FLOATING_RATE_TENURE  = NULL,
                   LOAN_SETTINGS_STATUS          = 'APPROVED',
                   LOAN_SETTINGS_CHECKER_UCID    = p_authorizer_ucid,
                   LOAN_SETTINGS_CHECKER_DATE    = SYSDATE
             WHERE COMPANY_ID = p_company_id;
        ELSE
            -- Reject: discard pending columns; old settings intact
            UPDATE EPF_COMPANY_SETTINGS
               SET PENDING_INTEREST_TYPE         = NULL,
                   PENDING_INTEREST_RATE         = NULL,
                   PENDING_LOAN_LIMIT_PCT        = NULL,
                   PENDING_MAX_INSTALMENT_MONTHS = NULL,
                   PENDING_FLOATING_RATE_TENURE  = NULL,
                   LOAN_SETTINGS_STATUS          = 'APPROVED',
                   LOAN_SETTINGS_CHECKER_UCID    = p_authorizer_ucid,
                   LOAN_SETTINGS_CHECKER_DATE    = SYSDATE
             WHERE COMPANY_ID = p_company_id;
        END IF;

        -- Log narration to activity log
        NARRATE(
            p_company_id  => p_company_id,
            p_user_ucid   => p_authorizer_ucid,
            p_action_code => 'LOAN_SETTINGS_' || p_decision,
            p_narration   => v_narration,
            p_ref_type    => 'LOAN_SETTINGS',
            p_ref_id      => p_company_id
        );

        p_out_success := 'Y';
        p_out_message := 'Loan settings ' || v_decision_text || ' successfully.';
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_out_success := 'N';
            p_out_message := 'Unexpected error in AUTHORIZE_LOAN_SETTINGS: ' || SQLERRM;
    END AUTHORIZE_LOAN_SETTINGS;

    -- ─────────────────────────────────────────────────────────
    --  GET_REQUEST_HISTORY
    --  Returns narrations for a request from EPF_ACTIVITY_LOGS.
    --  Same pattern as EPF_CORP_TXN_PKG.GET_REQUEST_HISTORY.
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_REQUEST_HISTORY (
        p_ref_type IN VARCHAR2,
        p_ref_id   IN NUMBER
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
        v_tag VARCHAR2(50);
    BEGIN
        v_tag := '[Ref ' || p_ref_type || '-' || p_ref_id || ']';
        OPEN v_cur FOR
            SELECT al.LOG_ID,
                   al.PERFORMED_DATE AS ACTION_DATE,
                   al.ACTION_CODE,
                   -- Strip the [Ref TYPE-ID] tag from the display narration
                   TRIM(REPLACE(al.REMARKS, v_tag, '')) AS NARRATION,
                   u.FULL_NAME,
                   NULL AS USER_COMPANY_ID
              FROM EPF_ACTIVITY_LOG al
              LEFT JOIN EPF_USERS   u  ON u.USER_ID = al.PERFORMED_BY
             WHERE al.REMARKS LIKE '%' || v_tag || '%'
             ORDER BY al.PERFORMED_DATE ASC, al.LOG_ID ASC;
        RETURN v_cur;
    END GET_REQUEST_HISTORY;

    -- ─────────────────────────────────────────────────────────
    --  GET_AUTHORIZER_DECISIONS
    --  Returns who has decided and who is still pending for
    --  a given request.  Used by the status popup "Action Required"
    --  and the progress indicator (e.g. "2 of 3 Authorizers").
    -- ─────────────────────────────────────────────────────────
    FUNCTION GET_AUTHORIZER_DECISIONS (
        p_request_type IN VARCHAR2,
        p_request_id   IN NUMBER
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT uc.USER_COMPANY_ID,
                   u.FULL_NAME,
                   u.EMAIL,
                   d.DECISION,
                   d.DECISION_DATE,
                   d.REMARKS,
                   CASE WHEN d.DECISION IS NULL THEN 'PENDING'
                        ELSE d.DECISION
                   END AS DECISION_STATUS
              FROM EPF_USER_COMPANIES  uc
              JOIN EPF_USER_COMP_ROLES ucr ON ucr.USER_COMPANY_ID = uc.USER_COMPANY_ID
              JOIN EPF_ROLES           r   ON r.ROLE_ID           = ucr.ROLE_ID
              JOIN EPF_USERS           u   ON u.USER_ID           = uc.USER_ID
              LEFT JOIN EPF_AUTHORIZER_DECISIONS d
                    ON d.AUTHORIZER_UCID = uc.USER_COMPANY_ID
                   AND d.REQUEST_TYPE    = p_request_type
                   AND d.REQUEST_ID      = p_request_id
             WHERE ucr.IS_ACTIVE = 'Y'
               AND r.ROLE_CODE   = 'CORP_AUTHORIZER'
               AND EPF_STATUS_PKG.GET_CODE(uc.STATUS_ID) = 'ACTIVE'
             ORDER BY uc.USER_COMPANY_ID;
        RETURN v_cur;
    END GET_AUTHORIZER_DECISIONS;

END EPF_AUTHORIZER_PKG;
/

-- ============================================================
-- End of 15_epf_authorizer_pkg.sql
-- ============================================================
