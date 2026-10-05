-- Part 8: trusted server_rev stamping, no public restore, request fingerprint,
-- repair entity.server_rev from published feed evidence.
--
-- ROOT CAUSE
--   AFTER trigger stamped server_rev via UPDATE, but BEFORE LWW always did
--   NEW.server_rev := OLD.server_rev, wiping the stamp. Entity.server_rev stayed
--   NULL/stale while feed.payload carried the allocated rev.
--
-- FIX
--   GUC zaib.stamping_rev=1 allows ONLY the trusted stamp UPDATE to change
--   server_rev. Clients still cannot set it. recording_feed=1 still suppresses
--   recursive feed publication. RPC checks ROW_COUNT so cancelled updates
--   never return accepted. p_allow_restore=true is rejected on the public RPC.
--   request_id is bound to (table, sync_id, payload hash).

-- ---------------------------------------------------------------------------
-- Request fingerprint columns (additive)
-- ---------------------------------------------------------------------------
ALTER TABLE public.zaib_sync_requests
  ADD COLUMN IF NOT EXISTS payload_hash text,
  ADD COLUMN IF NOT EXISTS cloud_table_check text,
  ADD COLUMN IF NOT EXISTS row_sync_id_check uuid;

-- ---------------------------------------------------------------------------
-- LWW: strip client server_rev; allow trusted stamp path
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.zaib_reject_stale_or_resurrect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Trusted internal stamp UPDATE (set by zaib_record_sync_change only).
  IF current_setting('zaib.stamping_rev', true) = '1' THEN
    RETURN NEW;
  END IF;

  -- Clients never choose server_rev.
  IF TG_OP = 'UPDATE' THEN
    NEW.server_rev := OLD.server_rev;
  ELSIF TG_OP = 'INSERT' THEN
    NEW.server_rev := NULL;
  END IF;

  -- No ordinary resurrection (admin sets zaib.allow_restore=1).
  IF TG_OP = 'UPDATE'
     AND OLD.deleted_at IS NOT NULL
     AND NEW.deleted_at IS NULL
     AND current_setting('zaib.allow_restore', true) IS DISTINCT FROM '1' THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.sync_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.zaib_deleted_registry r
      WHERE r.cloud_table = TG_TABLE_NAME AND r.sync_id = NEW.sync_id
    ) THEN
      RETURN NULL;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.updated_at IS NOT NULL AND NEW.updated_at IS NOT NULL
     AND NEW.updated_at < OLD.updated_at
     AND NOT (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
     AND NEW.deleted_at IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Publication: lock counter, feed, registry, stamp with trusted GUC
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
  v_stamp int;
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
    -- Payload carries allocated rev (entity stamp follows in same txn).
    v_payload := (to_jsonb(NEW) - 'server_rev') || jsonb_build_object('server_rev', v_rev);
    v_deleted := (NEW.deleted_at IS NOT NULL);
    v_op := CASE WHEN v_deleted THEN 'delete' ELSE 'upsert' END;
    IF v_deleted AND v_sync IS NOT NULL THEN
      INSERT INTO public.zaib_deleted_registry (cloud_table, sync_id, deleted_at, server_rev)
      VALUES (TG_TABLE_NAME, v_sync, NEW.deleted_at, v_rev)
      ON CONFLICT (cloud_table, sync_id) DO UPDATE
        SET deleted_at = EXCLUDED.deleted_at, server_rev = EXCLUDED.server_rev;
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
    PERFORM set_config('zaib.stamping_rev', '1', true);
    EXECUTE format(
      'UPDATE public.%I SET server_rev = $1 WHERE sync_id = $2',
      TG_TABLE_NAME
    ) USING v_rev, v_sync;
    GET DIAGNOSTICS v_stamp = ROW_COUNT;
    PERFORM set_config('zaib.stamping_rev', '0', true);
    PERFORM set_config('zaib.recording_feed', '0', true);
    IF v_stamp <> 1 THEN
      RAISE EXCEPTION 'zaib stamp failed for %.% rev=%', TG_TABLE_NAME, v_sync, v_rev;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION public.zaib_record_sync_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.zaib_reject_stale_or_resurrect() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC: no restore; ROW_COUNT checks; request fingerprint binding
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
  v_sets text;
  v_client jsonb;
  v_payload jsonb;
  v_hash text;
  v_n int;
  v_prev_hash text;
  v_prev_table text;
  v_prev_sync uuid;
BEGIN
  -- Public callers may never restore.
  IF COALESCE(p_allow_restore, false) THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'restore_not_allowed');
  END IF;
  PERFORM set_config('zaib.allow_restore', '0', true);

  IF p_table IS NULL OR NOT (p_table = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'invalid_table');
  END IF;
  IF p_payload IS NULL OR p_payload->>'sync_id' IS NULL THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'missing_sync_id');
  END IF;

  v_sync := (p_payload->>'sync_id')::uuid;
  v_client := p_payload - 'server_rev' - 'expected_server_rev';
  v_hash := md5(p_table || '|' || v_sync::text || '|' || v_client::text);

  IF p_request_id IS NOT NULL THEN
    SELECT outcome, payload_hash, cloud_table_check, row_sync_id_check
      INTO v_outcome, v_prev_hash, v_prev_table, v_prev_sync
    FROM public.zaib_sync_requests WHERE request_id = p_request_id;
    IF v_outcome IS NOT NULL THEN
      IF v_prev_hash IS DISTINCT FROM v_hash
         OR v_prev_table IS DISTINCT FROM p_table
         OR v_prev_sync IS DISTINCT FROM v_sync THEN
        RETURN jsonb_build_object(
          'status', 'rejected',
          'reason', 'request_id_payload_mismatch',
          'sync_id', v_sync
        );
      END IF;
      RETURN v_outcome || jsonb_build_object('idempotent', true);
    END IF;
  END IF;

  v_want_delete := (v_client ? 'deleted_at') AND (v_client->>'deleted_at') IS NOT NULL
                  AND length(trim(v_client->>'deleted_at')) > 0
                  AND lower(trim(v_client->>'deleted_at')) <> 'null';

  EXECUTE format(
    'SELECT to_jsonb(t), t.server_rev, t.deleted_at FROM public.%I t WHERE sync_id = $1 FOR UPDATE',
    p_table
  ) INTO v_existing, v_cur_rev, v_deleted_at USING v_sync;

  -- Helper to persist request outcome
  -- (inlined at each return)

  IF v_existing IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.zaib_deleted_registry r
      WHERE r.cloud_table = p_table AND r.sync_id = v_sync
    ) THEN
      SELECT jsonb_build_object(
        'status', 'deleted', 'sync_id', v_sync,
        'server_rev', r.server_rev, 'deleted_at', r.deleted_at, 'row', NULL
      ) INTO v_outcome
      FROM public.zaib_deleted_registry r
      WHERE r.cloud_table = p_table AND r.sync_id = v_sync;
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
        VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;

    IF p_expected_rev IS NOT NULL THEN
      v_outcome := jsonb_build_object('status', 'conflict', 'reason', 'expected_rev_for_missing_row', 'sync_id', v_sync);
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
        VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;

    EXECUTE format(
      'INSERT INTO public.%I SELECT * FROM jsonb_populate_record(NULL::public.%I, $1)',
      p_table, p_table
    ) USING v_client;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN
      RETURN jsonb_build_object('status', 'rejected', 'reason', 'insert_cancelled', 'sync_id', v_sync);
    END IF;

    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE sync_id = $1', p_table)
      INTO v_row USING v_sync;

    v_outcome := jsonb_build_object(
      'status', 'accepted', 'sync_id', v_sync,
      'server_rev', (v_row->>'server_rev')::bigint,
      'updated_at', v_row->>'updated_at', 'device_id', v_row->>'device_id',
      'deleted_at', v_row->>'deleted_at', 'row', v_row
    );
    IF p_request_id IS NOT NULL THEN
      INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
      VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
      ON CONFLICT (request_id) DO NOTHING;
    END IF;
    RETURN v_outcome;
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    IF v_want_delete THEN
      v_outcome := jsonb_build_object(
        'status', 'duplicate', 'sync_id', v_sync, 'server_rev', v_cur_rev,
        'deleted_at', v_deleted_at, 'updated_at', v_existing->>'updated_at',
        'device_id', v_existing->>'device_id', 'row', v_existing
      );
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
        VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;

    v_outcome := jsonb_build_object(
      'status', 'deleted', 'sync_id', v_sync, 'server_rev', v_cur_rev,
      'deleted_at', v_deleted_at, 'row', v_existing
    );
    IF p_request_id IS NOT NULL THEN
      INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
      VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
      ON CONFLICT (request_id) DO NOTHING;
    END IF;
    RETURN v_outcome;
  END IF;

  IF p_expected_rev IS NULL THEN
    IF v_cur_rev IS NOT NULL THEN
      v_outcome := jsonb_build_object(
        'status', 'conflict', 'reason', 'expected_rev_required',
        'sync_id', v_sync, 'server_rev', v_cur_rev,
        'updated_at', v_existing->>'updated_at', 'device_id', v_existing->>'device_id',
        'deleted_at', v_existing->>'deleted_at', 'row', v_existing
      );
      IF p_request_id IS NOT NULL THEN
        INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
        VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
        ON CONFLICT (request_id) DO NOTHING;
      END IF;
      RETURN v_outcome;
    END IF;
  ELSIF p_expected_rev IS DISTINCT FROM v_cur_rev THEN
    v_outcome := jsonb_build_object(
      'status', 'conflict', 'reason', 'rev_mismatch',
      'sync_id', v_sync, 'server_rev', v_cur_rev, 'expected_rev', p_expected_rev,
      'updated_at', v_existing->>'updated_at', 'device_id', v_existing->>'device_id',
      'deleted_at', v_existing->>'deleted_at', 'row', v_existing
    );
    IF p_request_id IS NOT NULL THEN
      INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
      VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
      ON CONFLICT (request_id) DO NOTHING;
    END IF;
    RETURN v_outcome;
  END IF;

  v_payload := (v_existing - 'server_rev') || v_client;
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
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    -- BEFORE trigger cancelled (RETURN NULL) or concurrent delete.
    RETURN jsonb_build_object(
      'status', 'rejected',
      'reason', 'update_cancelled',
      'sync_id', v_sync,
      'server_rev', v_cur_rev
    );
  END IF;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE sync_id = $1', p_table)
    INTO v_row USING v_sync;

  v_outcome := jsonb_build_object(
    'status', 'accepted', 'sync_id', v_sync,
    'server_rev', (v_row->>'server_rev')::bigint,
    'updated_at', v_row->>'updated_at', 'device_id', v_row->>'device_id',
    'deleted_at', v_row->>'deleted_at', 'row', v_row
  );
  IF p_request_id IS NOT NULL THEN
    INSERT INTO public.zaib_sync_requests(request_id, cloud_table, row_sync_id, outcome, payload_hash, cloud_table_check, row_sync_id_check)
    VALUES (p_request_id, p_table, v_sync, v_outcome, v_hash, p_table, v_sync)
    ON CONFLICT (request_id) DO NOTHING;
  END IF;
  RETURN v_outcome;
