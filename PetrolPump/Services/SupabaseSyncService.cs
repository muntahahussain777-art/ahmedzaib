using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SQLite;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using ZaibPetroleumService.ProjectConnection;

namespace ZaibPetroleumService.Services
{
    /// <summary>
    /// Silent Mobileâ†”PC sync via Supabase schema zaibservice.
    /// Dedup = sync_id. No UI changes.
    /// </summary>
    public static class SupabaseSyncService
    {
        private const string Url = "https://hvcfaslsgewdfblfdsdn.supabase.co";
        private const string AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Y2Zhc2xzZ2V3ZGZibGZkc2RuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4ODUxNzcsImV4cCI6MjEwNDQ2MTE3N30.7VXn9EiF1lWZkmW3VVDn36Axx0xO5ypj0oAggHpMXIc";
        private const string Schema = "public";

        private static readonly HttpClient Http = CreateClient();
        private static System.Windows.Forms.Timer _timer;
        private static int _running;
        private static int _queued;
        private static string _deviceId;
        private static readonly Dictionary<string, string> _lastPullByTable =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private const string DefaultPull = "1970-01-01T00:00:00.000Z";
        private const int PageSize = 500;

        private static HttpClient CreateClient()
        {
            var c = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
            c.DefaultRequestHeaders.Add("apikey", AnonKey);
            c.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", AnonKey);
            c.DefaultRequestHeaders.Add("Accept-Profile", Schema);
            c.DefaultRequestHeaders.Add("Content-Profile", Schema);
            c.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            return c;
        }

        public static void StartSilent()
        {
            try
            {
                EnsureLocalSyncReady();
                LoadState();
                if (_timer == null)
                {
                    _timer = new System.Windows.Forms.Timer { Interval = 45000 };
                    _timer.Tick += async (s, e) => await SyncNowSafe();
                    _timer.Start();
                }
                Task.Run(async () => await SyncNowSafe());
            }
            catch
            {
                // silent
            }
        }

        private static string StatePath()
        {
            string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DiselPetrolPump");
            Directory.CreateDirectory(folder);
            return Path.Combine(folder, "zaib_sync_state.json");
        }

        private static void LoadState()
        {
            try
            {
                string path = StatePath();
                if (!File.Exists(path)) return;
                var jo = JObject.Parse(File.ReadAllText(path));
                _deviceId = jo.Value<string>("deviceId");
                var legacy = jo.Value<string>("lastPull");
                var byTable = jo["lastPullByTable"] as JObject;
                if (byTable != null)
                {
                    foreach (var p in byTable.Properties())
                        _lastPullByTable[p.Name] = p.Value?.ToString() ?? DefaultPull;
                }
                else if (!string.IsNullOrWhiteSpace(legacy))
                {
                    // Migrate single watermark to per-table checkpoints.
                    foreach (var t in CloudTables())
                        _lastPullByTable[t] = legacy;
                }
            }
            catch { }
            if (string.IsNullOrWhiteSpace(_deviceId))
                _deviceId = Guid.NewGuid().ToString();
        }

        private static string[] CloudTables()
        {
            return new[]
            {
                "zaib_customers","zaib_dealers","zaib_petrol_entries","zaib_dealer_payouts",
                "zaib_dealer_purchases","zaib_dealer_direct","zaib_stock_diesel",
                "zaib_bank_transactions","zaib_expenses"
            };
        }

        private static string GetCheckpoint(string cloudTable)
        {
            if (_lastPullByTable.TryGetValue(cloudTable, out var v) && !string.IsNullOrWhiteSpace(v))
                return v;
            return DefaultPull;
        }

        private static void SetCheckpoint(string cloudTable, string updatedAt)
        {
            if (string.IsNullOrWhiteSpace(updatedAt)) return;
            _lastPullByTable[cloudTable] = updatedAt;
            SaveState();
        }

        private static void SaveState()
        {
            try
            {
                var by = new JObject();
                foreach (var kv in _lastPullByTable)
                    by[kv.Key] = kv.Value;
                var jo = new JObject
                {
                    ["deviceId"] = _deviceId,
                    ["lastPullByTable"] = by
                };
                File.WriteAllText(StatePath(), jo.ToString(Formatting.None));
            }
            catch { }
        }

        public static void EnsureLocalSyncReady()
        {
            using (var con = new SQLiteConnection(projectconnection.ConnectionString))
            {
                con.Open();
                string[] tables =
                {
                    "AddCustomer","PetrolAdd","AddDealer","DieselLedgerCredit","AddStock",
                    "DieselLedgerDebit","StockDiesel","BankTransactions","Expensetable"
                };
                foreach (var t in tables)
                {
                    DatabaseSchemaManager.EnsureColumn(con, t, "SyncId", "TEXT");
                    DatabaseSchemaManager.EnsureColumn(con, t, "UpdatedAt", "TEXT");
                    DatabaseSchemaManager.EnsureColumn(con, t, "SyncDirty", "INTEGER DEFAULT 1");
                }

                Exec(con, @"CREATE TABLE IF NOT EXISTS SyncTombstone (
                    SyncId TEXT PRIMARY KEY,
                    CloudTable TEXT NOT NULL,
                    DeletedAt TEXT NOT NULL
                );");
                Exec(con, @"CREATE TABLE IF NOT EXISTS SyncApplyGuard (
                    Id INTEGER PRIMARY KEY CHECK (Id = 1)
                );");
                Exec(con, @"CREATE TABLE IF NOT EXISTS SyncFailLog (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    At TEXT NOT NULL,
                    Scope TEXT NOT NULL,
                    SyncId TEXT,
                    Message TEXT NOT NULL
                );");
                Exec(con, @"CREATE TABLE IF NOT EXISTS SyncStagedRemote (
                    SyncId TEXT NOT NULL,
                    CloudTable TEXT NOT NULL,
                    PayloadJson TEXT NOT NULL,
                    UpdatedAt TEXT NOT NULL,
                    PRIMARY KEY (CloudTable, SyncId)
                );");

                BackfillSyncIds(con, "AddCustomer", "id");
                BackfillSyncIds(con, "PetrolAdd", "pid");
                BackfillSyncIds(con, "AddDealer", "Did");
                BackfillSyncIds(con, "DieselLedgerCredit", "LedgerID");
                BackfillSyncIds(con, "AddStock", "Sid");
                BackfillSyncIds(con, "DieselLedgerDebit", "LedgerID");
                BackfillSyncIds(con, "StockDiesel", "SID");
                BackfillSyncIds(con, "BankTransactions", "Id");
                BackfillSyncIds(con, "Expensetable", "sid");

                // Mark dirty on business-column changes only (avoids sync loop)
                EnsureTrigger(con, "trg_sync_AddCustomer_ai", "AddCustomer", "INSERT", "Name,Mobile,Date");
                EnsureTrigger(con, "trg_sync_AddCustomer_au", "AddCustomer", "UPDATE", "Name,Mobile,Date");
                EnsureTrigger(con, "trg_sync_PetrolAdd_ai", "PetrolAdd", "INSERT", "Date,ReceiptNo,vehicle,Litter,Rate,Advance,Amount,Credit,Balance,Note,CustomerId,Processed,IsInitialEntry");
                EnsureTrigger(con, "trg_sync_PetrolAdd_au", "PetrolAdd", "UPDATE", "Date,ReceiptNo,vehicle,Litter,Rate,Advance,Amount,Credit,Balance,Note,CustomerId,Processed,IsInitialEntry");
                EnsureTrigger(con, "trg_sync_AddDealer_ai", "AddDealer", "INSERT", "DealerName,DDAmount,DAmount,Date");
                EnsureTrigger(con, "trg_sync_AddDealer_au", "AddDealer", "UPDATE", "DealerName,DDAmount,DAmount,Date");
                EnsureTrigger(con, "trg_sync_DieselLedgerCredit_ai", "DieselLedgerCredit", "INSERT", "Did,Date,AmounGiven,Note");
                EnsureTrigger(con, "trg_sync_DieselLedgerCredit_au", "DieselLedgerCredit", "UPDATE", "Did,Date,AmounGiven,Note");
                EnsureTrigger(con, "trg_sync_AddStock_ai", "AddStock", "INSERT", "Vehicle,Rate,SellDisel,Stock,Date,AddDisel,DealerId,Note");
                EnsureTrigger(con, "trg_sync_AddStock_au", "AddStock", "UPDATE", "Vehicle,Rate,SellDisel,Stock,Date,AddDisel,DealerId,Note");
                EnsureTrigger(con, "trg_sync_DieselLedgerDebit_ai", "DieselLedgerDebit", "INSERT", "Did,Date,AmounGiven,Note");
                EnsureTrigger(con, "trg_sync_DieselLedgerDebit_au", "DieselLedgerDebit", "UPDATE", "Did,Date,AmounGiven,Note");
                EnsureTrigger(con, "trg_sync_StockDiesel_ai", "StockDiesel", "INSERT", "SDid,Date,Vehicle,Litter,Rate,Credit,Debit,Note");
                EnsureTrigger(con, "trg_sync_StockDiesel_au", "StockDiesel", "UPDATE", "SDid,Date,Vehicle,Litter,Rate,Credit,Debit,Note");
                EnsureTrigger(con, "trg_sync_BankTransactions_ai", "BankTransactions", "INSERT", "TransactionDate,TransactionType,CustomerId,DealerId,Amount,Note,BankName");
                EnsureTrigger(con, "trg_sync_BankTransactions_au", "BankTransactions", "UPDATE", "TransactionDate,TransactionType,CustomerId,DealerId,Amount,Note,BankName");
                EnsureTrigger(con, "trg_sync_Expensetable_ai", "Expensetable", "INSERT", "Name,Category,Amount,EDate,Note");
                EnsureTrigger(con, "trg_sync_Expensetable_au", "Expensetable", "UPDATE", "Name,Category,Amount,EDate,Note");
            }
        }

