-- Step 19.60: Add headline column to recommendations table
-- Stores the editorial 2–4 word heading Claude emits per pick ("Weekend
-- Curations"), shown above the card in the recommendation feed.
--
-- Nullable with no default on purpose: build_recommendation_row must send the
-- same keys for every row of a PostgREST bulk insert (Step 19.27), and a
-- NOT NULL DEFAULT column fails the whole batch the moment one candidate has
-- no headline. Rows generated before this migration simply stay NULL and the
-- iOS feed falls back to a type-derived heading.

ALTER TABLE recommendations ADD COLUMN IF NOT EXISTS headline TEXT;

COMMENT ON COLUMN recommendations.headline IS
    '2-4 word editorial heading shown above the pick in the feed; NULL for rows generated before Step 19.60';
