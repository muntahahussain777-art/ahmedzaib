-- Part 6: transactional publication counter (safe under concurrent writers + rollback).
--
-- PROTOCOL
--   Table zaib_sync_pub holds a single locked counter row (id=1).
--   On every entity INSERT/UPDATE/DELETE, zaib_record_sync_change():
--     1) UPDATE zaib_sync_pub SET next_rev = next_rev + 1 WHERE id = 1  -- row lock
--     2) INSERT into zaib_sync_feed with rev = previous next_rev
--   Steps run in the SAME transaction as the business write.
--   Rollback undoes the counter bump AND the feed event together.
--   Concurrent writers block on the counter row, so a later revision cannot
--   become visible before an earlier uncommitted revision commits.
--
--   Clients pull WHERE rev > cursor ORDER BY rev ASC.
--   Do NOT use PostgreSQL IDENTITY/BIGSERIAL as the pull watermark
--   (sequences leave permanent gaps after aborted transactions).
--   Do NOT bootstrap with MAX(id) without a full reconcile.
--
-- ROLLOUT
--   1) Apply this migration (additive).
--   2) Deploy WinForms + Flutter that read zaib_sync_feed (protocol v2).
--   3) Old clients reading zaib_sync_changes remain compatible during rollout
--      (legacy table still receives appends) but must be upgraded for safety.
--   4) Devices with flawed MAX-ID bootstrap are repaired by client-side
--      protocol-version detect + full snapshot reconcile before setting v2 cursor.
--
-- CONFLICT
--   Entity LWW still uses updated_at/device_id (client clocks). server_rev is
--   stamped on feed payloads; prefer higher server_rev when both sides carry it.

CREATE TABLE IF NOT EXISTS public.zaib_sync_pub (
  id integer PRIMARY KEY CHECK (id = 1),
  next_rev bigint NOT NULL DEFAULT 1
);
INSERT INTO public.zaib_sync_pub (id, next_rev) VALUES (1, 1)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.zaib_sync_feed (
  rev bigint PRIMARY KEY,
  cloud_table text NOT NULL,
  row_sync_id uuid NOT NULL,
  op text NOT NULL CHECK (op IN ('upsert', 'delete')),
  row_updated_at timestamptz,
  row_device_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_zaib_sync_feed_rev ON public.zaib_sync_feed (rev);
CREATE INDEX IF NOT EXISTS idx_zaib_sync_feed_table_sync ON public.zaib_sync_feed (cloud_table, row_sync_id);

ALTER TABLE public.zaib_sync_feed ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS zaib_sync_feed_anon_all ON public.zaib_sync_feed;
CREATE POLICY zaib_sync_feed_anon_all ON public.zaib_sync_feed
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS zaib_sync_feed_auth_all ON public.zaib_sync_feed;
CREATE POLICY zaib_sync_feed_auth_all ON public.zaib_sync_feed
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT SELECT, INSERT ON public.zaib_sync_feed TO anon, authenticated;
GRANT SELECT, UPDATE ON public.zaib_sync_pub TO anon, authenticated;

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
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS server_rev bigint', t);
  END LOOP;
END $$;

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
  v_row jsonb;
BEGIN
  -- Skip recursive stamp updates.
  IF current_setting('zaib.recording_feed', true) = '1' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Serialize publishers: lock counter row in THIS transaction.
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
  ELSE
    v_sync := NEW.sync_id;
    v_updated := NEW.updated_at;
    v_device := NEW.device_id;
    v_row := to_jsonb(NEW) || jsonb_build_object('server_rev', v_rev);
    v_payload := v_row;
    v_deleted := (NEW.deleted_at IS NOT NULL);
    v_op := CASE WHEN v_deleted THEN 'delete' ELSE 'upsert' END;
  END IF;

  IF v_sync IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  INSERT INTO public.zaib_sync_feed (rev, cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  VALUES (v_rev, TG_TABLE_NAME, v_sync, v_op, v_updated, v_device, v_payload);

  -- Legacy identity feed for older clients during coordinated rollout.
  BEGIN
    INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
    VALUES (TG_TABLE_NAME, v_sync, v_op, v_updated, v_device, v_payload);
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- Stamp server_rev on the entity without re-entering this trigger.
  IF TG_OP <> 'DELETE' THEN
    PERFORM set_config('zaib.recording_feed', '1', true);
    BEGIN
      EXECUTE format(
        'UPDATE public.%I SET server_rev = $1 WHERE sync_id = $2 AND (server_rev IS DISTINCT FROM $1)',
        TG_TABLE_NAME
      ) USING v_rev, v_sync;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM set_config('zaib.recording_feed', '0', true);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- AFTER triggers (feed only; LWW BEFORE runs first and may reject — if rejected,
-- this AFTER does not fire, so no leaked revision).
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
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_change_feed ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_%s_change_feed AFTER INSERT OR UPDATE OR DELETE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.zaib_record_sync_change()',
      t, t
    );
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.zaib_reject_stale_or_resurrect()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Shared atomic server revision wins when both sides carry it.
  IF NEW.server_rev IS NOT NULL AND OLD.server_rev IS NOT NULL THEN
    IF NEW.server_rev < OLD.server_rev THEN
      NEW := OLD;
      RETURN NEW;
    END IF;
    IF NEW.server_rev > OLD.server_rev THEN
      RETURN NEW;
    END IF;
  END IF;

  IF OLD.updated_at IS NOT NULL AND NEW.updated_at IS NOT NULL
     AND NEW.updated_at < OLD.updated_at THEN
    NEW := OLD;
    RETURN NEW;
  END IF;

  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    IF NEW.updated_at IS NULL OR NEW.updated_at <= OLD.updated_at THEN
      NEW := OLD;
      RETURN NEW;
    END IF;
  END IF;

  IF OLD.updated_at IS NOT NULL AND NEW.updated_at IS NOT NULL
     AND NEW.updated_at = OLD.updated_at THEN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
      RETURN NEW;
    END IF;
    IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      NEW := OLD;
      RETURN NEW;
    END IF;
    IF COALESCE(NEW.device_id, '') < COALESCE(OLD.device_id, '') THEN
      NEW := OLD;
      RETURN NEW;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- One-time backfill from legacy identity feed into gapless revs (only if empty).
DO $$
DECLARE
  cnt bigint;
  r record;
  v_rev bigint;
BEGIN
  SELECT COUNT(*) INTO cnt FROM public.zaib_sync_feed;
  IF cnt > 0 THEN
    RAISE NOTICE 'zaib_sync_feed already populated — skip backfill';
    RETURN;
  END IF;

  IF to_regclass('public.zaib_sync_changes') IS NULL THEN
    RETURN;
  END IF;

  FOR r IN
    SELECT cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload
    FROM public.zaib_sync_changes
    ORDER BY change_id ASC
  LOOP
    UPDATE public.zaib_sync_pub SET next_rev = next_rev + 1 WHERE id = 1
    RETURNING next_rev - 1 INTO v_rev;
    INSERT INTO public.zaib_sync_feed (rev, cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
    VALUES (v_rev, r.cloud_table, r.row_sync_id, r.op, r.row_updated_at, r.row_device_id, r.payload);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.zaib_record_sync_change() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zaib_reject_stale_or_resurrect() TO anon, authenticated;