END;
$$;

REVOKE ALL ON FUNCTION public.zaib_sync_apply(text, jsonb, bigint, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.zaib_sync_apply(text, jsonb, bigint, uuid, boolean) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Administrative restore only (service_role). Not granted to anon/authenticated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.zaib_sync_apply_admin(
  p_table text,
  p_payload jsonb,
  p_expected_rev bigint DEFAULT NULL,
  p_request_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sync uuid;
  v_client jsonb;
  v_n int;
BEGIN
  IF p_payload IS NULL OR p_payload->>'sync_id' IS NULL THEN
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'missing_sync_id');
  END IF;
  v_sync := (p_payload->>'sync_id')::uuid;
  v_client := p_payload - 'server_rev' - 'expected_server_rev';

  -- Authorized restore: clear registry + allow BEFORE trigger undelete.
  PERFORM set_config('zaib.allow_restore', '1', true);
  DELETE FROM public.zaib_deleted_registry
  WHERE cloud_table = p_table AND sync_id = v_sync;

  BEGIN
    EXECUTE format(
      'UPDATE public.%I SET deleted_at = NULL WHERE sync_id = $1 AND deleted_at IS NOT NULL',
      p_table
    ) USING v_sync;
    GET DIAGNOSTICS v_n = ROW_COUNT;
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    v_n := 0;
  END;

  -- Ordinary OCC apply (public restore flag stays false).
  RETURN public.zaib_sync_apply(p_table, v_client, p_expected_rev, p_request_id, false);
END;
$$;

REVOKE ALL ON FUNCTION public.zaib_sync_apply_admin(text, jsonb, bigint, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zaib_sync_apply_admin(text, jsonb, bigint, uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- Repair entity.server_rev from latest published feed evidence (additive)
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
    EXECUTE format(
      'UPDATE public.%I e
       SET server_rev = f.rev
       FROM (
         SELECT DISTINCT ON (row_sync_id) row_sync_id, rev
         FROM public.zaib_sync_feed
         WHERE cloud_table = %L
         ORDER BY row_sync_id, rev DESC
       ) f
       WHERE e.sync_id = f.row_sync_id
         AND e.server_rev IS DISTINCT FROM f.rev',
      t, t
    );
  END LOOP;
END $$;
