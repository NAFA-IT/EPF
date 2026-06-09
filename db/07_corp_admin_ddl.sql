-- ============================================================
-- FILE: /home/user/EPF/db/07_corp_admin_ddl.sql
-- EPF PORTAL  –  Corporate Admin Module – New DB Objects
-- Run once, in order.  Requires: 01_ddl_new_objects.sql applied.
-- ============================================================

-- ── Password / Set-Password Token Store ──────────────────────
CREATE TABLE EPF_PASSWORD_TOKENS (
    TOKEN_ID       NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    USER_ID        NUMBER          NOT NULL,
    TOKEN          VARCHAR2(200)   NOT NULL,
    PURPOSE        VARCHAR2(30)    NOT NULL,
    EXPIRES_AT     DATE,                          -- NULL = single-use (no time limit)
    USED_YN        VARCHAR2(1)     DEFAULT 'N'    NOT NULL,
    CREATED_DATE   DATE            DEFAULT SYSDATE NOT NULL,
    IP_ADDRESS     VARCHAR2(50),
    CONSTRAINT EPF_PWD_TOKENS_USER_FK  FOREIGN KEY (USER_ID)
        REFERENCES EPF_USERS (USER_ID),
    CONSTRAINT EPF_PWD_TOKENS_TOKEN_UK UNIQUE (TOKEN),
    CONSTRAINT EPF_PWD_TOKENS_PURPOSE_CK CHECK (PURPOSE IN ('SET_PASSWORD','RESET_PASSWORD')),
    CONSTRAINT EPF_PWD_TOKENS_USED_CK   CHECK (USED_YN IN ('Y','N'))
);

-- ── OTP Request Store ─────────────────────────────────────────
CREATE TABLE EPF_OTP_REQUESTS (
    OTP_ID         NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    USER_ID        NUMBER          NOT NULL,
    OTP_CODE       VARCHAR2(10)    NOT NULL,
    PURPOSE        VARCHAR2(30)    NOT NULL,
    EXPIRES_AT     DATE            NOT NULL,
    USED_YN        VARCHAR2(1)     DEFAULT 'N'  NOT NULL,
    ATTEMPT_COUNT  NUMBER          DEFAULT 0    NOT NULL,
    RESEND_COUNT   NUMBER          DEFAULT 0    NOT NULL,
    SESSION_ID     VARCHAR2(200),
    CREATED_DATE   DATE            DEFAULT SYSDATE NOT NULL,
    CONSTRAINT EPF_OTP_REQ_USER_FK    FOREIGN KEY (USER_ID)
        REFERENCES EPF_USERS (USER_ID),
    CONSTRAINT EPF_OTP_REQ_PURPOSE_CK CHECK (PURPOSE IN ('PWD_CHANGE','FORGOT_PWD','LOGIN_MFA')),
    CONSTRAINT EPF_OTP_REQ_USED_CK    CHECK (USED_YN IN ('Y','N'))
);

-- ── Sequence for Activity Log Reference Numbers ───────────────
CREATE SEQUENCE ACT_LOG_REF_SEQ
    START WITH 1
    INCREMENT BY 1
    CACHE 20
    NOCYCLE;

-- ── Activity / Audit Log ──────────────────────────────────────
CREATE TABLE EPF_ACTIVITY_LOGS (
    LOG_ID           NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    COMPANY_ID       NUMBER,
    USER_ID          NUMBER,
    USER_COMPANY_ID  NUMBER,
    ACTION_CODE      VARCHAR2(100),
    ACTION_DETAIL    VARCHAR2(4000),
    ACTION_DATE      DATE            DEFAULT SYSDATE NOT NULL,
    IP_ADDRESS       VARCHAR2(50),
    PAGE_NAME        VARCHAR2(200),
    REF_NO           VARCHAR2(30)    -- ACT-YYYYMM-000001 format, populated on insert
);

-- ── Email Log ─────────────────────────────────────────────────
CREATE TABLE EPF_EMAIL_LOGS (
    EMAIL_LOG_ID      NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    USER_ID           NUMBER,
    RECIPIENT_EMAIL   VARCHAR2(200),
    SUBJECT           VARCHAR2(500),
    BODY_SUMMARY      VARCHAR2(4000),
    SENT_DATE         DATE            DEFAULT SYSDATE NOT NULL,
    STATUS            VARCHAR2(20)    DEFAULT 'SENT'  NOT NULL,
    ERROR_MSG         VARCHAR2(4000),
    EMAIL_TYPE        VARCHAR2(50),
    CONSTRAINT EPF_EMAIL_LOG_STATUS_CK CHECK (STATUS IN ('SENT','FAILED'))
);

-- ── Indexes ───────────────────────────────────────────────────
CREATE INDEX EPF_ACT_LOGS_USER_IX
    ON EPF_ACTIVITY_LOGS (USER_ID);

CREATE INDEX EPF_ACT_LOGS_COMPANY_IX
    ON EPF_ACTIVITY_LOGS (COMPANY_ID);

CREATE INDEX EPF_OTP_USER_IX
    ON EPF_OTP_REQUESTS (USER_ID);

CREATE INDEX EPF_TOKENS_USER_IX
    ON EPF_PASSWORD_TOKENS (USER_ID);

-- ============================================================
-- End of 07_corp_admin_ddl.sql
-- ============================================================
