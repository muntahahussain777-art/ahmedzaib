-- Part 2 additive migration (repeatable): LWW + block stale undelete
-- Safe for anon clients using Prefer: resolution=merge-duplicates

CREATE OR REPLACE FUNCTION public.zaib_reject_stale_or_resurrect()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
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

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'zaib_customers','zaib_dealers','zaib_petrol_entries','zaib_dealer_payouts',
    'zaib_dealer_purchases','zaib_dealer_direct','zaib_stock_diesel',
    'zaib_bank_transactions','zaib_expenses'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_lww ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER trg_%s_lww BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.zaib_reject_stale_or_resurrect()',
      t, t
    );
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.zaib_reject_stale_or_resurrect() TO anon, authenticated;
