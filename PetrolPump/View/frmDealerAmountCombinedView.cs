using ZaibPetroleumService.Model;
using ZaibPetroleumService.ProjectConnection;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Data.SQLite;
using System.Drawing;
using System.Windows.Forms;

namespace ZaibPetroleumService.View
{
    /// <summary>
    /// VIP Dealer Ledger: Payout + Direct + DealerAmount (AddStock litter×rate) + running balance.
    /// Add/edit/delete still use the existing save forms. No sync/pull changes.
    /// </summary>
    public partial class frmDealerAmountCombinedView : SampleView
    {
        public frmDealerAmountCombinedView()
        {
            InitializeComponent();
        }

        private void frmDealerAmountCombinedView_Load(object sender, EventArgs e)
        {
            this.Text = "Dealer Ledger";
            if (label1 != null)
                label1.Text = "Dealer Ledger";
            dtpStart.Value = DateTime.Now;
            dtpEnd.Value = DateTime.Now;
            LoadData();
        }

        public override void btnAdd_Click(object sender, EventArgs e)
        {
            using (var pick = new Form())
            {
                pick.Text = "Add Dealer Entry";
                pick.StartPosition = FormStartPosition.CenterParent;
                pick.FormBorderStyle = FormBorderStyle.FixedDialog;
                pick.MaximizeBox = false;
                pick.MinimizeBox = false;
                pick.ClientSize = new Size(520, 130);
                pick.BackColor = Color.FromArgb(32, 36, 66);

                var lbl = new Label
                {
                    Text = "Kaun si entry?",
                    ForeColor = Color.White,
                    Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold),
                    Location = new Point(20, 16),
                    AutoSize = true
                };
                var btnPayout = new Button
                {
                    Text = "Dealer Payout",
                    Size = new Size(150, 42),
                    Location = new Point(20, 55),
                    DialogResult = DialogResult.Yes
                };
                var btnDirect = new Button
                {
                    Text = "Direct Amount",
                    Size = new Size(150, 42),
                    Location = new Point(186, 55),
                    DialogResult = DialogResult.No
                };
                var btnStock = new Button
                {
                    Text = "Dealer Amount",
                    Size = new Size(150, 42),
                    Location = new Point(352, 55),
                    DialogResult = DialogResult.Retry
                };
                pick.Controls.Add(lbl);
                pick.Controls.Add(btnPayout);
                pick.Controls.Add(btnDirect);
                pick.Controls.Add(btnStock);
                pick.AcceptButton = btnPayout;

                DialogResult choice = pick.ShowDialog(this);
                if (choice == DialogResult.Yes)
                {
                    var frm = new frmDieselLedgerDealerAdd();
                    if (frm.ShowDialog() == DialogResult.OK)
                        LoadData();
                }
                else if (choice == DialogResult.No)
                {
                    var frm = new FrmDirectDealerPaymentAmountAdd();
                    if (frm.ShowDialog() == DialogResult.OK)
                        LoadData();
                }
                else if (choice == DialogResult.Retry)
                {
                    var frm = new frmStockAdd();
                    frm.ShowDialog();
                    LoadData();
                }
            }
        }

        private void dtpStart_ValueChanged(object sender, EventArgs e)
        {
            LoadData();
        }

        private void dtpEnd_ValueChanged(object sender, EventArgs e)
        {
            LoadData();
        }

        private void txtSearch_TextChanged(object sender, EventArgs e)
        {
            LoadData();
        }

        public override void txtSearch_TextChanged_1(object sender, EventArgs e) { }

        private void LoadData()
        {
            string searchText = (txtSearch.Text ?? string.Empty).Trim();
            DateTime startDate = dtpStart.Value.Date;
            DateTime endDate = dtpEnd.Value.Date;
            if (endDate < startDate)
            {
                DateTime tmp = startDate;
                startDate = endDate;
                endDate = tmp;
            }

            DataTable dt = FetchLedger(searchText, startDate, endDate);
            BindGrid(dt);
            UpdateSummary(dt);
        }

