-- Part 3: server-side idempotent dealer balance deltas (manual/opening/closing).
-- Child payout/purchase/direct still sync as rows; clients apply those deltas locally
-- via SyncBalanceApplied. This table carries explicit non-child balance mutations.

CREATE TABLE IF NOT EXISTS public.zaib_dealer_balance_ops (
  sync_id uuid PRIMARY KEY,
  dealer_sync_id uuid NOT NULL,
  dd_delta double precision NOT NULL DEFAULT 0,
  d_delta double precision NOT NULL DEFAULT 0,
  source_kind text NOT NULL DEFAULT 'manual',
  source_sync_id text,
  date_text text,
  note text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  device_id text
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_zaib_balance_ops_source
  ON public.zaib_dealer_balance_ops (source_kind, source_sync_id)
  WHERE source_sync_id IS NOT NULL AND source_sync_id <> '' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_zaib_balance_ops_updated
  ON public.zaib_dealer_balance_ops (updated_at);

CREATE INDEX IF NOT EXISTS idx_zaib_balance_ops_dealer
  ON public.zaib_dealer_balance_ops (dealer_sync_id);

ALTER TABLE public.zaib_dealer_balance_ops ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS zaib_balance_ops_anon_all ON public.zaib_dealer_balance_ops;
CREATE POLICY zaib_balance_ops_anon_all ON public.zaib_dealer_balance_ops
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS zaib_balance_ops_auth_all ON public.zaib_dealer_balance_ops;
CREATE POLICY zaib_balance_ops_auth_all ON public.zaib_dealer_balance_ops
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP TRIGGER IF EXISTS trg_zaib_dealer_balance_ops_lww ON public.zaib_dealer_balance_ops;
CREATE TRIGGER trg_zaib_dealer_balance_ops_lww
  BEFORE UPDATE ON public.zaib_dealer_balance_ops
  FOR EACH ROW EXECUTE FUNCTION public.zaib_reject_stale_or_resurrect();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.zaib_dealer_balance_ops TO anon, authenticated;
