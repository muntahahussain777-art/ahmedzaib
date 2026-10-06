-- Part 7: durable deletion protection, conditional OCC writes, feed/counter lockdown.
--
-- PROTOCOL
--   Clients MUST write via RPC public.zaib_sync_apply(table, payload, expected_rev, request_id).
--   Server owns server_rev. Client-supplied server_rev is ignored/stripped.
--   expected_rev: NULL = insert-only (row must not exist); bigint = must match current server_rev.
--   Outcomes: accepted | duplicate | conflict | deleted | rejected
--   Idempotent retries: same request_id returns the stored outcome.
--   Ordinary writes NEVER resurrect deleted SyncIds (allow_restore only via explicit flag on RPC).
--   Rejected/no-op writes do NOT publish feed events (BEFORE trigger RETURN NULL / no mutation).
--
-- SECURITY
--   anon/authenticated: SELECT on entity tables + zaib_sync_feed (+ legacy changes SELECT).
--   No INSERT/UPDATE/DELETE on entities, feed, pub, or changes for clients.
--   No EXECUTE on trigger function zaib_record_sync_change for clients.
--   EXECUTE on zaib_sync_apply for anon/authenticated (SECURITY DEFINER, fixed search_path).
--
-- ROLLOUT
--   1) Apply this migration.
--   2) Deploy WinForms + Flutter that call zaib_sync_apply (this commit).
--   3) Older direct-upsert clients receive permission errors until upgraded (intentional).

-- ---------------------------------------------------------------------------
-- Durable deletion registry (survives physical DELETE + soft-delete)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.zaib_deleted_registry (
  cloud_table text NOT NULL,
  sync_id uuid NOT NULL,
  deleted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  server_rev bigint,
  PRIMARY KEY (cloud_table, sync_id)
);
ALTER TABLE public.zaib_deleted_registry ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS zaib_deleted_registry_select ON public.zaib_deleted_registry;
CREATE POLICY zaib_deleted_registry_select ON public.zaib_deleted_registry
  FOR SELECT TO anon, authenticated USING (true);
REVOKE ALL ON public.zaib_deleted_registry FROM anon, authenticated;
GRANT SELECT ON public.zaib_deleted_registry TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.zaib_sync_requests (
  request_id uuid PRIMARY KEY,
  cloud_table text NOT NULL,
  row_sync_id uuid NOT NULL,
  outcome jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.zaib_sync_requests ENABLE ROW LEVEL SECURITY;
-- No client policies: only SECURITY DEFINER RPC reads/writes this table.
REVOKE ALL ON public.zaib_sync_requests FROM anon, authenticated;

-- Backfill registry from currently soft-deleted rows.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'zaib_customers','zaib_dealers','zaib_petrol_entries','zaib_dealer_payouts',
    'zaib_dealer_purchases','zaib_dealer_direct','zaib_stock_diesel',
    'zaib_bank_transactions','zaib_expenses','zaib_dealer_balance_ops',
    'zaib_dealer_transfers'
  ]
  LOOP
    EXECUTE format(
      'INSERT INTO public.zaib_deleted_registry (cloud_table, sync_id, deleted_at, server_rev)
       SELECT %L, sync_id, deleted_at, server_rev FROM public.%I
       WHERE deleted_at IS NOT NULL AND sync_id IS NOT NULL
       ON CONFLICT DO NOTHING',
      t, t
    );
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Hardened LWW / no-resurrect (defense in depth; RETURN NULL cancels + skips AFTER)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.zaib_reject_stale_or_resurrect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Never trust client-supplied server_rev as overwrite permission.
  IF TG_OP = 'UPDATE' THEN
    NEW.server_rev := OLD.server_rev;
  ELSIF TG_OP = 'INSERT' THEN
    NEW.server_rev := NULL;
  END IF;

  -- Durable deletion: ordinary upsert/update cannot clear deleted_at.
  IF TG_OP = 'UPDATE'
     AND OLD.deleted_at IS NOT NULL
     AND NEW.deleted_at IS NULL THEN
    IF current_setting('zaib.allow_restore', true) IS DISTINCT FROM '1' THEN
      RETURN NULL; -- cancel write; no AFTER / no feed event
    END IF;
  END IF;

  -- INSERT of a SyncId that is registered deleted (after physical delete or soft).
  IF TG_OP = 'INSERT' AND NEW.sync_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.zaib_deleted_registry r
      WHERE r.cloud_table = TG_TABLE_NAME AND r.sync_id = NEW.sync_id
    ) AND current_setting('zaib.allow_restore', true) IS DISTINCT FROM '1' THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Stale timestamp (only for non-delete→delete and non-restore paths).
  IF TG_OP = 'UPDATE'
     AND OLD.updated_at IS NOT NULL AND NEW.updated_at IS NOT NULL
     AND NEW.updated_at < OLD.updated_at
     AND NOT (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL) THEN
    -- Allow delete even if client clock is skewed slightly? Prefer OCC via RPC.
    -- Still reject clearly older live updates.
    IF NEW.deleted_at IS NULL THEN
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Publication trigger: register deletes; do not swallow stamp errors silently in a way
-- that desyncs server_rev from feed (still best-effort stamp).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.zaib_record_sync_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_op text;
  v_sync uuid;
  v_updated timestamptz;
  v_device text;
  v_payload jsonb;
  v_deleted boolean;
  v_rev bigint;
