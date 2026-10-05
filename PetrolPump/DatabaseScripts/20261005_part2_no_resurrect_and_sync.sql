-- Part 2: never resurrect soft-deleted zaib rows via ordinary upsert.
-- Intentional restore must use a dedicated path (not a normal live update).
-- Additive / repeatable. Compatible with old clients (they simply cannot undelete).

CREATE OR REPLACE FUNCTION public.zaib_reject_stale_or_resurrect()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  -- Block stale clocks
  IF OLD.updated_at IS NOT NULL AND NEW.updated_at IS NOT NULL
     AND NEW.updated_at < OLD.updated_at THEN
    NEW := OLD;
    RETURN NEW;
  END IF;

  -- Never undelete via ordinary upsert, even if NEW.updated_at is newer.
  -- Restore requires intentional admin/RPC path, not a stale-device live row.
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    NEW := OLD;
    RETURN NEW;
  END IF;

  -- Equal timestamps: delete wins; else deterministic device_id tie-break
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
$function$;