        private static DataTable FetchLedger(string searchText, DateTime startDate, DateTime endDate)
        {
            const string unionCore = @"
SELECT * FROM (
  SELECT
    DL.LedgerID AS LedgerID,
    DL.Did AS Did,
    DA.DealerName AS DealerName,
    DL.Date AS Date,
    'Payout' AS Kind,
    IFNULL(DL.AmounGiven, 0) AS Payout,
    0 AS Direct,
    0 AS StockAmt,
    0 AS Litter,
    0 AS Rate,
    IFNULL(DL.Note, '') AS Note
  FROM DieselLedgerCredit DL
  LEFT JOIN AddDealer DA ON DL.Did = DA.Did
  UNION ALL
  SELECT
    DL.LedgerID AS LedgerID,
    DL.Did AS Did,
    DA.DealerName AS DealerName,
    DL.Date AS Date,
    'Direct' AS Kind,
    0 AS Payout,
    IFNULL(DL.AmounGiven, 0) AS Direct,
    0 AS StockAmt,
    0 AS Litter,
    0 AS Rate,
    IFNULL(DL.Note, '') AS Note
  FROM DieselLedgerDebit DL
  LEFT JOIN AddDealer DA ON DL.Did = DA.Did
  UNION ALL
  SELECT
    S.Sid AS LedgerID,
    S.DealerId AS Did,
    DA.DealerName AS DealerName,
    S.Date AS Date,
    'Dealer Amount' AS Kind,
    0 AS Payout,
    0 AS Direct,
    CAST(IFNULL(S.Rate, 0) * IFNULL(S.AddDisel, 0) AS REAL) AS StockAmt,
    IFNULL(S.AddDisel, 0) AS Litter,
    IFNULL(S.Rate, 0) AS Rate,
    IFNULL(S.Note, '') AS Note
  FROM AddStock S
  LEFT JOIN AddDealer DA ON S.DealerId = DA.Did
) x
WHERE 1=1";

            var dt = new DataTable();
            bool dateWindowOnly = string.IsNullOrEmpty(searchText);
            using (var con = new SQLiteConnection(projectconnection.conReturn()))
            {
                con.Open();
                using (var cmd = new SQLiteCommand { Connection = con })
                {
                    if (dateWindowOnly)
                    {
                        cmd.CommandText = unionCore + @"
  AND date(x.Date) >= date(@StartDate)
  AND date(x.Date) <= date(@EndDate)
ORDER BY IFNULL(x.DealerName,'' ) COLLATE NOCASE, date(x.Date) ASC, CASE x.Kind WHEN 'Dealer Amount' THEN 1 WHEN 'Direct' THEN 2 ELSE 3 END, x.LedgerID ASC";
                        cmd.Parameters.AddWithValue("@StartDate", startDate.ToString("yyyy-MM-dd"));
                        cmd.Parameters.AddWithValue("@EndDate", endDate.ToString("yyyy-MM-dd"));
                    }
                    else
                    {
                        cmd.CommandText = unionCore + @"
  AND (
        IFNULL(x.DealerName, '') LIKE @SearchLike
        OR IFNULL(x.Note, '') LIKE @SearchLike
      )
ORDER BY IFNULL(x.DealerName,'' ) COLLATE NOCASE, date(x.Date) ASC, CASE x.Kind WHEN 'Dealer Amount' THEN 1 WHEN 'Direct' THEN 2 ELSE 3 END, x.LedgerID ASC";
                        cmd.Parameters.AddWithValue("@SearchLike", "%" + searchText + "%");
                    }

                    using (var da = new SQLiteDataAdapter(cmd))
                        da.Fill(dt);
                }
            }

            if (!dt.Columns.Contains("Balance"))
                dt.Columns.Add("Balance", typeof(decimal));
            if (!dt.Columns.Contains("TotalBalance"))
                dt.Columns.Add("TotalBalance", typeof(decimal));

            Dictionary<int, decimal> openings = null;
            if (dateWindowOnly && dt.Rows.Count > 0)
            {
                openings = new Dictionary<int, decimal>();
                foreach (DataRow r in dt.Rows)
                {
                    if (r["Did"] == DBNull.Value) continue;
                    int did = Convert.ToInt32(r["Did"]);
                    if (openings.ContainsKey(did)) continue;
                    openings[did] = GetDealerOpeningBefore(did, startDate);
                }
            }

            ApplyRunningBalances(dt, openings);
            return dt;
        }

