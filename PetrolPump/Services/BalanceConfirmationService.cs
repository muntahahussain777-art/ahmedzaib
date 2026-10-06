using ZaibPetroleumService.Model;
using ZaibPetroleumService.ProjectConnection;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Data.SQLite;
using System.Windows.Forms;

namespace ZaibPetroleumService.Services
{
    /// <summary>
    /// Balance 0 ya negative hone par save se pehle Yes/No confirmation.
    /// Daily Diesel Sales aur Dealer Amount forms excluded (unke save handlers mein call nahi).
    /// Also: VIP opening carry + stored credit Balance repair after IUD.
    /// </summary>
    public static class BalanceConfirmationService
    {
        /// <summary>
        /// VIP sale Amount: Litter×Rate+Advance only when BOTH Litter and Rate &gt; 0; else Amount+Advance.
        /// </summary>
        public static decimal VipSaleAmount(decimal litter, decimal rate, decimal amount, decimal advance)
        {
            if (litter > 0m && rate > 0m)
                return litter * rate + advance;
            return amount + advance;
        }

        /// <summary>Credit column value for VIP (credit rows may store wasooli in Amount).</summary>
        public static decimal VipCreditValue(int isInitialEntry, decimal credit, decimal amount, decimal advance)
        {
            if (isInitialEntry == 0)
                return credit != 0m ? credit : amount + advance;
            return credit;
        }

        /// <summary>
        /// True remaining BEFORE a date (VIP formula). Used as opening when Daily Diesel is date-filtered.
        /// </summary>
        public static decimal GetCustomerOpeningBalanceBefore(int customerId, DateTime beforeDate)
        {
            string query = @"
SELECT IFNULL(SUM(
         CASE
           WHEN IFNULL(IsInitialEntry,1)=0 THEN 0
           WHEN IFNULL(Litter,0)>0 AND IFNULL(Rate,0)>0
             THEN CAST(IFNULL(Litter,0)*IFNULL(Rate,0)+IFNULL(Advance,0) AS REAL)
           ELSE IFNULL(Amount,0)+IFNULL(Advance,0)
         END
       ),0)
     - IFNULL(SUM(
         CASE
           WHEN IFNULL(IsInitialEntry,1)=0 THEN
             CASE WHEN IFNULL(Credit,0)<>0 THEN IFNULL(Credit,0)
                  ELSE IFNULL(Amount,0)+IFNULL(Advance,0) END
           ELSE IFNULL(Credit,0)
         END
       ),0)
FROM PetrolAdd
WHERE CustomerId=@id AND date(Date) < date(@before)";
            var ht = new Hashtable
            {
                { "@id", customerId },
                { "@before", beforeDate.ToString("yyyy-MM-dd") }
            };
            DataTable dt = MainClass.ExecuteSelectQuery(query, ht);
            if (dt == null || dt.Rows.Count == 0 || dt.Rows[0][0] == DBNull.Value) return 0m;
            return Convert.ToDecimal(dt.Rows[0][0]);
        }

        public static decimal GetCustomerPetrolRemaining(int customerId)
        {
            // Full-history remaining with the same VIP Amount/Credit formula as Daily Diesel.
            string query = @"
SELECT IFNULL(SUM(
         CASE
           WHEN IFNULL(IsInitialEntry,1)=0 THEN 0
           WHEN IFNULL(Litter,0)>0 AND IFNULL(Rate,0)>0
             THEN CAST(IFNULL(Litter,0)*IFNULL(Rate,0)+IFNULL(Advance,0) AS REAL)
           ELSE IFNULL(Amount,0)+IFNULL(Advance,0)
         END
       ),0)
     - IFNULL(SUM(
         CASE
           WHEN IFNULL(IsInitialEntry,1)=0 THEN
             CASE WHEN IFNULL(Credit,0)<>0 THEN IFNULL(Credit,0)
                  ELSE IFNULL(Amount,0)+IFNULL(Advance,0) END
           ELSE IFNULL(Credit,0)
         END
       ),0)
FROM PetrolAdd
WHERE CustomerId=@id";
            var ht = new Hashtable { { "@id", customerId } };
            DataTable dt = MainClass.ExecuteSelectQuery(query, ht);
            if (dt == null || dt.Rows.Count == 0 || dt.Rows[0][0] == DBNull.Value) return 0m;
            return Convert.ToDecimal(dt.Rows[0][0]);
        }

        public static decimal GetCustomerLedgerRemaining(int customerId)
        {
            // Prefer true petrol remaining (not stale SUM(Balance) snapshots).
            return GetCustomerPetrolRemaining(customerId);
        }

