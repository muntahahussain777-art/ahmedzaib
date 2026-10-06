using System;
using System.Collections;
using System.Data;
using System.Data.SQLite;
using System.Security.Cryptography;
using System.Text;

namespace ZaibPetroleumService.Services
{
    /// <summary>
    /// Part 1: local SQLite writes — entry + balance + sync metadata in ONE transaction.
    /// Does not change UI; callers keep existing success/error dialogs.
    /// </summary>
    public static class LocalPersistence
    {
        /// <summary>
        /// Runs work inside a single SQLite transaction. Returns false on failure / rollback.
        /// </summary>
        public static bool RunInTransaction(Func<SQLiteConnection, SQLiteTransaction, bool> work)
        {
            if (work == null) return false;
            try
            {
                using (var connection = new SQLiteConnection(MainClass.con_string))
                {
                    connection.Open();
                    using (SQLiteTransaction tx = connection.BeginTransaction())
                    {
                        try
                        {
                            bool ok = work(connection, tx);
                            if (!ok)
                            {
                                tx.Rollback();
                                return false;
                            }
                            tx.Commit();
                            return true;
                        }
                        catch
                        {
                            try { tx.Rollback(); } catch { /* ignore */ }
                            throw;
                        }
                    }
                }
            }
            catch
            {
                return false;
            }
        }

        public static int Exec(string sql, Hashtable ht, SQLiteConnection connection, SQLiteTransaction tx)
        {
            using (var cmd = new SQLiteCommand(sql, connection, tx))
            {
                if (ht != null)
                {
                    foreach (System.Collections.DictionaryEntry item in ht)
                        cmd.Parameters.AddWithValue(item.Key.ToString(), item.Value ?? DBNull.Value);
                }
                return cmd.ExecuteNonQuery();
            }
        }

        public static object Scalar(string sql, Hashtable ht, SQLiteConnection connection, SQLiteTransaction tx)
        {
            using (var cmd = new SQLiteCommand(sql, connection, tx))
            {
                if (ht != null)
                {
                    foreach (System.Collections.DictionaryEntry item in ht)
                        cmd.Parameters.AddWithValue(item.Key.ToString(), item.Value ?? DBNull.Value);
                }
                return cmd.ExecuteScalar();
            }
        }

        public static DataTable Select(string sql, Hashtable ht, SQLiteConnection connection, SQLiteTransaction tx)
        {
            using (var cmd = new SQLiteCommand(sql, connection, tx))
            {
                if (ht != null)
                {
                    foreach (System.Collections.DictionaryEntry item in ht)
                        cmd.Parameters.AddWithValue(item.Key.ToString(), item.Value ?? DBNull.Value);
                }
                using (var da = new SQLiteDataAdapter(cmd))
                {
                    var dt = new DataTable();
                    da.Fill(dt);
                    return dt;
                }
            }
        }

        /// <summary>
        /// Read authoritative row by PK inside an open transaction.
        /// </summary>
        public static DataRow ReadRow(string table, string pkCol, object pk, SQLiteConnection connection, SQLiteTransaction tx)
        {
            DataTable dt = Select(
                $"SELECT * FROM [{table}] WHERE [{pkCol}] = @id LIMIT 1",
                new Hashtable { { "@id", pk } },
                connection, tx);
            if (dt == null || dt.Rows.Count == 0) return null;
            return dt.Rows[0];
        }

        public static string StableTombstoneRequestId(string cloudTable, string syncId, string deletedAt)
        {
            using (var md5 = MD5.Create())
            {
                byte[] hash = md5.ComputeHash(Encoding.UTF8.GetBytes(
                    (cloudTable ?? "") + "|" + (syncId ?? "") + "|" + (deletedAt ?? "") + "|del"));
                return new Guid(hash).ToString();
            }
        }

