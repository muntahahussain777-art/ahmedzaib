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
    /// Silent Mobile↔PC sync via Supabase schema zaibservice.
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
        private static string _deviceId;
        private static string _lastPull = "1970-01-01T00:00:00.000Z";

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
                _lastPull = jo.Value<string>("lastPull") ?? _lastPull;
            }
            catch { }
            if (string.IsNullOrWhiteSpace(_deviceId))
                _deviceId = Guid.NewGuid().ToString();
        }

        private static void SaveState()
        {
            try
            {
                var jo = new JObject
                {
                    ["deviceId"] = _deviceId,
                    ["lastPull"] = _lastPull
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
            string sql = $@"
CREATE TRIGGER IF NOT EXISTS {name}
AFTER {evt}{ofCols} ON {table}
BEGIN
  UPDATE {table}
  SET SyncDirty = 1,
      UpdatedAt = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
      SyncId = CASE WHEN SyncId IS NULL OR SyncId = '' THEN lower(hex(randomblob(16))) ELSE SyncId END
  WHERE {pk} = {(evt == "INSERT" ? "NEW" : "NEW")}.{pk};
END;";
            Exec(con, sql);
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
            if (Interlocked.Exchange(ref _running, 1) == 1) return;
            try
            {
                EnsureLocalSyncReady();
                using (var con = new SQLiteConnection(projectconnection.ConnectionString))
                {
                    con.Open();
                    await PushCustomers(con);
                    await PushDealers(con);
                    await PushPetrol(con);
                    await PushPayouts(con);
                    await PushPurchases(con);
                    await PushDirect(con);
                    await PushStock(con);
                    await PushBank(con);
                    await PushExpenses(con);
                    await PushTombstones(con);

                    string pullStarted = DateTime.UtcNow.ToString("o");
                    await PullCustomers(con);
                    await PullDealers(con);
                    await PullPetrol(con);
                    await PullPayouts(con);
                    await PullPurchases(con);
                    await PullDirect(con);
                    await PullStock(con);
                    await PullBank(con);
                    await PullExpenses(con);
                    _lastPull = pullStarted;
                    SaveState();
                }
            }
            catch
            {
                // silent offline
            }
            finally
            {
                Interlocked.Exchange(ref _running, 0);
            }
        }

        private static async Task UpsertAsync(string table, object row)
        {
            string json = JsonConvert.SerializeObject(row);
            var req = new HttpRequestMessage(HttpMethod.Post, $"{Url}/rest/v1/{table}?on_conflict=sync_id")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            req.Headers.Add("Prefer", "resolution=merge-duplicates,return=minimal");
            var res = await Http.SendAsync(req);
            res.EnsureSuccessStatusCode();
        }

        private static async Task<JArray> SelectSinceAsync(string table)
        {
            string url = $"{Url}/rest/v1/{table}?select=*&updated_at=gt.{Uri.EscapeDataString(_lastPull)}&order=updated_at.asc";
            var res = await Http.GetAsync(url);
            res.EnsureSuccessStatusCode();
            string body = await res.Content.ReadAsStringAsync();
            return JArray.Parse(string.IsNullOrWhiteSpace(body) ? "[]" : body);
        }

        private static void MarkClean(SQLiteConnection con, string table, string pk, object id, string syncId)
        {
            using (var cmd = new SQLiteCommand($"UPDATE {table} SET SyncDirty=0, SyncId=@s WHERE {pk}=@id", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                cmd.Parameters.AddWithValue("@id", id);
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
                await UpsertAsync("zaib_customers", new
                {
                    sync_id = syncId,
                    local_id = r["id"],
                    name = Convert.ToString(r["Name"]) ?? "",
                    mobile = Convert.ToString(r["Mobile"]) ?? "",
                    date_text = Convert.ToString(r["Date"]) ?? "",
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "AddCustomer", "id", r["id"], syncId);
            }
        }

        private static async Task PushDealers(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM AddDealer WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                await UpsertAsync("zaib_dealers", new
                {
                    sync_id = syncId,
                    local_id = r["Did"],
                    dealer_name = Convert.ToString(r["DealerName"]) ?? "",
                    dd_amount = r["DDAmount"] == DBNull.Value ? 0 : Convert.ToDouble(r["DDAmount"]),
                    d_amount = r["DAmount"] == DBNull.Value ? 0 : Convert.ToDouble(r["DAmount"]),
                    date_text = Convert.ToString(r["Date"]) ?? "",
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "AddDealer", "Did", r["Did"], syncId);
            }
        }

        private static async Task PushPetrol(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM PetrolAdd WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
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
                await UpsertAsync("zaib_petrol_entries", new
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
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "PetrolAdd", "pid", r["pid"], syncId);
            }
        }

        private static async Task PushPayouts(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM DieselLedgerCredit WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["Did"]);
                await UpsertAsync("zaib_dealer_payouts", new
                {
                    sync_id = syncId,
                    local_id = r["LedgerID"],
                    dealer_sync_id = dSync,
                    dealer_name = "",
                    amount_given = ToD(r["AmounGiven"]),
                    date_text = Convert.ToString(r["Date"]) ?? "",
                    note = Convert.ToString(r["Note"]) ?? "",
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "DieselLedgerCredit", "LedgerID", r["LedgerID"], syncId);
            }
        }

        private static async Task PushPurchases(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM AddStock WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["DealerId"]);
                await UpsertAsync("zaib_dealer_purchases", new
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
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "AddStock", "Sid", r["Sid"], syncId);
            }
        }

        private static async Task PushDirect(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM DieselLedgerDebit WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["Did"]);
                await UpsertAsync("zaib_dealer_direct", new
                {
                    sync_id = syncId,
                    local_id = r["LedgerID"],
                    dealer_sync_id = dSync,
                    dealer_name = "",
                    amount_given = ToD(r["AmounGiven"]),
                    date_text = Convert.ToString(r["Date"]) ?? "",
                    note = Convert.ToString(r["Note"]) ?? "",
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "DieselLedgerDebit", "LedgerID", r["LedgerID"], syncId);
            }
        }

        private static async Task PushStock(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM StockDiesel WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["SDid"]);
                await UpsertAsync("zaib_stock_diesel", new
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
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "StockDiesel", "SID", r["SID"], syncId);
            }
        }

        private static async Task PushBank(SQLiteConnection con)
        {
            var dt = QueryDirty(con, "SELECT * FROM BankTransactions WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                string cSync = GetSyncId(con, "AddCustomer", "id", r["CustomerId"]);
                string dSync = GetSyncId(con, "AddDealer", "Did", r["DealerId"]);
                await UpsertAsync("zaib_bank_transactions", new
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
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "BankTransactions", "Id", r["Id"], syncId);
            }
        }

        private static async Task PushExpenses(SQLiteConnection con)
        {
            if (!TableExists(con, "Expensetable")) return;
            var dt = QueryDirty(con, "SELECT * FROM Expensetable WHERE IFNULL(SyncDirty,1)=1");
            foreach (DataRow r in dt.Rows)
            {
                string syncId = string.IsNullOrWhiteSpace(Convert.ToString(r["SyncId"])) ? Guid.NewGuid().ToString() : Convert.ToString(r["SyncId"]);
                await UpsertAsync("zaib_expenses", new
                {
                    sync_id = syncId,
                    local_id = r["sid"],
                    name = Convert.ToString(r["Name"]) ?? "",
                    category = Convert.ToString(r["Category"]) ?? "",
                    amount = ToD(r["Amount"]),
                    e_date = Convert.ToString(r["EDate"]) ?? "",
                    note = Convert.ToString(r["Note"]) ?? "",
                    updated_at = string.IsNullOrWhiteSpace(Convert.ToString(r["UpdatedAt"])) ? DateTime.UtcNow.ToString("o") : Convert.ToString(r["UpdatedAt"]),
                    deleted_at = (string)null,
                    device_id = _deviceId
                });
                MarkClean(con, "Expensetable", "sid", r["sid"], syncId);
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
                    await UpsertAsync(table, new
                    {
                        sync_id = syncId,
                        updated_at = deletedAt,
                        deleted_at = deletedAt,
                        device_id = _deviceId
                    });
                    using (var d = new SQLiteCommand("DELETE FROM SyncTombstone WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                }
                catch { }
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

        private static bool ShouldApply(SQLiteConnection con, string table, string syncId, string remoteUpdated)
        {
            using (var cmd = new SQLiteCommand($"SELECT UpdatedAt, SyncDirty FROM {table} WHERE SyncId=@s LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@s", syncId);
                using (var r = cmd.ExecuteReader())
                {
                    if (!r.Read()) return true;
                    int dirty = r["SyncDirty"] == DBNull.Value ? 0 : Convert.ToInt32(r["SyncDirty"]);
                    DateTime local = DateTime.TryParse(Convert.ToString(r["UpdatedAt"]), out var lt) ? lt.ToUniversalTime() : DateTime.MinValue;
                    DateTime remote = DateTime.TryParse(remoteUpdated, out var rt) ? rt.ToUniversalTime() : DateTime.MinValue;
                    if (dirty == 1) return remote > local;
                    return remote >= local;
                }
            }
        }

        private static async Task PullCustomers(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_customers"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM AddCustomer WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "AddCustomer", syncId, updated)) continue;
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
            }
        }

        private static async Task PullDealers(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_dealers"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM AddDealer WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "AddDealer", syncId, updated)) continue;
                using (var chk = new SQLiteCommand("SELECT Did FROM AddDealer WHERE SyncId=@s", con))
                {
                    chk.Parameters.AddWithValue("@s", syncId);
                    var exists = chk.ExecuteScalar();
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
            }
        }

        private static async Task PullPetrol(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_petrol_entries"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM PetrolAdd WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "PetrolAdd", syncId, updated)) continue;
                object custId = LocalIdBySync(con, "AddCustomer", "id", r.Value<string>("customer_sync_id"));
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
            }
        }

        private static async Task PullPayouts(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_dealer_payouts"))
            {
                await UpsertChild(con, "DieselLedgerCredit", "LedgerID", "zaib_dealer_payouts", r,
                    (cmd, row, did) =>
                    {
                        cmd.Parameters.AddWithValue("@Did", did);
                        cmd.Parameters.AddWithValue("@Date", row.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@AmounGiven", row.Value<double?>("amount_given") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", row.Value<string>("note") ?? "");
                    },
                    "Did,Date,AmounGiven,Note",
                    "AddDealer", "Did", "dealer_sync_id");
            }
        }

        private static async Task PullPurchases(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_dealer_purchases"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM AddStock WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "AddStock", syncId, updated)) continue;
                object did = LocalIdBySync(con, "AddDealer", "Did", r.Value<string>("dealer_sync_id"));
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
            }
        }

        private static async Task PullDirect(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_dealer_direct"))
            {
                await UpsertChild(con, "DieselLedgerDebit", "LedgerID", "zaib_dealer_direct", r,
                    (cmd, row, did) =>
                    {
                        cmd.Parameters.AddWithValue("@Did", did);
                        cmd.Parameters.AddWithValue("@Date", row.Value<string>("date_text") ?? "");
                        cmd.Parameters.AddWithValue("@AmounGiven", row.Value<double?>("amount_given") ?? 0);
                        cmd.Parameters.AddWithValue("@Note", row.Value<string>("note") ?? "");
                    },
                    "Did,Date,AmounGiven,Note",
                    "AddDealer", "Did", "dealer_sync_id");
            }
        }

        private static async Task PullStock(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_stock_diesel"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM StockDiesel WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "StockDiesel", syncId, updated)) continue;
                object did = LocalIdBySync(con, "AddDealer", "Did", r.Value<string>("dealer_sync_id"));
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
            }
        }

        private static async Task PullBank(SQLiteConnection con)
        {
            foreach (var r in await SelectSinceAsync("zaib_bank_transactions"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM BankTransactions WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "BankTransactions", syncId, updated)) continue;
                object cid = LocalIdBySync(con, "AddCustomer", "id", r.Value<string>("customer_sync_id"));
                object did = LocalIdBySync(con, "AddDealer", "Did", r.Value<string>("dealer_sync_id"));
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
            }
        }

        private static async Task PullExpenses(SQLiteConnection con)
        {
            if (!TableExists(con, "Expensetable")) return;
            foreach (var r in await SelectSinceAsync("zaib_expenses"))
            {
                string syncId = r.Value<string>("sync_id");
                if (string.IsNullOrWhiteSpace(syncId)) continue;
                string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
                if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
                {
                    using (var d = new SQLiteCommand("DELETE FROM Expensetable WHERE SyncId=@s", con))
                    {
                        d.Parameters.AddWithValue("@s", syncId);
                        d.ExecuteNonQuery();
                    }
                    continue;
                }
                if (!ShouldApply(con, "Expensetable", syncId, updated)) continue;
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
            }
        }

        private static Task UpsertChild(
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
            if (string.IsNullOrWhiteSpace(syncId)) return Task.CompletedTask;
            string updated = r.Value<string>("updated_at") ?? DateTime.UtcNow.ToString("o");
            if (r["deleted_at"] != null && r["deleted_at"].Type != JTokenType.Null)
            {
                using (var d = new SQLiteCommand($"DELETE FROM {localTable} WHERE SyncId=@s", con))
                {
                    d.Parameters.AddWithValue("@s", syncId);
                    d.ExecuteNonQuery();
                }
                return Task.CompletedTask;
            }
            if (!ShouldApply(con, localTable, syncId, updated)) return Task.CompletedTask;
            object parentId = LocalIdBySync(con, parentTable, parentPk, r.Value<string>(parentSyncField));
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
            return Task.CompletedTask;
        }
    }
}
