-- Step 15.1: Add personalization_note column to recommendations table
-- Stores Claude's explanation of why each recommendation fits the partner.

ALTER TABLE recommendations ADD COLUMN personalization_note TEXT;

COMMENT ON COLUMN recommendations.personalization_note IS
    'Claude AI explanation of why this recommendation fits the specific partner (Step 15.1)';