        /// <summary>
        /// Durable tombstone for cloud delete. Captures ExpectedServerRev + stable RequestId
        /// in the same transaction as the local delete (OCC base for upload).
        /// </summary>
        public static void EnsureTombstone(
            string syncId,
            string cloudTable,
            SQLiteConnection connection,
            SQLiteTransaction tx,
            long? expectedServerRev = null)
        {
            if (string.IsNullOrWhiteSpace(syncId) || string.IsNullOrWhiteSpace(cloudTable))
                return;
            string deletedAt = DateTime.UtcNow.ToString("o");
            string requestId = StableTombstoneRequestId(cloudTable, syncId, deletedAt);
            Exec(
                @"INSERT OR REPLACE INTO SyncTombstone(SyncId, CloudTable, DeletedAt, ExpectedServerRev, RequestId)
                  VALUES(@s, @t, @d, @r, @req)",
                new Hashtable
                {
                    { "@s", syncId },
                    { "@t", cloudTable },
                    { "@d", deletedAt },
                    { "@r", expectedServerRev.HasValue && expectedServerRev.Value > 0
                        ? (object)expectedServerRev.Value : DBNull.Value },
                    { "@req", requestId }
                },
                connection, tx);
        }

        private static long? ReadServerRevFromRow(DataRow row)
        {
            if (row == null || !row.Table.Columns.Contains("ServerRev") || row["ServerRev"] == DBNull.Value)
                return null;
            try
            {
                long v = Convert.ToInt64(row["ServerRev"]);
                return v > 0 ? (long?)v : null;
            }
            catch { return null; }
        }

        /// <summary>
        /// Delete one local row and record SyncTombstone so pull cannot resurrect it.
        /// Reads SyncId + ServerRev BEFORE delete in the same transaction.
        /// Returns rows deleted (0 or 1).
        /// </summary>
        public static int DeleteByPkWithTombstone(string table, string pkCol, object pk, string cloudTable)
        {
            int deleted = 0;
            bool ok = RunInTransaction((conn, tx) =>
            {
                DataRow row = ReadRow(table, pkCol, pk, conn, tx);
                if (row == null) return false;
                string syncId = null;
                if (row.Table.Columns.Contains("SyncId") && row["SyncId"] != DBNull.Value)
                    syncId = Convert.ToString(row["SyncId"]);
                long? expectedRev = ReadServerRevFromRow(row);
                EnsureTombstone(syncId, cloudTable, conn, tx, expectedRev);
                deleted = Exec(
                    $"DELETE FROM [{table}] WHERE [{pkCol}] = @id",
                    new Hashtable { { "@id", pk } },
                    conn, tx);
                return deleted > 0;
            });
            return ok ? deleted : 0;
        }

        /// <summary>
        /// Delete matching rows and tombstone each SyncId (bulk / side-effect deletes).
        /// whereSql is the predicate only (no WHERE keyword), e.g. "pid = @pid".
        /// Preserves each row's ServerRev as ExpectedServerRev.
        /// </summary>
        public static int DeleteMatchingWithTombstones(string table, string whereSql, Hashtable ht, string cloudTable)
        {
            int deleted = 0;
            bool ok = RunInTransaction((conn, tx) =>
            {
                DataTable rows = Select(
                    $"SELECT * FROM [{table}] WHERE {whereSql}",
                    ht, conn, tx);
                if (rows != null)
                {
                    foreach (DataRow r in rows.Rows)
                    {
                        if (!r.Table.Columns.Contains("SyncId") || r["SyncId"] == DBNull.Value) continue;
                        string syncId = Convert.ToString(r["SyncId"]);
                        long? expectedRev = ReadServerRevFromRow(r);
                        EnsureTombstone(syncId, cloudTable, conn, tx, expectedRev);
                    }
                }
                deleted = Exec($"DELETE FROM [{table}] WHERE {whereSql}", ht, conn, tx);
                return true;
            });
            return ok ? deleted : -1;
        }
    }
}
