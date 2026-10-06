-- Part 5: commit-safe change feed for late-arriving offline sync.
-- Protocol: BIGSERIAL change_id + contiguous watermark (not MAX-seen).
-- Concurrent txns may allocate IDs out of commit order; clients advance only
-- through contiguous change_id values so a late commit with a lower ID is not skipped.
-- Entity LWW (updated_at/device_id) remains conflict authority; this feed is discovery only.

CREATE TABLE IF NOT EXISTS public.zaib_sync_changes (
  change_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cloud_table text NOT NULL,
  row_sync_id uuid NOT NULL,
  op text NOT NULL CHECK (op IN ('upsert', 'delete')),
  row_updated_at timestamptz,
  row_device_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_zaib_sync_changes_change_id ON public.zaib_sync_changes (change_id);
CREATE INDEX IF NOT EXISTS idx_zaib_sync_changes_table_sync ON public.zaib_sync_changes (cloud_table, row_sync_id);

ALTER TABLE public.zaib_sync_changes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS zaib_sync_changes_anon_all ON public.zaib_sync_changes;
CREATE POLICY zaib_sync_changes_anon_all ON public.zaib_sync_changes
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS zaib_sync_changes_auth_all ON public.zaib_sync_changes;
CREATE POLICY zaib_sync_changes_auth_all ON public.zaib_sync_changes
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT SELECT, INSERT ON public.zaib_sync_changes TO anon, authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

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
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_sync := OLD.sync_id;
    v_updated := OLD.updated_at;
    v_device := OLD.device_id;
    v_payload := to_jsonb(OLD);
    v_op := 'delete';
  ELSE
    v_sync := NEW.sync_id;
    v_updated := NEW.updated_at;
    v_device := NEW.device_id;
    v_payload := to_jsonb(NEW);
    v_deleted := (NEW.deleted_at IS NOT NULL);
    v_op := CASE WHEN v_deleted THEN 'delete' ELSE 'upsert' END;
  END IF;

  IF v_sync IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  VALUES (TG_TABLE_NAME, v_sync, v_op, v_updated, v_device, v_payload);

  RETURN COALESCE(NEW, OLD);
END;
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'zaib_customers','zaib_dealers','zaib_petrol_entries','zaib_dealer_payouts',
    'zaib_dealer_purchases','zaib_dealer_direct','zaib_stock_diesel',
    'zaib_bank_transactions','zaib_expenses','zaib_dealer_balance_ops'
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

-- Bootstrap existing rows into the feed (idempotent only if feed empty for that table).
-- Clients with legacy data should set change cursor to max(change_id) after this migration
-- so they do not re-apply history they already hold. New empty devices start at 0.
DO $$
DECLARE
  cnt bigint;
BEGIN
  SELECT COUNT(*) INTO cnt FROM public.zaib_sync_changes;
  IF cnt > 0 THEN
    RAISE NOTICE 'zaib_sync_changes already has %% rows — skip bootstrap', cnt;
    RETURN;
  END IF;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_customers', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_customers t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_dealers', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_dealers t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_petrol_entries', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_petrol_entries t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_dealer_payouts', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_dealer_payouts t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_dealer_purchases', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_dealer_purchases t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_dealer_direct', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_dealer_direct t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_stock_diesel', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_stock_diesel t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_bank_transactions', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_bank_transactions t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_expenses', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_expenses t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;

  INSERT INTO public.zaib_sync_changes (cloud_table, row_sync_id, op, row_updated_at, row_device_id, payload)
  SELECT 'zaib_dealer_balance_ops', sync_id,
         CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
         updated_at, device_id, to_jsonb(t)
  FROM public.zaib_dealer_balance_ops t WHERE sync_id IS NOT NULL
  ORDER BY updated_at NULLS FIRST, sync_id;
END $$;

-- Dealer-to-dealer transfers (cross-device)
CREATE TABLE IF NOT EXISTS public.zaib_dealer_transfers (
  sync_id uuid PRIMARY KEY,
  local_id integer,
  from_dealer_sync_id uuid,
  to_dealer_sync_id uuid,
  amount double precision NOT NULL DEFAULT 0,
  date_text text,
  note text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  device_id text
);
CREATE INDEX IF NOT EXISTS idx_zaib_dealer_transfers_updated ON public.zaib_dealer_transfers (updated_at);
ALTER TABLE public.zaib_dealer_transfers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS zaib_dealer_transfers_anon_all ON public.zaib_dealer_transfers;
CREATE POLICY zaib_dealer_transfers_anon_all ON public.zaib_dealer_transfers
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS zaib_dealer_transfers_auth_all ON public.zaib_dealer_transfers;
CREATE POLICY zaib_dealer_transfers_auth_all ON public.zaib_dealer_transfers
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP TRIGGER IF EXISTS trg_zaib_dealer_transfers_lww ON public.zaib_dealer_transfers;
CREATE TRIGGER trg_zaib_dealer_transfers_lww
  BEFORE UPDATE ON public.zaib_dealer_transfers
  FOR EACH ROW EXECUTE FUNCTION public.zaib_reject_stale_or_resurrect();
DROP TRIGGER IF EXISTS trg_zaib_dealer_transfers_change_feed ON public.zaib_dealer_transfers;
CREATE TRIGGER trg_zaib_dealer_transfers_change_feed
  AFTER INSERT OR UPDATE OR DELETE ON public.zaib_dealer_transfers
  FOR EACH ROW EXECUTE FUNCTION public.zaib_record_sync_change();
GRANT SELECT, INSERT, UPDATE, DELETE ON public.zaib_dealer_transfers TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.zaib_record_sync_change() TO anon, authenticated;