        /// <summary>Opening = (Direct + Stock litter×rate) − Payout before start date.</summary>
        private static decimal GetDealerOpeningBefore(int dealerId, DateTime beforeDate)
        {
            string query = @"
SELECT
  IFNULL((SELECT SUM(IFNULL(AmounGiven,0)) FROM DieselLedgerDebit
          WHERE Did=@id AND date(Date) < date(@before)), 0)
+ IFNULL((SELECT SUM(IFNULL(Rate,0)*IFNULL(AddDisel,0)) FROM AddStock
          WHERE DealerId=@id AND date(Date) < date(@before)), 0)
- IFNULL((SELECT SUM(IFNULL(AmounGiven,0)) FROM DieselLedgerCredit
          WHERE Did=@id AND date(Date) < date(@before)), 0)";
            var ht = new Hashtable
            {
                { "@id", dealerId },
                { "@before", beforeDate.ToString("yyyy-MM-dd") }
            };
            DataTable dt = MainClass.ExecuteSelectQuery(query, ht);
            if (dt == null || dt.Rows.Count == 0 || dt.Rows[0][0] == DBNull.Value) return 0m;
            return Convert.ToDecimal(dt.Rows[0][0]);
        }

        private static void ApplyRunningBalances(DataTable dt, Dictionary<int, decimal> openings)
        {
            if (dt == null || dt.Rows.Count == 0) return;

            decimal run = 0m;
            int prevDid = int.MinValue;
            int groupStart = 0;

            for (int i = 0; i <= dt.Rows.Count; i++)
            {
                int did = int.MinValue;
                if (i < dt.Rows.Count && dt.Rows[i]["Did"] != DBNull.Value)
                    did = Convert.ToInt32(dt.Rows[i]["Did"]);

                bool newGroup = i == dt.Rows.Count || (prevDid != int.MinValue && did != prevDid);
                if (newGroup && prevDid != int.MinValue)
                {
                    for (int r = groupStart; r < i; r++)
                        dt.Rows[r]["TotalBalance"] = DBNull.Value;
                    dt.Rows[groupStart]["TotalBalance"] = run;
                    groupStart = i;
                }

                if (i == dt.Rows.Count) break;

                if (did != prevDid)
                {
                    run = 0m;
                    if (openings != null && did != int.MinValue && openings.TryGetValue(did, out decimal open))
                        run = open;
                    prevDid = did;
                }

                decimal payout = ToDec(dt.Rows[i]["Payout"]);
                decimal direct = ToDec(dt.Rows[i]["Direct"]);
                decimal stockAmt = dt.Columns.Contains("StockAmt") ? ToDec(dt.Rows[i]["StockAmt"]) : 0m;
                run += direct;
                run += stockAmt;
                run -= payout;
                dt.Rows[i]["Balance"] = run;
            }
        }

        private static decimal ToDec(object v)
        {
            if (v == null || v == DBNull.Value) return 0m;
            return Convert.ToDecimal(v);
        }