BEGIN
  IF current_setting('zaib.recording_feed', true) = '1' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  UPDATE public.zaib_sync_pub
  SET next_rev = next_rev + 1
  WHERE id = 1
  RETURNING next_rev - 1 INTO v_rev;

  IF v_rev IS NULL THEN
    INSERT INTO public.zaib_sync_pub (id, next_rev) VALUES (1, 2)
    ON CONFLICT (id) DO UPDATE SET next_rev = public.zaib_sync_pub.next_rev + 1
    RETURNING next_rev - 1 INTO v_rev;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_sync := OLD.sync_id;
    v_updated := OLD.updated_at;
    v_device := OLD.device_id;
    v_payload := to_jsonb(OLD) || jsonb_build_object('server_rev', v_rev);
    v_op := 'delete';
    IF v_sync IS NOT NULL THEN
      INSERT INTO public.zaib_deleted_registry (cloud_table, sync_id, deleted_at, server_rev)
      VALUES (TG_TABLE_NAME, v_sync, COALESCE(OLD.deleted_at, clock_timestamp()), v_rev)
      ON CONFLICT (cloud_table, sync_id) DO UPDATE
        SET deleted_at = EXCLUDED.deleted_at, server_rev = EXCLUDED.server_rev;
    END IF;
  ELSE
    v_sync := NEW.sync_id;
    v_updated := NEW.updated_at;
    v_device := NEW.device_id;
    v_payload := to_jsonb(NEW) || jsonb_build_object('server_rev', v_rev);
    v_deleted := (NEW.deleted_at IS NOT NULL);
    v_op := CASE WHEN v_deleted THEN 'delete' ELSE 'upsert' END;
    IF v_deleted AND v_sync IS NOT NULL THEN
      INSERT INTO public.zaib_deleted_registry (cloud_table, sync_id, deleted_at, server_rev)
      VALUES (TG_TABLE_NAME, v_sync, NEW.deleted_at, v_rev)
      ON CONFLICT (cloud_table, sync_id) DO UPDATE
        SET deleted_at = EXCLUDED.deleted_at, server_rev = EXCLUDED.server_rev;
    ELSIF NOT v_deleted AND v_sync IS NOT NULL
          AND current_setting('zaib.allow_restore', true) = '1' THEN
      DELETE FROM public.zaib_deleted_registry
      WHERE cloud_table = TG_TABLE_NAME AND sync_id = v_sync;
    END IF;
  END IF;

  IF v_sync IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  INSERT INTO public.zaib_sync_feed (rev, cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  VALUES (v_rev, TG_TABLE_NAME, v_sync, v_op, v_updated, v_device, v_payload);

  BEGIN
    INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
    VALUES (TG_TABLE_NAME, v_sync, v_op, v_updated, v_device, v_payload);
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  IF TG_OP <> 'DELETE' THEN
    PERFORM set_config('zaib.recording_feed', '1', true);
    BEGIN
      EXECUTE format(
        'UPDATE public.%I SET server_rev = $1 WHERE sync_id = $2 AND (server_rev IS DISTINCT FROM $1)',
        TG_TABLE_NAME
      ) USING v_rev, v_sync;
    EXCEPTION WHEN OTHERS THEN
      RAISE; -- do not swallow: keep feed rev and row stamp consistent
    END;
    PERFORM set_config('zaib.recording_feed', '0', true);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ---------------------------------------------------------------------------
-- Conditional apply RPC (atomic OCC)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.zaib_sync_apply(
  p_table text,
  p_payload jsonb,
  p_expected_rev bigint DEFAULT NULL,
  p_request_id uuid DEFAULT NULL,
  p_allow_restore boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed text[] := ARRAY[
    'zaib_customers','zaib_dealers','zaib_petrol_entries','zaib_dealer_payouts',
    'zaib_dealer_purchases','zaib_dealer_direct','zaib_stock_diesel',
    'zaib_bank_transactions','zaib_expenses','zaib_dealer_balance_ops',
    'zaib_dealer_transfers'
  ];
  v_sync uuid;
  v_row jsonb;
  v_existing jsonb;
  v_cur_rev bigint;
  v_deleted_at timestamptz;
  v_want_delete boolean;
  v_outcome jsonb;
  v_cols text;
  v_vals text;
  v_sets text;
  k text;
  v_payload jsonb;
BEGIN
  IF p_table IS NULL OR NOT (p_table = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'invalid_table');
  END IF;

  IF p_payload IS NULL OR p_payload->>'sync_id' IS NULL THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'missing_sync_id');
  END IF;

  v_sync := (p_payload->>'sync_id')::uuid;

  IF p_request_id IS NOT NULL THEN
    SELECT outcome INTO v_outcome FROM public.zaib_sync_requests WHERE request_id = p_request_id;
    IF v_outcome IS NOT NULL THEN
      RETURN v_outcome || jsonb_build_object('idempotent', true);
    END IF;
  END IF;

  -- Strip client-controlled revision fields.
  v_payload := p_payload - 'server_rev' - 'expected_server_rev';
  v_want_delete := (v_payload ? 'deleted_at') AND (v_payload->>'deleted_at') IS NOT NULL
                  AND length(trim(v_payload->>'deleted_at')) > 0
                  AND lower(trim(v_payload->>'deleted_at')) <> 'null';

  IF p_allow_restore THEN
    PERFORM set_config('zaib.allow_restore', '1', true);
  ELSE
    PERFORM set_config('zaib.allow_restore', '0', true);
  END IF;

  EXECUTE format('SELECT to_jsonb(t), t.server_rev, t.deleted_at FROM public.%I t WHERE sync_id = $1 FOR UPDATE', p_table)
    INTO v_existing, v_cur_rev, v_deleted_at
    USING v_sync;

  -- Missing row
  IF v_existing IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.zaib_deleted_registry r
      WHERE r.cloud_table = p_table AND r.sync_id = v_sync
    ) AND NOT p_allow_restore THEN
      SELECT jsonb_build_object(
        'status', 'deleted',
        'sync_id', v_sync,
        'server_rev', r.server_rev,
        'deleted_at', r.deleted_at,
        'row', NULL
      ) INTO v_outcome
      FROM public.zaib_deleted_registry r
      WHERE r.cloud_table = p_table AND r.sync_id = v_sync;
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
        VALUES (p_request_id, p_table, v_sync, v_outcome)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;

    -- Insert path: expected_rev must be NULL (new row).
    IF p_expected_rev IS NOT NULL THEN
      v_outcome := jsonb_build_object('status', 'conflict', 'reason', 'expected_rev_for_missing_row', 'sync_id', v_sync);
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
        VALUES (p_request_id, p_table, v_sync, v_outcome)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;

    EXECUTE format('INSERT INTO public.%I SELECT * FROM jsonb_populate_record(NULL::public.%I, $1)', p_table, p_table)
      USING v_payload;

    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE sync_id = $1', p_table)
      INTO v_row USING v_sync;

    v_outcome := jsonb_build_object(
      'status', 'accepted',
      'sync_id', v_sync,
      'server_rev', (v_row->>'server_rev')::bigint,
      'updated_at', v_row->>'updated_at',
      'device_id', v_row->>'device_id',
      'deleted_at', v_row->>'deleted_at',
      'row', v_row
    );
    IF p_request_id IS NOT NULL THEN
      INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
      VALUES (p_request_id, p_table, v_sync, v_outcome)
      ON CONFLICT (request_id) DO NOTHING;
    END IF;
    RETURN v_outcome;
  END IF;

  -- Existing deleted row
  IF v_deleted_at IS NOT NULL THEN
    IF v_want_delete THEN
      -- Idempotent delete ack
      v_outcome := jsonb_build_object(
        'status', 'duplicate',
        'sync_id', v_sync,
        'server_rev', v_cur_rev,
        'deleted_at', v_deleted_at,
        'updated_at', v_existing->>'updated_at',
        'device_id', v_existing->>'device_id',
        'row', v_existing
      );
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
        VALUES (p_request_id, p_table, v_sync, v_outcome)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;

    IF NOT p_allow_restore THEN
      v_outcome := jsonb_build_object(
        'status', 'deleted',
        'sync_id', v_sync,
        'server_rev', v_cur_rev,
        'deleted_at', v_deleted_at,
        'row', v_existing
      );
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
        VALUES (p_request_id, p_table, v_sync, v_outcome)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome; -- no mutation, no feed
    END IF;
    -- allow_restore falls through to update
  END IF;

  -- Live (or restore) OCC check
  IF p_expected_rev IS NULL THEN
    -- Bootstrap: only allow when server_rev is still NULL (never published revision).
    IF v_cur_rev IS NOT NULL THEN
      v_outcome := jsonb_build_object(
        'status', 'conflict',
        'reason', 'expected_rev_required',
        'sync_id', v_sync,
        'server_rev', v_cur_rev,
        'updated_at', v_existing->>'updated_at',
        'device_id', v_existing->>'device_id',
        'deleted_at', v_existing->>'deleted_at',
        'row', v_existing
      );
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
        VALUES (p_request_id, p_table, v_sync, v_outcome)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;
  ELSIF p_expected_rev IS DISTINCT FROM v_cur_rev THEN
    v_outcome := jsonb_build_object(
      'status', 'conflict',
      'reason', 'rev_mismatch',
      'sync_id', v_sync,
      'server_rev', v_cur_rev,
      'expected_rev', p_expected_rev,
      'updated_at', v_existing->>'updated_at',
      'device_id', v_existing->>'device_id',
      'deleted_at', v_existing->>'deleted_at',
      'row', v_existing
    );
    IF p_request_id IS NOT NULL THEN
      INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
      VALUES (p_request_id, p_table, v_sync, v_outcome)
      ON CONFLICT (request_id) DO NOTHING;
    END IF;
    RETURN v_outcome;
  END IF;

  -- Merge existing JSON with client payload (client keys win); server_rev never from client.
  v_payload := (v_existing - 'server_rev') || (v_payload - 'server_rev');
  v_payload := jsonb_set(v_payload, '{sync_id}', to_jsonb(v_sync), true);

  SELECT string_agg(format('%I = s.%I', column_name, column_name), ', ')
  INTO v_sets
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = p_table
    AND column_name NOT IN ('sync_id', 'server_rev');

  IF v_sets IS NULL OR length(v_sets) = 0 THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'no_updatable_columns');
  END IF;

  EXECUTE format(
    'UPDATE public.%I t SET %s
     FROM jsonb_populate_record(NULL::public.%I, $1) s
     WHERE t.sync_id = $2',
    p_table, v_sets, p_table
  ) USING v_payload, v_sync;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE sync_id = $1', p_table)
    INTO v_row USING v_sync;

  v_outcome := jsonb_build_object(
    'status', 'accepted',
    'sync_id', v_sync,
    'server_rev', (v_row->>'server_rev')::bigint,
    'updated_at', v_row->>'updated_at',
    'device_id', v_row->>'device_id',
    'deleted_at', v_row->>'deleted_at',
    'row', v_row
  );
  IF p_request_id IS NOT NULL THEN
    INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome)
    VALUES (p_request_id, p_table, v_sync, v_outcome)
    ON CONFLICT (request_id) DO NOTHING;
  END IF;
  RETURN v_outcome;