        private static void EnsureTrigger(SQLiteConnection con, string name, string table, string evt, string cols)
        {
            string pk = PrimaryKey(table);
            string ofCols = evt == "UPDATE" ? (" OF " + cols) : "";
            // DROP+CREATE so WHEN guard is applied (IF NOT EXISTS would keep old body).
            Exec(con, $"DROP TRIGGER IF EXISTS {name}");
            string sql = $@"
CREATE TRIGGER {name}
AFTER {evt}{ofCols} ON {table}
WHEN (SELECT COUNT(*) FROM SyncApplyGuard) = 0
BEGIN
  UPDATE {table}
  SET SyncDirty = 1,
      UpdatedAt = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
      SyncId = CASE WHEN SyncId IS NULL OR SyncId = '' THEN lower(hex(randomblob(16))) ELSE SyncId END
  WHERE {pk} = NEW.{pk};
END;";
            Exec(con, sql);
        }

        private static void BeginRemoteApply(SQLiteConnection con)
        {
            try { Exec(con, "INSERT OR IGNORE INTO SyncApplyGuard(Id) VALUES(1)"); } catch { }
        }

        private static void EndRemoteApply(SQLiteConnection con)
        {
            try { Exec(con, "DELETE FROM SyncApplyGuard"); } catch { }
        }

        private static void LogFail(SQLiteConnection con, string scope, string syncId, Exception ex)
        {
            try
            {
                string msg = (ex?.Message ?? "error");
                if (msg.Length > 500) msg = msg.Substring(0, 500);
                msg = System.Text.RegularExpressions.Regex.Replace(msg, @"eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+", "[redacted-jwt]");
                using (var cmd = new SQLiteCommand(
                    "INSERT INTO SyncFailLog(At,Scope,SyncId,Message) VALUES(@a,@s,@i,@m)", con))
                {
                    cmd.Parameters.AddWithValue("@a", DateTime.UtcNow.ToString("o"));
                    cmd.Parameters.AddWithValue("@s", scope ?? "");
                    cmd.Parameters.AddWithValue("@i", (object)syncId ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@m", msg);
                    cmd.ExecuteNonQuery();
                }
            }
            catch { }
        }

        private static string PrimaryKey(string table)
        {
            switch (table)
            {
                case "AddCustomer": return "id";
                case "PetrolAdd": return "pid";
                case "AddDealer": return "Did";
                case "DieselLedgerCredit": return "LedgerID";
                case "AddStock": return "Sid";
                case "DieselLedgerDebit": return "LedgerID";
                case "StockDiesel": return "SID";
                case "BankTransactions": return "Id";
                case "Expensetable": return "sid";
                default: return "rowid";
            }
        }

        private static void BackfillSyncIds(SQLiteConnection con, string table, string pk)
        {
            if (!TableExists(con, table)) return;
            using (var cmd = new SQLiteCommand($"SELECT {pk} FROM {table} WHERE SyncId IS NULL OR SyncId = ''", con))
            using (var r = cmd.ExecuteReader())
            {
                var ids = new List<object>();
                while (r.Read()) ids.Add(r[0]);
                r.Close();
                foreach (var id in ids)
                {
                    using (var u = new SQLiteCommand(
                        $"UPDATE {table} SET SyncId=@s, UpdatedAt=@t, SyncDirty=1 WHERE {pk}=@id", con))
                    {
                        u.Parameters.AddWithValue("@s", Guid.NewGuid().ToString());
                        u.Parameters.AddWithValue("@t", DateTime.UtcNow.ToString("o"));
                        u.Parameters.AddWithValue("@id", id);
                        u.ExecuteNonQuery();
                    }
                }
            }
        }

        private static bool TableExists(SQLiteConnection con, string table)
        {
            using (var cmd = new SQLiteCommand("SELECT 1 FROM sqlite_master WHERE type='table' AND name=@n LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@n", table);
                return cmd.ExecuteScalar() != null;
            }
        }

        private static void Exec(SQLiteConnection con, string sql)
        {
            using (var cmd = new SQLiteCommand(sql, con))
                cmd.ExecuteNonQuery();
        }

        private static async Task SyncNowSafe()
        {
            if (Interlocked.Exchange(ref _running, 1) == 1)
            {
                Interlocked.Exchange(ref _queued, 1);
                return;
            }
            try
            {
                EnsureLocalSyncReady();
                using (var con = new SQLiteConnection(projectconnection.ConnectionString))
                {
                    con.Open();
                    // Deletes first, then parents→children, then protected pull.
                    await PushTombstones(con);
                    await PushCustomers(con);
                    await PushDealers(con);
                    await PushPetrol(con);
                    await PushPayouts(con);
                    await PushPurchases(con);
                    await PushDirect(con);
                    await PushStock(con);
                    await PushBank(con);
                    await PushExpenses(con);

                    BeginRemoteApply(con);
                    try
                    {
                        await PullCustomers(con);
                        await PullDealers(con);
                        await PullPetrol(con);
                        await PullPayouts(con);
                        await PullPurchases(con);
                        await PullDirect(con);
                        await PullStock(con);
                        await PullBank(con);
                        await PullExpenses(con);
                        await FlushStaged(con);
                    }
                    finally
                    {
                        EndRemoteApply(con);
                    }
                }
            }
            catch (Exception ex)
            {
                try
                {
                    using (var con = new SQLiteConnection(projectconnection.ConnectionString))
                    {
                        con.Open();
                        LogFail(con, "syncNow", null, ex);
                    }
                }
                catch { }
            }
            finally
            {
                Interlocked.Exchange(ref _running, 0);
                if (Interlocked.Exchange(ref _queued, 0) == 1)
                    await SyncNowSafe();
            }
        }

        private static async Task<bool> UpsertAsync(string table, object row)
        {
            string json = JsonConvert.SerializeObject(row);
            var req = new HttpRequestMessage(HttpMethod.Post, $"{Url}/rest/v1/{table}?on_conflict=sync_id")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            req.Headers.Add("Prefer", "resolution=merge-duplicates,return=representation");
            var res = await Http.SendAsync(req);
            res.EnsureSuccessStatusCode();
            string body = await res.Content.ReadAsStringAsync();
            if (string.IsNullOrWhiteSpace(body) || body == "[]") return true;
            try
            {
                var arr = JArray.Parse(body);
                if (arr.Count == 0) return true;
                var returned = arr[0] as JObject;
                var uploaded = JObject.Parse(json);
                string upAt = uploaded.Value<string>("updated_at");
                string retAt = returned?.Value<string>("updated_at");
                string upDev = uploaded.Value<string>("device_id");
                string retDev = returned?.Value<string>("device_id");
                if (string.IsNullOrWhiteSpace(upAt) || string.IsNullOrWhiteSpace(retAt)) return true;
                DateTime u = DateTime.TryParse(upAt, out var ut) ? ut.ToUniversalTime() : DateTime.MinValue;
                DateTime r = DateTime.TryParse(retAt, out var rt) ? rt.ToUniversalTime() : DateTime.MinValue;
                if (u != r) return false;
                if (!string.IsNullOrEmpty(upDev) && !string.IsNullOrEmpty(retDev) && upDev != retDev) return false;
                return true;
            }
            catch
            {
                return true;
            }
        }

        private static async Task<List<JObject>> SelectSincePagedAsync(string table)
        {
            var all = new List<JObject>();
            string since = GetCheckpoint(table);
            int from = 0;
            while (true)
            {
                string url =
                    $"{Url}/rest/v1/{table}?select=*&updated_at=gt.{Uri.EscapeDataString(since)}" +
                    $"&order=updated_at.asc,sync_id.asc&limit={PageSize}&offset={from}";
                var res = await Http.GetAsync(url);
                res.EnsureSuccessStatusCode();
                string body = await res.Content.ReadAsStringAsync();
                var arr = JArray.Parse(string.IsNullOrWhiteSpace(body) ? "[]" : body);
                foreach (var t in arr)
                {
                    if (t is JObject jo) all.Add(jo);
                }
                if (arr.Count < PageSize) break;
                from += PageSize;
            }
            return all;
        }

        private static void MarkCleanIfVersion(SQLiteConnection con, string table, string pk, object id, string syncId, string uploadedUpdatedAt)
        {
            using (var cmd = new SQLiteCommand(
                $"UPDATE {table} SET SyncDirty=0, SyncId=@s WHERE {pk}=@id AND UpdatedAt=@u", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                cmd.Parameters.AddWithValue("@id", id);
                cmd.Parameters.AddWithValue("@u", uploadedUpdatedAt ?? "");
                cmd.ExecuteNonQuery();
            }
        }

        private static bool ParentReady(SQLiteConnection con, string table, string pk, object id)
        {
            if (id == null || id == DBNull.Value) return true;
            using (var cmd = new SQLiteCommand(
                $"SELECT SyncId, SyncDirty FROM {table} WHERE {pk}=@id LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@id", id);
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) return false;
                    string syncId = r["SyncId"] == DBNull.Value ? null : Convert.ToString(r["SyncId"]);
                    if (string.IsNullOrWhiteSpace(syncId)) return false;
                    int dirty = r["SyncDirty"] == DBNull.Value ? 0 : Convert.ToInt32(r["SyncDirty"]);
                    return dirty == 0;
                }
            }
        }

