using System;
using System.Collections;
using System.Data;
using System.Data.SQLite;

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

        /// <summary>
        /// Durable tombstone for cloud delete (same schema as sync triggers).
        /// Safe if SyncId empty. Does not notify cloud until next push.
        /// </summary>
        public static void EnsureTombstone(string syncId, string cloudTable, SQLiteConnection connection, SQLiteTransaction tx)
        {
            if (string.IsNullOrWhiteSpace(syncId) || string.IsNullOrWhiteSpace(cloudTable))
                return;
            Exec(
                @"INSERT OR REPLACE INTO SyncTombstone(SyncId, CloudTable, DeletedAt)
                  VALUES(@s, @t, strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
                new Hashtable { { "@s", syncId }, { "@t", cloudTable } },
                connection, tx);
        }
    }
}