END;
$$;

-- ---------------------------------------------------------------------------
-- Privilege lockdown
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'zaib_customers','zaib_dealers','zaib_petrol_entries','zaib_dealer_payouts',
    'zaib_dealer_purchases','zaib_dealer_direct','zaib_stock_diesel',
    'zaib_bank_transactions','zaib_expenses','zaib_dealer_balance_ops',
    'zaib_dealer_transfers'
  ]
  LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM anon, authenticated', t);
    EXECUTE format('GRANT SELECT ON public.%I TO anon, authenticated', t);
  END LOOP;
END $$;

REVOKE ALL ON public.zaib_sync_pub FROM anon, authenticated, PUBLIC;
ALTER TABLE public.zaib_sync_pub ENABLE ROW LEVEL SECURITY;
-- No policies for anon/auth → deny; service_role / owner still full access for triggers.

REVOKE ALL ON public.zaib_sync_feed FROM anon, authenticated, PUBLIC;
GRANT SELECT ON public.zaib_sync_feed TO anon, authenticated;
DROP POLICY IF EXISTS zaib_sync_feed_anon_all ON public.zaib_sync_feed;
DROP POLICY IF EXISTS zaib_sync_feed_auth_all ON public.zaib_sync_feed;
CREATE POLICY zaib_sync_feed_select_anon ON public.zaib_sync_feed
  FOR SELECT TO anon USING (true);
CREATE POLICY zaib_sync_feed_select_auth ON public.zaib_sync_feed
  FOR SELECT TO authenticated USING (true);

REVOKE ALL ON public.zaib_sync_changes FROM anon, authenticated, PUBLIC;
GRANT SELECT ON public.zaib_sync_changes TO anon, authenticated;
DROP POLICY IF EXISTS zaib_sync_changes_anon_all ON public.zaib_sync_changes;
DROP POLICY IF EXISTS zaib_sync_changes_auth_all ON public.zaib_sync_changes;
CREATE POLICY zaib_sync_changes_select_anon ON public.zaib_sync_changes
  FOR SELECT TO anon USING (true);
CREATE POLICY zaib_sync_changes_select_auth ON public.zaib_sync_changes
  FOR SELECT TO authenticated USING (true);

REVOKE ALL ON FUNCTION public.zaib_record_sync_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.zaib_reject_stale_or_resurrect() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.zaib_sync_apply(text, jsonb, bigint, uuid, boolean) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.zaib_sync_apply(text, jsonb, bigint, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.zaib_sync_apply(text, jsonb, bigint, uuid, boolean) TO anon, authenticated;
