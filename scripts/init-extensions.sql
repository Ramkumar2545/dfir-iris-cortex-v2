-- ============================================================
-- PostgreSQL extensions required by DFIR-IRIS
-- Auto-executed by postgres image BEFORE IRIS init scripts
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- uuid_generate_v4()
