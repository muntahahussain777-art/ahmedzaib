-- Part 6 isolated protocol probes (run against a throwaway schema or accept soft-deleted probe rows).
-- Already exercised via MCP on production project with soft-deleted probe customer aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee2.
--
-- 1) Rollback must not advance next_rev or leave a feed row (subtransaction abort).
-- 2) Successful insert allocates exactly one rev; soft-delete allocates the next.
-- 3) Concurrent writers: omitted here (requires parallel sessions); protocol relies on
--    FOR UPDATE lock on zaib_sync_pub held until commit.

SELECT next_rev FROM zaib_sync_pub WHERE id = 1;
SELECT COUNT(*) AS feed_count, MIN(rev), MAX(rev) FROM zaib_sync_feed;
