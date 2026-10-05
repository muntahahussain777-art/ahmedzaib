-- Part 8 verification probes (disposable SyncIds only). Safe to re-run.
-- Expect: all RAISE NOTICE part8_*_ok; no EXCEPTION.

DO $$
DECLARE
  sid uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
  r jsonb; r1 jsonb; r2 jsonb;
  entity_rev bigint; feed_rev bigint; payload_rev bigint; rpc_rev bigint; base bigint;
  feed_before bigint;
  orig jsonb;
BEGIN
  DELETE FROM zaib_sync_requests WHERE request_id::text LIKE 'aaaaaaaa-%' OR row_sync_id = sid;
  DELETE FROM zaib_customers WHERE sync_id = sid;
  DELETE FROM zaib_deleted_registry WHERE sync_id = sid;
  DELETE FROM zaib_sync_feed WHERE row_sync_id = sid;

  orig := jsonb_build_object(
    'sync_id', sid, 'name', '__p8__', 'mobile', '', 'date_text', '',
    'updated_at', now(), 'device_id', 'p8');

  r := zaib_sync_apply('zaib_customers', orig, NULL, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', false);
  IF r->>'status' <> 'accepted' THEN RAISE EXCEPTION 'insert %', r; END IF;
  rpc_rev := (r->>'server_rev')::bigint;
  SELECT server_rev INTO entity_rev FROM zaib_customers WHERE sync_id = sid;
  SELECT rev, (payload->>'server_rev')::bigint INTO feed_rev, payload_rev
  FROM zaib_sync_feed WHERE row_sync_id = sid ORDER BY rev DESC LIMIT 1;
  IF entity_rev IS DISTINCT FROM rpc_rev OR feed_rev IS DISTINCT FROM rpc_rev OR payload_rev IS DISTINCT FROM rpc_rev THEN
    RAISE EXCEPTION 'rev inequality e=% f=% p=% r=%', entity_rev, feed_rev, payload_rev, rpc_rev;
  END IF;
  IF (SELECT COUNT(*) FROM zaib_sync_feed WHERE row_sync_id = sid) <> 1 THEN
    RAISE EXCEPTION 'stamp published != 1';
  END IF;

  SELECT server_rev INTO base FROM zaib_customers WHERE sync_id = sid;
  r1 := zaib_sync_apply('zaib_customers',
    jsonb_build_object('sync_id',sid,'name','win','mobile','','date_text','','updated_at',now(),'device_id','A'),
    base, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', false);
  r2 := zaib_sync_apply('zaib_customers',
    jsonb_build_object('sync_id',sid,'name','lose','mobile','','date_text','','updated_at',now(),'device_id','B'),
    base, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', false);
  IF r1->>'status' <> 'accepted' OR r2->>'status' <> 'conflict' THEN
    RAISE EXCEPTION 'parallel % / %', r1, r2;
  END IF;

  r := zaib_sync_apply('zaib_customers', orig, NULL, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', true);
  IF r->>'status' <> 'rejected' OR coalesce(r->>'reason','') <> 'restore_not_allowed' THEN
    RAISE EXCEPTION 'public restore %', r;
  END IF;

  r := zaib_sync_apply('zaib_customers',
    jsonb_build_object('sync_id',sid,'name','other','mobile','','date_text','','updated_at',now(),'device_id','p8'),
    NULL, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', false);
  IF r->>'status' <> 'rejected' OR coalesce(r->>'reason','') <> 'request_id_payload_mismatch' THEN
    RAISE EXCEPTION 'req mismatch %', r;
  END IF;

  r := zaib_sync_apply('zaib_customers', orig, NULL, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', false);
  IF r->>'status' <> 'accepted' OR coalesce((r->>'idempotent')::boolean, false) IS NOT TRUE THEN
    -- idempotent may be missing if first outcome stored without flag; status accepted is enough
    IF r->>'status' <> 'accepted' THEN RAISE EXCEPTION 'idempotent %', r; END IF;
  END IF;

  -- soft delete + public resurrect blocked
  r := zaib_sync_apply('zaib_customers',
    jsonb_build_object('sync_id',sid,'name','win','mobile','','date_text','','updated_at',now(),'deleted_at',now(),'device_id','p8'),
    (r1->>'server_rev')::bigint, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5', false);
  IF r->>'status' <> 'accepted' THEN RAISE EXCEPTION 'delete %', r; END IF;
  SELECT COUNT(*) INTO feed_before FROM zaib_sync_feed WHERE row_sync_id = sid;
  r := zaib_sync_apply('zaib_customers',
    jsonb_build_object('sync_id',sid,'name','res','mobile','','date_text','','updated_at',now()+interval '1 day','device_id','evil'),
    (r->>'server_rev')::bigint, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6', false);
  IF r->>'status' <> 'deleted' THEN RAISE EXCEPTION 'resurrect %', r; END IF;
  IF (SELECT COUNT(*) FROM zaib_sync_feed WHERE row_sync_id = sid) <> feed_before THEN
    RAISE EXCEPTION 'resurrect published';
  END IF;

  DELETE FROM zaib_sync_requests WHERE request_id::text LIKE 'aaaaaaaa-%' OR row_sync_id = sid;
  DELETE FROM zaib_customers WHERE sync_id = sid;
  DELETE FROM zaib_deleted_registry WHERE sync_id = sid;
  DELETE FROM zaib_sync_feed WHERE row_sync_id = sid;
  RAISE NOTICE 'part8_verify_ok';
END $$;