        /// <summary>
        /// Recompute sale row deltas + credit remaining snapshots for one customer (chronological).
        /// Suppresses SyncDirty triggers so mass repair does not force-upload every row.
        /// </summary>
        public static void RecalculateCustomerPetrolBalances(int customerId)
        {
            if (customerId <= 0) return;
            try
            {
                using (var con = new SQLiteConnection(projectconnection.ConnectionString))
                {
                    con.Open();
                    try { using (var g = new SQLiteCommand("INSERT OR IGNORE INTO SyncApplyGuard(Id) VALUES(1)", con)) g.ExecuteNonQuery(); } catch { }

                    DataTable rows;
                    using (var cmd = new SQLiteCommand(
                        @"SELECT pid, IFNULL(IsInitialEntry,1) AS IsInitialEntry,
                                 IFNULL(Litter,0) AS Litter, IFNULL(Rate,0) AS Rate,
                                 IFNULL(Amount,0) AS Amount, IFNULL(Advance,0) AS Advance,
                                 IFNULL(Credit,0) AS Credit
                          FROM PetrolAdd
                          WHERE CustomerId=@id
                          ORDER BY date(Date) ASC, pid ASC", con))
                    {
                        cmd.Parameters.AddWithValue("@id", customerId);
                        using (var da = new SQLiteDataAdapter(cmd))
                        {
                            rows = new DataTable();
                            da.Fill(rows);
                        }
                    }

                    decimal run = 0m;
                    using (var tx = con.BeginTransaction())
                    {
                        foreach (DataRow r in rows.Rows)
                        {
                            int pid = Convert.ToInt32(r["pid"]);
                            int isInit = Convert.ToInt32(r["IsInitialEntry"]);
                            decimal litter = Convert.ToDecimal(r["Litter"]);
                            decimal rate = Convert.ToDecimal(r["Rate"]);
                            decimal amount = Convert.ToDecimal(r["Amount"]);
                            decimal advance = Convert.ToDecimal(r["Advance"]);
                            decimal credit = Convert.ToDecimal(r["Credit"]);

                            decimal balToStore;
                            if (isInit == 0)
                            {
                                decimal credVal = VipCreditValue(0, credit, amount, advance);
                                run -= credVal;
                                balToStore = run; // remaining after this credit
                            }
                            else
                            {
                                decimal saleAmt = VipSaleAmount(litter, rate, amount, advance);
                                decimal saleCred = credit;
                                run += saleAmt;
                                run -= saleCred;
                                // Sale stored Balance stays per-row delta (Amount−Credit+Advance), matching save form.
                                balToStore = amount - credit + advance;
                            }

                            using (var u = new SQLiteCommand(
                                "UPDATE PetrolAdd SET Balance=@b WHERE pid=@p", con, tx))
                            {
                                u.Parameters.AddWithValue("@b", balToStore.ToString("F2"));
                                u.Parameters.AddWithValue("@p", pid);
                                u.ExecuteNonQuery();
                            }
                        }
                        tx.Commit();
                    }

                    try { using (var g = new SQLiteCommand("DELETE FROM SyncApplyGuard", con)) g.ExecuteNonQuery(); } catch { }
                }
            }
            catch
            {
                try
                {
                    using (var con = new SQLiteConnection(projectconnection.ConnectionString))
                    {
                        con.Open();
                        using (var g = new SQLiteCommand("DELETE FROM SyncApplyGuard", con)) g.ExecuteNonQuery();
                    }
                }
                catch { }
            }
        }

        /// <summary>One-shot repair for every customer that has petrol rows.</summary>
        public static void RecalculateAllCustomerPetrolBalances()
        {
            DataTable ids = MainClass.ExecuteSelectQuery(
                "SELECT DISTINCT CustomerId FROM PetrolAdd WHERE CustomerId IS NOT NULL", null);
            if (ids == null) return;
            foreach (DataRow r in ids.Rows)
            {
                if (r[0] == DBNull.Value) continue;
                RecalculateCustomerPetrolBalances(Convert.ToInt32(r[0]));
            }
        }

        public static decimal GetDealerCreditBalance(int dealerId)
        {
            string query = "SELECT IFNULL(DAmount,0) AS DAmount, IFNULL(DDAmount,0) AS DDAmount FROM AddDealer WHERE Did = @id";
            var ht = new Hashtable { { "@id", dealerId } };
            DataTable dt = MainClass.ExecuteSelectQuery(query, ht);
            if (dt == null || dt.Rows.Count == 0) return 0;
            decimal dAmount = Convert.ToDecimal(dt.Rows[0]["DAmount"]);
            decimal ddAmount = Convert.ToDecimal(dt.Rows[0]["DDAmount"]);
            return ddAmount - dAmount;
        }

        public static decimal GetBankBalance(string bankName, int excludeTransactionId = 0)
        {
            if (string.IsNullOrWhiteSpace(bankName)) return 0;
            string query = excludeTransactionId > 0
                ? "SELECT IFNULL(SUM(CAST(Amount AS REAL)),0) FROM BankTransactions WHERE BankName = @bank AND Id <> @excludeId"
                : "SELECT IFNULL(SUM(CAST(Amount AS REAL)),0) FROM BankTransactions WHERE BankName = @bank";
            var ht = new Hashtable { { "@bank", bankName.Trim() } };
            if (excludeTransactionId > 0)
                ht.Add("@excludeId", excludeTransactionId);
            DataTable dt = MainClass.ExecuteSelectQuery(query, ht);
            if (dt == null || dt.Rows.Count == 0) return 0;
            return Convert.ToDecimal(dt.Rows[0][0]);
        }

        public static decimal NetDeduction(decimal newDeduction, decimal oldDeduction, bool isEditSameEntity)
        {
            if (!isEditSameEntity) return newDeduction;
            return newDeduction - oldDeduction;
        }

        public static bool ConfirmCustomerPetrolCredit(int customerId, decimal creditAmount, string displayName = null)
        {
            if (creditAmount <= 0) return true;
            string name = string.IsNullOrWhiteSpace(displayName) ? "Customer" : displayName.Trim();
            return ConfirmDeduction(name, GetCustomerPetrolRemaining(customerId), creditAmount);
        }

        public static bool ConfirmCustomerLedgerDeduction(int customerId, decimal deduction, string displayName = null)
        {
            if (deduction <= 0) return true;
            string name = string.IsNullOrWhiteSpace(displayName) ? "Customer" : displayName.Trim();
            return ConfirmDeduction(name, GetCustomerLedgerRemaining(customerId), deduction);
        }

        public static bool ConfirmDealerCreditDeduction(int dealerId, decimal deduction, string displayName = null)
        {
            if (deduction <= 0) return true;
            string name = string.IsNullOrWhiteSpace(displayName) ? "Dealer" : displayName.Trim();
            return ConfirmDeduction(name, GetDealerCreditBalance(dealerId), deduction);
        }

        public static bool ConfirmBankOutTransaction(string bankName, decimal storedAmount, int excludeTransactionId = 0)
        {
            if (storedAmount >= 0) return true;

            decimal current = GetBankBalance(bankName, excludeTransactionId);
            decimal projected = current + storedAmount;

            // Sirf jab balance 0 ya negative ho — har Out par nahi
            if (projected > 0) return true;

            string bank = string.IsNullOrWhiteSpace(bankName) ? "Bank" : bankName.Trim();
            string message;

            if (projected == 0)
            {
                message = bank + " ka balance 0 ho jayega.\n" +
                          "(Abhi: " + current.ToString("N2") + " — Out: " + Math.Abs(storedAmount).ToString("N2") + ")\n\n" +
                          "Kya aap phir bhi ye entry karna chahte hain?";
            }
            else
            {
                message = bank + " ka balance negative ho jayega (" + projected.ToString("N2") + ").\n" +
                          "(Abhi: " + current.ToString("N2") + " — Out: " + Math.Abs(storedAmount).ToString("N2") + ")\n\n" +
                          "Kya aap phir bhi ye entry karna chahte hain?";
            }

            using (var yn = new YesOrNoMessage(message, "Confirm Bank Entry"))
                return yn.ShowDialog() == DialogResult.Yes;
        }

        private static bool ConfirmDeduction(string entityLabel, decimal currentBalance, decimal deduction)
        {
            decimal projected = currentBalance - deduction;
            if (projected > 0) return true;

            string message;
            if (projected == 0)
            {
                message = entityLabel + " ka amount 0 ho jayega.\n" +
                          "(Abhi: " + currentBalance.ToString("N2") + " — Entry: " + deduction.ToString("N2") + ")\n\n" +
                          "Kya aap phir bhi entry karna chahte hain?";
            }
            else
            {
                message = entityLabel + " ka record khatam ho chuka hai (balance " + projected.ToString("N2") + " ho jayega).\n\n" +
                          "Kya aap entry phir bhi karna chahte hain?";
            }

            using (var yn = new YesOrNoMessage(message, "Confirm Entry"))
                return yn.ShowDialog() == DialogResult.Yes;
        }
    }
}