        private static string RowUpdatedAt(DataRow r)
        {
            string v = Convert.ToString(r["UpdatedAt"]);
            return string.IsNullOrWhiteSpace(v) ? DateTime.UtcNow.ToString("o") : v;
        }

        private static void AdvanceCheckpoint(string cloudTable, string updatedAt, ref string appliedMax)
        {
            if (string.IsNullOrWhiteSpace(updatedAt)) return;
            DateTime u = DateTime.TryParse(updatedAt, out var ut) ? ut.ToUniversalTime() : DateTime.MinValue;
            DateTime m = DateTime.TryParse(appliedMax, out var mt) ? mt.ToUniversalTime() : DateTime.MinValue;
            if (u >= m) appliedMax = updatedAt;
        }

        private static void StageRemote(SQLiteConnection con, string cloudTable, JObject row)
        {
            string syncId = row.Value<string>("sync_id");
            if (string.IsNullOrWhiteSpace(syncId)) return;
            using (var cmd = new SQLiteCommand(
                @"INSERT OR REPLACE INTO SyncStagedRemote(SyncId,CloudTable,PayloadJson,UpdatedAt)
                  VALUES(@s,@t,@p,@u)", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                cmd.Parameters.AddWithValue("@t", cloudTable);
                cmd.Parameters.AddWithValue("@p", row.ToString(Formatting.None));
                cmd.Parameters.AddWithValue("@u", row.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o"));
                cmd.ExecuteNonQuery();
            }
        }

        private static string GetSyncId(SQLiteConnection con, string table, string pk, object id)
        {
            if (id == null || id == DBNull.Value) return null;
            using (var cmd = new SQLiteCommand($"SELECT SyncId FROM {table} WHERE {pk}=@id LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@id", id);
                var v = cmd.ExecuteScalar();
                return v == null || v == DBNull.Value ? null : v.ToString();
            }
        }

        private static DataTable QueryDirty(SQLiteConnection con, string sql)
        {
            using (var da = new SQLiteDataAdapter(sql, con))
            {
                var dt = new DataTable();
                da.Fill(dt);
                return dt;
            }
        }

        private static async Task PushCustomers(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM AddCustomer WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                try
                {
                    bool ok = await UpsertAsync("zaib_customers", new
                    {
                        sync_id = syncId,
                        local_id = r["id"],
                        name = Convert.ToString(r["Name"]) ?? "",
                        mobile = Convert.ToString(r["Mobile"]) ?? "",
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "AddCustomer", "id", r["id"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_customers", syncId, ex); }
            }
        }

        private static async Task PushDealers(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM AddDealer WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                try
                {
                    bool ok = await UpsertAsync("zaib_dealers", new
                    {
                        sync_id = syncId,
                        local_id = r["Did"],
                        dealer_name = Convert.ToString(r["DealerName"]) ?? "",
                        dd_amount = r["DDAmount"] == DBNull.Value ? 0 : Convert.ToDouble(r["DDAmount"]),
                        d_amount = r["DAmount"] == DBNull.Value ? 0 : Convert.ToDouble(r["DAmount"]),
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "AddDealer", "Did", r["Did"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_dealers", syncId, ex); }
            }
        }

        private static async Task PushPetrol(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM PetrolAdd WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                if (!ParentReady(con, "AddCustomer", "id", r["CustomerId"])) continue;
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                string custSync = GetSyncId(con, "AddCustomer", "id", r["CustomerId"]);
                string customerName = "";
                if (r["CustomerId"] != DBNull.Value)
                {
                    using (var c = new SQLiteCommand("SELECT Name FROM AddCustomer WHERE id=@id", con))
                    {
                        c.Parameters.AddWithValue("@id", r["CustomerId"]);
                        var v = c.ExecuteScalar();
                        customerName = v?.ToString() ?? "";
                    }
                }
                try
                {
                    bool ok = await UpsertAsync("zaib_petrol_entries", new
                    {
                        sync_id = syncId,
                        local_id = r["pid"],
                        customer_sync_id = custSync,
                        customer_name = customerName,
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        receipt_no = Convert.ToString(r["ReceiptNo"]) ?? "",
                        vehicle = Convert.ToString(r["vehicle"]) ?? "",
                        litter = ToD(r["Litter"]),
                        rate = ToD(r["Rate"]),
                        advance = ToD(r["Advance"]),
                        amount = ToD(r["Amount"]),
                        credit = ToD(r["Credit"]),
                        balance = ToD(r["Balance"]),
                        note = Convert.ToString(r["Note"]) ?? "",
                        is_initial_entry = r.Table.Columns.Contains("IsInitialEntry") ? (r["IsInitialEntry"] == DBNull.Value ? 1 : Convert.ToInt32(r["IsInitialEntry"])) : 1,
                        processed = r.Table.Columns.Contains("Processed") ? (r["Processed"] == DBNull.Value ? 0 : Convert.ToInt32(r["Processed"])) : 0,
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "PetrolAdd", "pid", r["pid"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_petrol_entries", syncId, ex); }
            }
        }

        private static async Task PushPayouts(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM DieselLedgerCredit WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                if (!ParentReady(con, "AddDealer", "Did", r["Did"])) continue;
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["Did"]);
                try
                {
                    bool ok = await UpsertAsync("zaib_dealer_payouts", new
                    {
                        sync_id = syncId,
                        local_id = r["LedgerID"],
                        dealer_sync_id = dSync,
                        dealer_name = "",
                        amount_given = ToD(r["AmounGiven"]),
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        note = Convert.ToString(r["Note"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "DieselLedgerCredit", "LedgerID", r["LedgerID"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_dealer_payouts", syncId, ex); }
            }
        }

        private static async Task PushPurchases(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM AddStock WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                if (!ParentReady(con, "AddDealer", "Did", r["DealerId"])) continue;
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["DealerId"]);
                try
                {
                    bool ok = await UpsertAsync("zaib_dealer_purchases", new
                    {
                        sync_id = syncId,
                        local_id = r["Sid"],
                        dealer_sync_id = dSync,
                        dealer_name = "",
                        vehicle = Convert.ToString(r["Vehicle"]) ?? "",
                        rate = ToD(r["Rate"]),
                        add_diesel = ToD(r["AddDisel"]),
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        note = Convert.ToString(r["Note"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "AddStock", "Sid", r["Sid"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_dealer_purchases", syncId, ex); }
            }
        }

        private static async Task PushDirect(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM DieselLedgerDebit WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                if (!ParentReady(con, "AddDealer", "Did", r["Did"])) continue;
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["Did"]);
                try
                {
                    bool ok = await UpsertAsync("zaib_dealer_direct", new
                    {
                        sync_id = syncId,
                        local_id = r["LedgerID"],
                        dealer_sync_id = dSync,
                        dealer_name = "",
                        amount_given = ToD(r["AmounGiven"]),
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        note = Convert.ToString(r["Note"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "DieselLedgerDebit", "LedgerID", r["LedgerID"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_dealer_direct", syncId, ex); }
            }
        }

        private static async Task PushStock(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM StockDiesel WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                if (!ParentReady(con, "AddDealer", "Did", r["SDid"])) continue;
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["SDid"]);
                try
                {
                    bool ok = await UpsertAsync("zaib_stock_diesel", new
                    {
                        sync_id = syncId,
                        local_id = r["SID"],
                        dealer_sync_id = dSync,
                        dealer_name = "",
                        date_text = Convert.ToString(r["Date"]) ?? "",
                        vehicle = Convert.ToString(r["Vehicle"]) ?? "",
                        litter = ToD(r["Litter"]),
                        rate = ToD(r["Rate"]),
                        credit = ToD(r["Credit"]),
                        debit = ToD(r["Debit"]),
                        note = Convert.ToString(r["Note"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "StockDiesel", "SID", r["SID"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_stock_diesel", syncId, ex); }
            }
        }

        private static async Task PushBank(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM BankTransactions WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                if (r["CustomerId"] != DBNull.Value && !ParentReady(con, "AddCustomer", "id", r["CustomerId"])) continue;
                if (r["DealerId"] != DBNull.Value && !ParentReady(con, "AddDealer", "Did", r["DealerId"])) continue;
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                string cSync = GetSyncId(con, "AddCustomer", "id", r["CustomerId"]);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["DealerId"]);
                try
                {
                    bool ok = await UpsertAsync("zaib_bank_transactions", new
                    {
                        sync_id = syncId,
                        local_id = r["Id"],
                        transaction_date = Convert.ToString(r["TransactionDate"]) ?? "",
                        transaction_type = Convert.ToString(r["TransactionType"]) ?? "",
                        customer_sync_id = cSync,
                        customer_name = "",
                        dealer_sync_id = dSync,
                        dealer_name = "",
                        amount = ToD(r["Amount"]),
                        note = Convert.ToString(r["Note"]) ?? "",
                        bank_name = Convert.ToString(r["BankName"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "BankTransactions", "Id", r["Id"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_bank_transactions", syncId, ex); }
            }
        }

        private static async Task PushExpenses(SQLiteConnection con)
        {
            if (!TableExists(con, "Expensetable")) return;
            var dt = QueryDirty(con, "SELECT * FROM Expensetable WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string updatedAt = RowUpdatedAt(r);
                try
                {
                    bool ok = await UpsertAsync("zaib_expenses", new
                    {
                        sync_id = syncId,
                        local_id = r["sid"],
                        name = Convert.ToString(r["Name"]) ?? "",
                        category = Convert.ToString(r["Category"]) ?? "",
                        amount = ToD(r["Amount"]),
                        e_date = Convert.ToString(r["EDate"]) ?? "",
                        note = Convert.ToString(r["Note"]) ?? "",
                        updated_at = updatedAt,
                        deleted_at = (string)null,
                        device_id = _deviceId
                    });
                    if (ok) MarkCleanIfVersion(con, "Expensetable", "sid", r["sid"], syncId, updatedAt);
                }
                catch (Exception ex) { LogFail(con, "push:zaib_expenses", syncId, ex); }
            }
        }

        private static async Task PushTombstones(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM SyncTombstone");
            foreach (DataRow r in dt.Rows)
            {
                string table = Convert.ToString(r["CloudTable"]);
                string syncId = Convert.ToString(r["SyncId"]);
                string deletedAt = Convert.ToString(r["DeletedAt"]);
                try
                {
                    bool ok = await UpsertAsync(table, new
                    {
                        sync_id = syncId,
                        updated_at = deletedAt,
                        deleted_at = deletedAt,
                        device_id = _deviceId
                    });
                    if (ok)
                    {
                        using (var d = new SQLiteCommand("DELETE FROM SyncTombstone WHERE SyncId=@s", con))
                        {
                            d.Parameters.AddWithValue("@s", syncId);
                            d.ExecuteNonQuery();
                        }
                    }
                }
                catch (Exception ex) { LogFail(con, "push:tombstone", syncId, ex); }
            }
        }

        private static double ToD(object v)
        {
            if (v == null || v == DBNull.Value) return 0;
            double.TryParse(Convert.ToString(v), out double d);
            return d;
        }

        private static object LocalIdBySync(SQLiteConnection con, string table, string pk, string syncId)
        {
            if (string.IsNullOrWhiteSpace(syncId)) return DBNull.Value;
            using (var cmd = new SQLiteCommand($"SELECT {pk} FROM {table} WHERE SyncId=@s LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                var v = cmd.ExecuteScalar();
                return v ?? (object)DBNull.Value;
            }
        }

        private static bool HasTombstone(SQLiteConnection con, string syncId)
        {
            using (var cmd = new SQLiteCommand("SELECT 1 FROM SyncTombstone WHERE SyncId=@s LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                return cmd.ExecuteScalar() != null;
            }
        }

        private static bool ShouldApply(SQLiteConnection con, string table, string syncId, string remoteUpdated, bool remoteDeleted, string remoteDeviceId)
        {
            if (HasTombstone(con, syncId))
            {
                // Keep local tombstone until push ack; never resurrect from stale live row.
                return remoteDeleted;
            }
            using (var cmd = new SQLiteCommand($"SELECT UpdatedAt, SyncDirty FROM {table} WHERE SyncId=@s LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) return true;
                    int dirty = r["SyncDirty"] == DBNull.Value ? 0 : Convert.ToInt32(r["SyncDirty"]);
                    if (dirty == 1) return false; // protect pending edits
                    DateTime local = DateTime.TryParse(Convert.ToString(r["UpdatedAt"]), out var lt) ? lt.ToUniversalTime() : DateTime.MinValue;
                    DateTime remote = DateTime.TryParse(remoteUpdated, out var rt) ? rt.ToUniversalTime() : DateTime.MinValue;
                    int cmp = remote.CompareTo(local);
                    if (cmp > 0) return true;
                    if (cmp < 0) return false;
                    if (remoteDeleted) return true;
                    string ld = _deviceId ?? "";
                    string rd = remoteDeviceId ?? "";
                    return string.CompareOrdinal(rd, ld) >= 0;
                }
            }
        }

        /// <summary>
        /// Remote soft-delete apply: local row delete must NOT leave SyncTombstone
        /// (delete triggers would re-push and create sync loops).
        /// Protects SyncDirty rows and local tombstones until upload ack.
        /// </summary>
        private static void ApplyRemoteDelete(SQLiteConnection con, string table, string syncId)
        {
            if (string.IsNullOrWhiteSpace(syncId)) return;
            if (HasTombstone(con, syncId)) return;
            using (var chk = new SQLiteCommand($"SELECT SyncDirty FROM {table} WHERE SyncId=@s LIMIT 1", con))
            {
                chk.Parameters.AddWithValue("@s", syncId);
                var v = chk.ExecuteScalar();
                if (v != null && v != DBNull.Value && Convert.ToInt32(v) == 1) return;
            }
            using (var d = new SQLiteCommand($"DELETE FROM {table} WHERE SyncId=@s", con))
            {
                d.Parameters.AddWithValue("@s", syncId);
                d.ExecuteNonQuery();
            }
            using (var t = new SQLiteCommand("DELETE FROM SyncTombstone WHERE SyncId=@s", con))
            {
                t.Parameters.AddWithValue("@s", syncId);
                t.ExecuteNonQuery();
            }
        }

        private static bool DealerHasPendingChildren(SQLiteConnection con, object did)
        {
            if (did == null || did == DBNull.Value) return false;
            string[] sqls =
            {
                "SELECT 1 FROM DieselLedgerCredit WHERE Did=@id AND IFNULL(SyncDirty,1)=1 LIMIT 1",
                "SELECT 1 FROM DieselLedgerDebit WHERE Did=@id AND IFNULL(SyncDirty,1)=1 LIMIT 1",
                "SELECT 1 FROM AddStock WHERE DealerId=@id AND IFNULL(SyncDirty,1)=1 LIMIT 1",
                "SELECT 1 FROM StockDiesel WHERE SDid=@id AND IFNULL(SyncDirty,1)=1 LIMIT 1"
            };
            foreach (var sql in sqls)
            {
                using (var cmd = new SQLiteCommand(sql, con))
                {
                    cmd.Parameters.AddWithValue("@id", did);
                    if (cmd.ExecuteScalar() != null) return true;
                }
            }
            return false;
        }

        private static async Task PullCustomers(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_customers");
            foreach (var r in await SelectSincePagedAsync("zaib_customers"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "AddCustomer", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_customers", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "AddCustomer", syncId);
                    AdvanceCheckpoint("zaib_customers", updated, ref appliedMax);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT id FROM AddCustomer WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    if (exists == null)
                    {
                        using (var i = new SQLiteCommand("INSERT INTO AddCustomer(Name,Mobile,Date,SyncId,UpdatedAt,SyncDirty) VALUES(@n,@m,@d,@s,@u,0)", con))
                        {
                            i.Parameters.AddWithValue("@n", r.Value<string>("name") ?? "");
                            i.Parameters.AddWithValue("@m", r.Value<string>("mobile") ?? "");
                            i.Parameters.AddWithValue("@d", r.Value<string>("date_text") ?? "");
                            i.Parameters.AddWithValue("@s", syncId);
                            i.Parameters.AddWithValue("@u", updated);
                            i.ExecuteNonQuery();
                        }
                    }
                    else
                    {
                        using (var u = new SQLiteCommand("UPDATE AddCustomer SET Name=@n, Mobile=@m, Date=@d, UpdatedAt=@u, SyncDirty=0 WHERE SyncId=@s", con))
                        {
                            u.Parameters.AddWithValue("@n", r.Value<string>("name") ?? "");
                            u.Parameters.AddWithValue("@m", r.Value<string>("mobile") ?? "");
                            u.Parameters.AddWithValue("@d", r.Value<string>("date_text") ?? "");
                            u.Parameters.AddWithValue("@u", updated);
                            u.Parameters.AddWithValue("@s", syncId);
                            u.ExecuteNonQuery();
                        }
                    }
                }
                AdvanceCheckpoint("zaib_customers", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_customers", appliedMax);
        }

        private static async Task PullDealers(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_dealers");
            foreach (var r in await SelectSincePagedAsync("zaib_dealers"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "AddDealer", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_dealers", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "AddDealer", syncId);
                    AdvanceCheckpoint("zaib_dealers", updated, ref appliedMax);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT Did FROM AddDealer WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    bool skipBalances = exists != null && DealerHasPendingChildren(con, exists);
                    if (exists == null)
                    {
                        using (var i = new SQLiteCommand("INSERT INTO AddDealer(DealerName,DDAmount,DAmount,Date,SyncId,UpdatedAt,SyncDirty) VALUES(@n,@dd,@d,@dt,@s,@u,0)", con))
                        {
                            i.Parameters.AddWithValue("@n", r.Value<string>("dealer_name") ?? "");
                            i.Parameters.AddWithValue("@dd", r.Value<double?>("dd_amount") ?? 0);
                            i.Parameters.AddWithValue("@d", r.Value<double?>("d_amount") ?? 0);
                            i.Parameters.AddWithValue("@dt", r.Value<string>("date_text") ?? "");
                            i.Parameters.AddWithValue("@s", syncId);
                            i.Parameters.AddWithValue("@u", updated);
                            i.ExecuteNonQuery();
                        }
                    }
                    else if (skipBalances)
                    {
                        using (var u = new SQLiteCommand("UPDATE AddDealer SET DealerName=@n, Date=@dt, UpdatedAt=@u, SyncDirty=0 WHERE SyncId=@s", con))
                        {
                            u.Parameters.AddWithValue("@n", r.Value<string>("dealer_name") ?? "");
                            u.Parameters.AddWithValue("@dt", r.Value<string>("date_text") ?? "");
                            u.Parameters.AddWithValue("@u", updated);
                            u.Parameters.AddWithValue("@s", syncId);
                            u.ExecuteNonQuery();
                        }
                    }
                    else
                    {
                        using (var u = new SQLiteCommand("UPDATE AddDealer SET DealerName=@n, DDAmount=@dd, DAmount=@d, Date=@dt, UpdatedAt=@u, SyncDirty=0 WHERE SyncId=@s", con))
                        {
                            u.Parameters.AddWithValue("@n", r.Value<string>("dealer_name") ?? "");
                            u.Parameters.AddWithValue("@dd", r.Value<double?>("dd_amount") ?? 0);
                            u.Parameters.AddWithValue("@d", r.Value<double?>("d_amount") ?? 0);
                            u.Parameters.AddWithValue("@dt", r.Value<string>("date_text") ?? "");
                            u.Parameters.AddWithValue("@u", updated);
                            u.Parameters.AddWithValue("@s", syncId);
                            u.ExecuteNonQuery();
                        }
                    }
                }
                AdvanceCheckpoint("zaib_dealers", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_dealers", appliedMax);
        }

        private static async Task PullPetrol(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_petrol_entries");
            foreach (var r in await SelectSincePagedAsync("zaib_petrol_entries"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "PetrolAdd", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_petrol_entries", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "PetrolAdd", syncId);
                    AdvanceCheckpoint("zaib_petrol_entries", updated, ref appliedMax);
                    continue;
                }
                string custSync = r.Value<string>("customer_sync_id");
                object custId = LocalIdBySync(con, "AddCustomer", "id", custSync);
                if (!string.IsNullOrWhiteSpace(custSync) && (custId == null || custId == DBNull.Value))
                {
                    StageRemote(con, "zaib_petrol_entries", r);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT pid FROM PetrolAdd WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    string sql = exists == null
                        ? "INSERT INTO PetrolAdd(Date,ReceiptNo,vehicle,Litter,Rate,Advance,Amount,Credit,Balance,Note,CustomerId,Processed,IsInitialEntry,SyncId,UpdatedAt,SyncDirty) VALUES(@Date,@ReceiptNo,@vehicle,@Litter,@Rate,@Advance,@Amount,@Credit,@Balance,@Note,@CustomerId,@Processed,@IsInitialEntry,@s,@u,0)"
                        : "UPDATE PetrolAdd SET Date=@Date,ReceiptNo=@ReceiptNo,vehicle=@vehicle,Litter=@Litter,Rate=@Rate,Advance=@Advance,Amount=@Amount,Credit=@Credit,Balance=@Balance,Note=@Note,CustomerId=@CustomerId,Processed=@Processed,IsInitialEntry=@IsInitialEntry,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                    using (var cmd = new SQLiteCommand(sql, con))
                    {
                        cmd.Parameters.AddWithValue("@Date", r.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@ReceiptNo", r.Value<string>("receipt_no") ?? "");
                        cmd.Parameters.AddWithValue("@vehicle", r.Value<string>("vehicle") ?? "");
                        cmd.Parameters.AddWithValue("@Litter", r.Value<double?>("litter") ?? 0);
                        cmd.Parameters.AddWithValue("@Rate", r.Value<double?>("rate") ?? 0);
                        cmd.Parameters.AddWithValue("@Advance", r.Value<double?>("advance") ?? 0);
                        cmd.Parameters.AddWithValue("@Amount", r.Value<double?>("amount") ?? 0);
                        cmd.Parameters.AddWithValue("@Credit", r.Value<double?>("credit") ?? 0);
                        cmd.Parameters.AddWithValue("@Balance", r.Value<double?>("balance") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", r.Value<string>("note") ?? "");
                        cmd.Parameters.AddWithValue("@CustomerId", custId);
                        cmd.Parameters.AddWithValue("@Processed", r.Value<int?>("processed") ?? 0);
                        cmd.Parameters.AddWithValue("@IsInitialEntry", r.Value<int?>("is_initial_entry") ?? 1);
                        cmd.Parameters.AddWithValue("@s", syncId);
                        cmd.Parameters.AddWithValue("@u", updated);
                        cmd.ExecuteNonQuery();
                    }
                }
                AdvanceCheckpoint("zaib_petrol_entries", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_petrol_entries", appliedMax);
        }

        private static async Task PullPayouts(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_dealer_payouts");
            foreach (var r in await SelectSincePagedAsync("zaib_dealer_payouts"))
            {
                bool applied = await UpsertChild(con, "DieselLedgerCredit", "LedgerID", "zaib_dealer_payouts", r,
                    (cmd, row, did) =>
                    {
                        cmd.Parameters.AddWithValue("@Did", did);
                        cmd.Parameters.AddWithValue("@Date", row.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@AmounGiven", row.Value<double?>("amount_given") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", row.Value<string>("note") ?? "");
                    },
                    "Did,Date,AmounGiven,Note",
                    "AddDealer", "Did", "dealer_sync_id");
                if (applied)
                    AdvanceCheckpoint("zaib_dealer_payouts", r.Value<string>("updated_at"), ref appliedMax);
            }
            SetCheckpoint("zaib_dealer_payouts", appliedMax);
        }

        private static async Task PullPurchases(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_dealer_purchases");
            foreach (var r in await SelectSincePagedAsync("zaib_dealer_purchases"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "AddStock", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_dealer_purchases", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "AddStock", syncId);
                    AdvanceCheckpoint("zaib_dealer_purchases", updated, ref appliedMax);
                    continue;
                }
                string dSync = r.Value<string>("dealer_sync_id");
                object did = LocalIdBySync(con, "AddDealer", "Did", dSync);
                if (!string.IsNullOrWhiteSpace(dSync) && (did == null || did == DBNull.Value))
                {
                    StageRemote(con, "zaib_dealer_purchases", r);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT Sid FROM AddStock WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    string sql = exists == null
                        ? "INSERT INTO AddStock(Vehicle,Rate,SellDisel,Stock,Date,AddDisel,DealerId,Note,SyncId,UpdatedAt,SyncDirty) VALUES(@Vehicle,@Rate,0,0,@Date,@AddDisel,@DealerId,@Note,@s,@u,0)"
                        : "UPDATE AddStock SET Vehicle=@Vehicle,Rate=@Rate,Date=@Date,AddDisel=@AddDisel,DealerId=@DealerId,Note=@Note,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                    using (var cmd = new SQLiteCommand(sql, con))
                    {
                        cmd.Parameters.AddWithValue("@Vehicle", r.Value<string>("vehicle") ?? "");
                        cmd.Parameters.AddWithValue("@Rate", r.Value<double?>("rate") ?? 0);
                        cmd.Parameters.AddWithValue("@Date", r.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@AddDisel", r.Value<double?>("add_diesel") ?? 0);
                        cmd.Parameters.AddWithValue("@DealerId", did);
                        cmd.Parameters.AddWithValue("@Note", r.Value<string>("note") ?? "");
                        cmd.Parameters.AddWithValue("@s", syncId);
                        cmd.Parameters.AddWithValue("@u", updated);
                        cmd.ExecuteNonQuery();
                    }
                }
                AdvanceCheckpoint("zaib_dealer_purchases", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_dealer_purchases", appliedMax);
        }

        private static async Task PullDirect(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_dealer_direct");
            foreach (var r in await SelectSincePagedAsync("zaib_dealer_direct"))
            {
                bool applied = await UpsertChild(con, "DieselLedgerDebit", "LedgerID", "zaib_dealer_direct", r,
                    (cmd, row, did) =>
                    {
                        cmd.Parameters.AddWithValue("@Did", did);
                        cmd.Parameters.AddWithValue("@Date", row.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@AmounGiven", row.Value<double?>("amount_given") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", row.Value<string>("note") ?? "");
                    },
                    "Did,Date,AmounGiven,Note",
                    "AddDealer", "Did", "dealer_sync_id");
                if (applied)
                    AdvanceCheckpoint("zaib_dealer_direct", r.Value<string>("updated_at"), ref appliedMax);
            }
            SetCheckpoint("zaib_dealer_direct", appliedMax);
        }

        private static async Task PullStock(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_stock_diesel");
            foreach (var r in await SelectSincePagedAsync("zaib_stock_diesel"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "StockDiesel", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_stock_diesel", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "StockDiesel", syncId);
                    AdvanceCheckpoint("zaib_stock_diesel", updated, ref appliedMax);
                    continue;
                }
                string dSync = r.Value<string>("dealer_sync_id");
                object did = LocalIdBySync(con, "AddDealer", "Did", dSync);
                if (!string.IsNullOrWhiteSpace(dSync) && (did == null || did == DBNull.Value))
                {
                    StageRemote(con, "zaib_stock_diesel", r);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT SID FROM StockDiesel WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    string sql = exists == null
                        ? "INSERT INTO StockDiesel(SDid,Date,Vehicle,Litter,Rate,Credit,Debit,Note,SyncId,UpdatedAt,SyncDirty) VALUES(@SDid,@Date,@Vehicle,@Litter,@Rate,@Credit,@Debit,@Note,@s,@u,0)"
                        : "UPDATE StockDiesel SET SDid=@SDid,Date=@Date,Vehicle=@Vehicle,Litter=@Litter,Rate=@Rate,Credit=@Credit,Debit=@Debit,Note=@Note,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                    using (var cmd = new SQLiteCommand(sql, con))
                    {
                        cmd.Parameters.AddWithValue("@SDid", did);
                        cmd.Parameters.AddWithValue("@Date", r.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@Vehicle", r.Value<string>("vehicle") ?? "");
                        cmd.Parameters.AddWithValue("@Litter", r.Value<double?>("litter") ?? 0);
                        cmd.Parameters.AddWithValue("@Rate", r.Value<double?>("rate") ?? 0);
                        cmd.Parameters.AddWithValue("@Credit", r.Value<double?>("credit") ?? 0);
                        cmd.Parameters.AddWithValue("@Debit", r.Value<double?>("debit") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", r.Value<string>("note") ?? "");
                        cmd.Parameters.AddWithValue("@s", syncId);
                        cmd.Parameters.AddWithValue("@u", updated);
                        cmd.ExecuteNonQuery();
                    }
                }
                AdvanceCheckpoint("zaib_stock_diesel", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_stock_diesel", appliedMax);
        }

        private static async Task PullBank(SQLiteConnection con)
        {
            string appliedMax = GetCheckpoint("zaib_bank_transactions");
            foreach (var r in await SelectSincePagedAsync("zaib_bank_transactions"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "BankTransactions", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_bank_transactions", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "BankTransactions", syncId);
                    AdvanceCheckpoint("zaib_bank_transactions", updated, ref appliedMax);
                    continue;
                }
                string cSync = r.Value<string>("customer_sync_id");
                string dSync = r.Value<string>("dealer_sync_id");
                object cid = LocalIdBySync(con, "AddCustomer", "id", cSync);
                object did = LocalIdBySync(con, "AddDealer", "Did", dSync);
                if ((!string.IsNullOrWhiteSpace(cSync) && (cid == null || cid == DBNull.Value)) ||
                    (!string.IsNullOrWhiteSpace(dSync) && (did == null || did == DBNull.Value)))
                {
                    StageRemote(con, "zaib_bank_transactions", r);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT Id FROM BankTransactions WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    string sql = exists == null
                        ? "INSERT INTO BankTransactions(TransactionDate,TransactionType,CustomerId,DealerId,Amount,Note,BankName,SyncId,UpdatedAt,SyncDirty) VALUES(@TransactionDate,@TransactionType,@CustomerId,@DealerId,@Amount,@Note,@BankName,@s,@u,0)"
                        : "UPDATE BankTransactions SET TransactionDate=@TransactionDate,TransactionType=@TransactionType,CustomerId=@CustomerId,DealerId=@DealerId,Amount=@Amount,Note=@Note,BankName=@BankName,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                    using (var cmd = new SQLiteCommand(sql, con))
                    {
                        cmd.Parameters.AddWithValue("@TransactionDate", r.Value<string>("transaction_date") ?? "");
                        cmd.Parameters.AddWithValue("@TransactionType", r.Value<string>("transaction_type") ?? "");
                        cmd.Parameters.AddWithValue("@CustomerId", cid);
                        cmd.Parameters.AddWithValue("@DealerId", did);
                        cmd.Parameters.AddWithValue("@Amount", r.Value<double?>("amount") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", r.Value<string>("note") ?? "");
                        cmd.Parameters.AddWithValue("@BankName", r.Value<string>("bank_name") ?? "");
                        cmd.Parameters.AddWithValue("@s", syncId);
                        cmd.Parameters.AddWithValue("@u", updated);
                        cmd.ExecuteNonQuery();
                    }
                }
                AdvanceCheckpoint("zaib_bank_transactions", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_bank_transactions", appliedMax);
        }

        private static async Task PullExpenses(SQLiteConnection con)
        {
            if (!TableExists(con, "Expensetable")) return;
            string appliedMax = GetCheckpoint("zaib_expenses");
            foreach (var r in await SelectSincePagedAsync("zaib_expenses"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
                if (!ShouldApply(con, "Expensetable", syncId, updated, deleted, r.Value<string>("device_id")))
                {
                    AdvanceCheckpoint("zaib_expenses", updated, ref appliedMax);
                    continue;
                }
                if (deleted)
                {
                    ApplyRemoteDelete(con, "Expensetable", syncId);
                    AdvanceCheckpoint("zaib_expenses", updated, ref appliedMax);
                    continue;
                }
                using (var chk = new SQLiteCommand("SELECT sid FROM Expensetable WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
                    string sql = exists == null
                        ? "INSERT INTO Expensetable(Name,Category,Amount,EDate,Note,SyncId,UpdatedAt,SyncDirty) VALUES(@Name,@Category,@Amount,@EDate,@Note,@s,@u,0)"
                        : "UPDATE Expensetable SET Name=@Name,Category=@Category,Amount=@Amount,EDate=@EDate,Note=@Note,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                    using (var cmd = new SQLiteCommand(sql, con))
                    {
                        cmd.Parameters.AddWithValue("@Name", r.Value<string>("name") ?? "");
                        cmd.Parameters.AddWithValue("@Category", r.Value<string>("category") ?? "");
                        cmd.Parameters.AddWithValue("@Amount", r.Value<double?>("amount") ?? 0);
                        cmd.Parameters.AddWithValue("@EDate", r.Value<string>("e_date") ?? "");
                        cmd.Parameters.AddWithValue("@Note", r.Value<string>("note") ?? "");
                        cmd.Parameters.AddWithValue("@s", syncId);
                        cmd.Parameters.AddWithValue("@u", updated);
                        cmd.ExecuteNonQuery();
                    }
                }
                AdvanceCheckpoint("zaib_expenses", updated, ref appliedMax);
            }
            SetCheckpoint("zaib_expenses", appliedMax);
        }

        private static async Task FlushStaged(SQLiteConnection con)
        {
            if (!TableExists(con, "SyncStagedRemote")) return;
            var dt = QueryDirty(con, "SELECT * FROM SyncStagedRemote ORDER BY UpdatedAt ASC");
            foreach (DataRow row in dt.Rows)
            {
                string cloud = Convert.ToString(row["CloudTable"]);
                string syncId = Convert.ToString(row["SyncId"]);
                try
                {
                    var payload = JObject.Parse(Convert.ToString(row["PayloadJson"]) ?? "{}");
                    bool applied = false;
                    if (cloud == "zaib_petrol_entries")
                    {
                        // Re-run petrol pull logic for one row via Upsert path
                        string updated = payload.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                        bool deleted = payload["deleted_at"] != null && payload["deleted_at"].Type != JTokenType.Null;
                        if (ShouldApply(con, "PetrolAdd", syncId, updated, deleted, payload.Value<string>("device_id")))
                        {
                            if (deleted) { ApplyRemoteDelete(con, "PetrolAdd", syncId); applied = true; }
                            else
                            {
                                string custSync = payload.Value<string>("customer_sync_id");
                                object custId = LocalIdBySync(con, "AddCustomer", "id", custSync);
                                if (string.IsNullOrWhiteSpace(custSync) || (custId != null && custId != DBNull.Value))
                                {
                                    using (var chk = new SQLiteCommand("SELECT pid FROM PetrolAdd WHERE SyncId=@s", con))
                                    {
                                        chk.Parameters.AddWithValue("@s", syncId);
                                        var exists = chk.ExecuteScalar();
                                        string sql = exists == null
                                            ? "INSERT INTO PetrolAdd(Date,ReceiptNo,vehicle,Litter,Rate,Advance,Amount,Credit,Balance,Note,CustomerId,Processed,IsInitialEntry,SyncId,UpdatedAt,SyncDirty) VALUES(@Date,@ReceiptNo,@vehicle,@Litter,@Rate,@Advance,@Amount,@Credit,@Balance,@Note,@CustomerId,@Processed,@IsInitialEntry,@s,@u,0)"
                                            : "UPDATE PetrolAdd SET Date=@Date,ReceiptNo=@ReceiptNo,vehicle=@vehicle,Litter=@Litter,Rate=@Rate,Advance=@Advance,Amount=@Amount,Credit=@Credit,Balance=@Balance,Note=@Note,CustomerId=@CustomerId,Processed=@Processed,IsInitialEntry=@IsInitialEntry,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                                        using (var cmd = new SQLiteCommand(sql, con))
                                        {
                                            cmd.Parameters.AddWithValue("@Date", payload.Value<string>("date_text") ?? "");
                                            cmd.Parameters.AddWithValue("@ReceiptNo", payload.Value<string>("receipt_no") ?? "");
                                            cmd.Parameters.AddWithValue("@vehicle", payload.Value<string>("vehicle") ?? "");
                                            cmd.Parameters.AddWithValue("@Litter", payload.Value<double?>("litter") ?? 0);
                                            cmd.Parameters.AddWithValue("@Rate", payload.Value<double?>("rate") ?? 0);
                                            cmd.Parameters.AddWithValue("@Advance", payload.Value<double?>("advance") ?? 0);
                                            cmd.Parameters.AddWithValue("@Amount", payload.Value<double?>("amount") ?? 0);
                                            cmd.Parameters.AddWithValue("@Credit", payload.Value<double?>("credit") ?? 0);
                                            cmd.Parameters.AddWithValue("@Balance", payload.Value<double?>("balance") ?? 0);
                                            cmd.Parameters.AddWithValue("@Note", payload.Value<string>("note") ?? "");
                                            cmd.Parameters.AddWithValue("@CustomerId", custId ?? (object)DBNull.Value);
                                            cmd.Parameters.AddWithValue("@Processed", payload.Value<int?>("processed") ?? 0);
                                            cmd.Parameters.AddWithValue("@IsInitialEntry", payload.Value<int?>("is_initial_entry") ?? 1);
                                            cmd.Parameters.AddWithValue("@s", syncId);
                                            cmd.Parameters.AddWithValue("@u", updated);
                                            cmd.ExecuteNonQuery();
                                        }
                                    }
                                    applied = true;
                                }
                            }
                        }
                        else applied = true;
                    }
                    else if (cloud == "zaib_dealer_payouts")
                    {
                        applied = await UpsertChild(con, "DieselLedgerCredit", "LedgerID", cloud, payload,
                            (cmd, row2, did) =>
                            {
                                cmd.Parameters.AddWithValue("@Did", did);
                                cmd.Parameters.AddWithValue("@Date", row2.Value<string>("date_text") ?? "");
                                cmd.Parameters.AddWithValue("@AmounGiven", row2.Value<double?>("amount_given") ?? 0);
                                cmd.Parameters.AddWithValue("@Note", row2.Value<string>("note") ?? "");
                            },
                            "Did,Date,AmounGiven,Note", "AddDealer", "Did", "dealer_sync_id");
                    }
                    else if (cloud == "zaib_dealer_direct")
                    {
                        applied = await UpsertChild(con, "DieselLedgerDebit", "LedgerID", cloud, payload,
                            (cmd, row2, did) =>
                            {
                                cmd.Parameters.AddWithValue("@Did", did);
                                cmd.Parameters.AddWithValue("@Date", row2.Value<string>("date_text") ?? "");
                                cmd.Parameters.AddWithValue("@AmounGiven", row2.Value<double?>("amount_given") ?? 0);
                                cmd.Parameters.AddWithValue("@Note", row2.Value<string>("note") ?? "");
                            },
                            "Did,Date,AmounGiven,Note", "AddDealer", "Did", "dealer_sync_id");
                    }
                    else
                    {
                        applied = true;
                    }
                    if (applied)
                    {
                        using (var d = new SQLiteCommand("DELETE FROM SyncStagedRemote WHERE CloudTable=@t AND SyncId=@s", con))
                        {
                            d.Parameters.AddWithValue("@t", cloud);
                            d.Parameters.AddWithValue("@s", syncId);
                            d.ExecuteNonQuery();
                        }
                    }
                }
                catch (Exception ex) { LogFail(con, "flush:" + cloud, syncId, ex); }
            }
        }

        private static Task<bool> UpsertChild(
            SQLiteConnection con,
            string localTable,
            string pk,
            string cloudTable,
            JToken r,
            Action<SQLiteCommand, JToken, object> bind,
            string insertCols,
            string parentTable,
            string parentPk,
            string parentSyncField)
        {
            string syncId = r.Value<string>("sync_id");
            if (string.IsNullOrWhiteSpace(syncId)) return Task.FromResult(true);
            string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
            bool deleted = r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null;
            if (!ShouldApply(con, localTable, syncId, updated, deleted, r.Value<string>("device_id")))
                return Task.FromResult(true);
            if (deleted)
            {
                ApplyRemoteDelete(con, localTable, syncId);
                return Task.FromResult(true);
            }
            string parentSync = r.Value<string>(parentSyncField);
            object parentId = LocalIdBySync(con, parentTable, parentPk, parentSync);
            if (!string.IsNullOrWhiteSpace(parentSync) && (parentId == null || parentId == DBNull.Value))
            {
                if (r is JObject jo) StageRemote(con, cloudTable, jo);
                return Task.FromResult(false);
            }
            using (var chk = new SQLiteCommand($"SELECT {pk} FROM {localTable} WHERE SyncId=@s", con))
            {
                chk.Parameters.AddWithValue("@s", syncId);
                var exists = chk.ExecuteScalar();
                string sql = exists == null
                    ? $"INSERT INTO {localTable}({insertCols},SyncId,UpdatedAt,SyncDirty) VALUES(@Did,@Date,@AmounGiven,@Note,@s,@u,0)"
                    : $"UPDATE {localTable} SET Did=@Did,Date=@Date,AmounGiven=@AmounGiven,Note=@Note,UpdatedAt=@u,SyncDirty=0 WHERE SyncId=@s";
                using (var cmd = new SQLiteCommand(sql, con))
                {
                    bind(cmd, r, parentId);
                    cmd.Parameters.AddWithValue("@s", syncId);
                    cmd.Parameters.AddWithValue("@u", updated);
                    cmd.ExecuteNonQuery();
                }
            }
            return Task.FromResult(true);
        }
    }
}