        private void BindGrid(DataTable dt)
        {
            guna2DataGridView1.SuspendLayout();
            try
            {
                guna2DataGridView1.AutoGenerateColumns = false;
                guna2DataGridView1.DataSource = null;

                void Map(string gridCol, string dataCol)
                {
                    if (!guna2DataGridView1.Columns.Contains(gridCol)) return;
                    var col = guna2DataGridView1.Columns[gridCol];
                    col.DataPropertyName = dt.Columns.Contains(dataCol) ? dataCol : string.Empty;
                    col.Visible = gridCol != "dgvid" && gridCol != "dgvDid";
                }

                Map("dgvid", "LedgerID");
                Map("dgvDid", "Did");
                Map("dgvKind", "Kind");
                Map("dgvName", "DealerName");
                Map("dgvDate", "Date");
                Map("dgvLitter", "Litter");
                Map("dgvRate", "Rate");
                Map("dgvStock", "StockAmt");
                Map("dgvPayout", "Payout");
                Map("dgvDirect", "Direct");
                Map("dgvBalance", "Balance");
                Map("dgvTotalBalance", "TotalBalance");
                Map("dgvNote", "Note");

                guna2DataGridView1.DataSource = dt;
                MainClass.SrNo(guna2DataGridView1);
            }
            finally
            {
                guna2DataGridView1.ResumeLayout(true);
            }
        }

        private void UpdateSummary(DataTable dt)
        {
            decimal payout = 0m, direct = 0m, stock = 0m;
            if (dt != null)
            {
                foreach (DataRow r in dt.Rows)
                {
                    payout += ToDec(r["Payout"]);
                    direct += ToDec(r["Direct"]);
                    stock += dt.Columns.Contains("StockAmt") ? ToDec(r["StockAmt"]) : 0m;
                }
            }
            lblPayout.Text = $"Payout: {payout:N2}";
            lblDirect.Text = $"Direct: {direct:N2}   |   Amount: {stock:N2}";
            lblResult.Text = $"Period net (Direct+Amount − Payout): {(direct + stock - payout):N2}   |   Balance = running";
        }

        private void guna2DataGridView1_CellDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            OpenEdit();
        }

        private void OpenEdit()
        {
            if (guna2DataGridView1.CurrentRow == null || guna2DataGridView1.CurrentRow.IsNewRow)
                return;

            string kind = Convert.ToString(guna2DataGridView1.CurrentRow.Cells["dgvKind"].Value) ?? "";
            int id = 0;
            try
            {
                if (guna2DataGridView1.CurrentRow.DataBoundItem is DataRowView drv &&
                    drv.Row.Table.Columns.Contains("LedgerID") && drv["LedgerID"] != DBNull.Value)
                    id = Convert.ToInt32(drv["LedgerID"]);
                else if (guna2DataGridView1.Columns.Contains("dgvid") &&
                         guna2DataGridView1.CurrentRow.Cells["dgvid"].Value != null &&
                         guna2DataGridView1.CurrentRow.Cells["dgvid"].Value != DBNull.Value)
                    id = Convert.ToInt32(guna2DataGridView1.CurrentRow.Cells["dgvid"].Value);
            }
            catch { }

            if (id <= 0) return;

            if (string.Equals(kind, "Direct", StringComparison.OrdinalIgnoreCase))
            {
                var frm = new FrmDirectDealerPaymentAmountAdd(id);
                if (frm.ShowDialog() == DialogResult.OK)
                    LoadData();
            }
            else if (string.Equals(kind, "Dealer Amount", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(kind, "Stock", StringComparison.OrdinalIgnoreCase))
            {
                var frm = new frmStockAdd { id = id };
                frm.ShowDialog();
                LoadData();
            }
            else
            {
                var frm = new frmDieselLedgerDealerAdd(id);
                if (frm.ShowDialog() == DialogResult.OK)
                    LoadData();
            }
        }

        private void guna2DataGridView1_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode != Keys.Delete) return;
            e.Handled = true;
            OpenEdit();
        }

        private void guna2DataGridView1_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
        {
            MainClass.SrNo(guna2DataGridView1);
            if (guna2DataGridView1.Columns[e.ColumnIndex].Name == "dgvBalance" && e.Value != null && e.Value != DBNull.Value)
            {
                try
                {
                    decimal v = Convert.ToDecimal(e.Value);
                    e.CellStyle.ForeColor = v < 0 ? Color.FromArgb(255, 120, 120) : Color.White;
                }
                catch { }
            }
        }
    }
}
