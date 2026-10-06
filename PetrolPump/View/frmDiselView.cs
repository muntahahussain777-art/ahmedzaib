using ZaibPetroleumService.Model;
using ZaibPetroleumService.ProjectConnection;
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SQLite;
using System.Data.SqlClient;
using System.Drawing;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using static System.ComponentModel.Design.ObjectSelectorEditor;

namespace ZaibPetroleumService.View
{
    public partial class frmDiselView : SampleView
    {
        private readonly Timer _searchDebounceTimer = new Timer();
        private int _loadToken;
        private static bool _dbIndexEnsured;
        private static bool _petrolBalanceRepaired;

        public frmDiselView()
        {
            InitializeComponent();
            this.KeyPreview = true;  // Enable form to capture key events

        }

     


        private void frmDiselView_Load(object sender, EventArgs e)
        {
            EnableGridDoubleBuffering();
            EnsureQueryIndex();

            comboBox1.Visible = true;
            btnAverage.Visible = true;
            dtpStart.Value = DateTime.Now;
            dtpEnd.Value = DateTime.Now;

            comboBox1.Items.Clear();
            comboBox1.Items.Add("Rate");
            comboBox1.SelectedIndex = 0;

            _searchDebounceTimer.Interval = 400;
            _searchDebounceTimer.Tick += (s, ev) =>
            {
                _searchDebounceTimer.Stop();
                LoadData1();
            };

            dtpStart.ValueChanged += DatePickers_ValueChanged;
            dtpEnd.ValueChanged += DatePickers_ValueChanged;

            if (!guna2DataGridView1.Columns.Contains("dgvTotalBalance"))
            {
                DataGridViewTextBoxColumn totalBalanceColumn = new DataGridViewTextBoxColumn();
                totalBalanceColumn.Name = "dgvTotalBalance";
                totalBalanceColumn.HeaderText = "Total Balance";
                guna2DataGridView1.Columns.Add(totalBalanceColumn);
            }

            guna2DataGridView1.KeyDown += new KeyEventHandler(guna2DataGridView1_KeyDown);

            // Form turant dikhe — data background mein aaye (aaj ki date filter)
            LoadData1();
        }

        private static void EnsureQueryIndex()
        {
            if (_dbIndexEnsured) return;
            try
            {
                using (var con = new SQLiteConnection(projectconnection.conReturn()))
                {
                    con.Open();
                    using (var cmd1 = new SQLiteCommand(
                        "CREATE INDEX IF NOT EXISTS idx_PetrolAdd_Date_Initial ON PetrolAdd(Date, IsInitialEntry)", con))
                        cmd1.ExecuteNonQuery();
                    using (var cmd2 = new SQLiteCommand(
                        "CREATE INDEX IF NOT EXISTS idx_PetrolAdd_CustomerId ON PetrolAdd(CustomerId)", con))
                        cmd2.ExecuteNonQuery();
                }
                _dbIndexEnsured = true;
                // One-shot: repair stale credit Balance snapshots so Credit Adjust / DB match VIP.
                if (!_petrolBalanceRepaired)
                {
                    _petrolBalanceRepaired = true;
                    try { Services.BalanceConfirmationService.RecalculateAllCustomerPetrolBalances(); }
                    catch { }
                }
            }
            catch { /* index optional — load still works */ }
        }

        private void EnableGridDoubleBuffering()
        {
            typeof(DataGridView).InvokeMember("DoubleBuffered",
                BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.SetProperty,
                null, guna2DataGridView1, new object[] { true });
        }

        private void btnAverage_Click(object sender, EventArgs e)
        {
            // Calculate Average based on the selected ComboBox option (Rate)
            if (comboBox1.Visible && comboBox1.SelectedItem != null)
            {
                string selectedOption = comboBox1.SelectedItem.ToString();
                if (selectedOption == "Rate")
                {
                    CalculateAverage("Rate");
                }
                else
                {
                    CustomeMessage noDataMessage = new CustomeMessage("Please select a valid option!", "Info");
                    noDataMessage.ShowDialog();
                }
            }
        }

 
      
        private void frmCreditAdjust_KeyDown(object sender, KeyEventArgs e)
        {
            // Check if the Ctrl key is pressed along with R
            if (e.Control && e.KeyCode == Keys.R)
            {
                // Call the method to reload the form
                LoadData1();
                CustomeMessage noDataMessage = new CustomeMessage("Form reloaded successfully!", "Info");
                noDataMessage.ShowDialog();
            }
        }

        public override void btnAdd_Click(object sender, EventArgs e)
        {
            frmDiselAdd frm = new frmDiselAdd();
            frm.ShowDialog();
            LoadData1();
        }

        private void LoadData1()
        {
            int token = ++_loadToken;
            string searchText = txtSearch.Text ?? string.Empty;
            DateTime startDate = dtpStart.Value.Date;
            DateTime endDate = dtpEnd.Value.Date;
            if (endDate < startDate)
            {
                DateTime tmp = startDate;
                startDate = endDate;
                endDate = tmp;
            }

            Task.Run(() => FetchPetrolData(searchText, startDate, endDate))
                .ContinueWith(t =>
                {
                    if (token != _loadToken || IsDisposed) return;
                    if (t.IsFaulted)
                    {
                        MessageBox.Show(t.Exception?.GetBaseException().Message ?? "Load failed.", "Error",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return;
                    }
                    BindPetrolGrid(t.Result);
                }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private static DataTable FetchPetrolData(string searchText, DateTime startDate, DateTime endDate)
        {
            searchText = (searchText ?? string.Empty).Trim();
            // Sale + Credit dono. Credit entry (IsInitialEntry=0): Credit column mein wasooli.
            // Running Balance = true customer cumulative through this row (full history), same VIP formula.
            // Works for date filter, search, vehicle filter — never starts from 0 mid-ledger.
            const string vipRunningBalanceSql = @"
(SELECT IFNULL(SUM(
           CASE
             WHEN IFNULL(p2.IsInitialEntry, 1) = 0 THEN 0
             WHEN IFNULL(p2.Litter, 0) > 0 AND IFNULL(p2.Rate, 0) > 0
               THEN CAST(IFNULL(p2.Litter, 0) AS REAL) * CAST(IFNULL(p2.Rate, 0) AS REAL) + IFNULL(p2.Advance, 0)
             ELSE IFNULL(p2.Amount, 0) + IFNULL(p2.Advance, 0)
           END
         ), 0)
       - IFNULL(SUM(
           CASE
             WHEN IFNULL(p2.IsInitialEntry, 1) = 0 THEN
               CASE
                 WHEN IFNULL(p2.Credit, 0) <> 0 THEN IFNULL(p2.Credit, 0)
                 ELSE IFNULL(p2.Amount, 0) + IFNULL(p2.Advance, 0)
               END
             ELSE IFNULL(p2.Credit, 0)
           END
         ), 0)
 FROM PetrolAdd p2
 WHERE p2.CustomerId = PetrolAdd.CustomerId
   AND (
         date(p2.Date) < date(PetrolAdd.Date)
         OR (date(p2.Date) = date(PetrolAdd.Date) AND p2.pid <= PetrolAdd.pid)
       ))";

            // Sale Amount: Litter×Rate+Adv only when BOTH Litter & Rate > 0; else Amount+Adv.
            const string selectCore = @"
SELECT PetrolAdd.pid,
       PetrolAdd.CustomerId,
       PetrolAdd.Date,
       PetrolAdd.ReceiptNo,
       PetrolAdd.vehicle,
       IFNULL(PetrolAdd.Litter, 0) AS Litter,
       IFNULL(PetrolAdd.Rate, 0) AS Rate,
       IFNULL(PetrolAdd.Advance, 0) AS Advance,
       CASE
           WHEN IFNULL(PetrolAdd.IsInitialEntry, 1) = 0 THEN 0
           WHEN IFNULL(PetrolAdd.Litter, 0) > 0 AND IFNULL(PetrolAdd.Rate, 0) > 0
               THEN CAST(IFNULL(PetrolAdd.Litter, 0) * IFNULL(PetrolAdd.Rate, 0) + IFNULL(PetrolAdd.Advance, 0) AS DECIMAL(18, 3))
           ELSE IFNULL(PetrolAdd.Amount, 0) + IFNULL(PetrolAdd.Advance, 0)
       END AS Amount,
       CASE
           WHEN IFNULL(PetrolAdd.IsInitialEntry, 1) = 0 THEN
               CASE
                   WHEN IFNULL(PetrolAdd.Credit, 0) <> 0 THEN IFNULL(PetrolAdd.Credit, 0)
                   ELSE IFNULL(PetrolAdd.Amount, 0) + IFNULL(PetrolAdd.Advance, 0)
               END
           ELSE IFNULL(PetrolAdd.Credit, 0)
       END AS CreditVal,
       CAST(" + vipRunningBalanceSql + @" AS DECIMAL(18, 3)) AS Balance,
       CAST(NULL AS REAL) AS TotalBalance,
       CASE
           WHEN IFNULL(PetrolAdd.IsInitialEntry, 1) = 0 AND IFNULL(TRIM(PetrolAdd.Note), '') = ''
               THEN 'Credit Customer'
           ELSE IFNULL(PetrolAdd.Note, '')
       END AS Note,
       AddCustomer.Name,
       IFNULL(PetrolAdd.IsInitialEntry, 1) AS IsInitialEntry
FROM PetrolAdd
INNER JOIN AddCustomer ON PetrolAdd.CustomerId = AddCustomer.id
WHERE 1=1";

            var dt = new DataTable();
            using (var con = new SQLiteConnection(projectconnection.conReturn()))
            {
                con.Open();
                string qry;
                var cmd = new SQLiteCommand { Connection = con };

                if (string.IsNullOrEmpty(searchText))
                {
                    // Bina search: date range (Balance still full running through each row)
                    qry = selectCore + @"
  AND date(PetrolAdd.Date) >= date(@StartDate)
  AND date(PetrolAdd.Date) <= date(@EndDate)
ORDER BY AddCustomer.Name COLLATE NOCASE, PetrolAdd.Date ASC, PetrolAdd.pid ASC";
                    cmd.CommandText = qry;
                    cmd.Parameters.AddWithValue("@StartDate", startDate.ToString("yyyy-MM-dd"));
                    cmd.Parameters.AddWithValue("@EndDate", endDate.ToString("yyyy-MM-dd"));
                }
                else
                {
                    // Search active: poori history — date filter nahi; naam sirf exact match (amount mix nahi)
                    string searchLike = "%" + searchText + "%";
                    int? exactCustomerId = TryGetExactCustomerId(con, searchText);

                    if (exactCustomerId.HasValue)
                    {
                        qry = selectCore + @"
  AND PetrolAdd.CustomerId = @CustomerId
ORDER BY PetrolAdd.Date ASC, PetrolAdd.pid ASC";
                        cmd.CommandText = qry;
                        cmd.Parameters.AddWithValue("@CustomerId", exactCustomerId.Value);
                    }
                    else
                    {
                        // Customer name exact nahi — vehicle / receipt / note
                        qry = selectCore + @"
  AND (
        IFNULL(PetrolAdd.vehicle, '') LIKE @SearchLike
        OR CAST(IFNULL(PetrolAdd.ReceiptNo, '') AS TEXT) LIKE @SearchLike
        OR IFNULL(PetrolAdd.Note, '') LIKE @SearchLike
      )
ORDER BY AddCustomer.Name COLLATE NOCASE, PetrolAdd.Date ASC, PetrolAdd.pid ASC";
                        cmd.CommandText = qry;
                        cmd.Parameters.AddWithValue("@SearchLike", searchLike);
                    }
                }

                using (cmd)
                using (var da = new SQLiteDataAdapter(cmd))
                    da.Fill(dt);
            }

            ApplyCustomerGroupTotalBalance(dt);
            return dt;
        }

        /// <summary>
        /// TotalBalance on first row of each customer = that customer's last running Balance in this grid.
        /// </summary>
        private static void ApplyCustomerGroupTotalBalance(DataTable dt)
        {
            if (dt == null || dt.Rows.Count == 0 || !dt.Columns.Contains("Balance")) return;

            int groupStart = 0;
            int prevCid = int.MinValue;
            for (int i = 0; i <= dt.Rows.Count; i++)
            {
                int cid = int.MinValue;
                if (i < dt.Rows.Count && dt.Rows[i]["CustomerId"] != DBNull.Value)
                    cid = Convert.ToInt32(dt.Rows[i]["CustomerId"]);

                if (i == dt.Rows.Count || (prevCid != int.MinValue && cid != prevCid))
                {
                    int groupEnd = i - 1;
                    if (groupEnd >= groupStart)
                    {
                        decimal lastBal = ToDec(dt.Rows[groupEnd]["Balance"]);
                        for (int r = groupStart; r <= groupEnd; r++)
                            dt.Rows[r]["TotalBalance"] = DBNull.Value;
                        dt.Rows[groupStart]["TotalBalance"] = lastBal;
                    }
                    groupStart = i;
                }
                prevCid = cid;
            }
        }

        private static decimal ToDec(object v)
        {
            if (v == null || v == DBNull.Value) return 0m;
            return Convert.ToDecimal(v);
        }

        private static int? TryGetExactCustomerId(SQLiteConnection con, string name)
        {
            using (var cmd = new SQLiteCommand(
                "SELECT id FROM AddCustomer WHERE TRIM(Name) = @Name COLLATE NOCASE LIMIT 1", con))
            {
                cmd.Parameters.AddWithValue("@Name", name.Trim());
                object result = cmd.ExecuteScalar();
                if (result == null || result == DBNull.Value) return null;
                return Convert.ToInt32(result);
            }
        }

        private static List<int> GetCustomerIdsByNameLike(SQLiteConnection con, string searchLike)
        {
            // Deprecated path — exact name match only (similar names mix nahi honge)
            var ids = new List<int>();
            string exactName = (searchLike ?? "").Trim().Trim('%');
            if (string.IsNullOrEmpty(exactName))
                return ids;

            int? id = TryGetExactCustomerId(con, exactName);
            if (id.HasValue)
                ids.Add(id.Value);
            return ids;
        }

        private void BindPetrolGrid(DataTable dt)
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
                    col.Visible = true;
                }

                Map("dgvid", "pid");
                Map("dgvDate", "Date");
                Map("dgvreciptno", "ReceiptNo");
                Map("dgvVechleNo", "vehicle");
                Map("dgvLitter", "Litter");
                Map("dgvrate", "Rate");
                Map("dgvAdvance", "Advance");
                Map("dgvAmount", "Amount");
                Map("dgvCredit", "CreditVal");
                Map("dgvBalance", "Balance");
                Map("dgvTotalBalance", "TotalBalance");
                Map("dgvNote", "Note");
                Map("dgvName", "Name");

                if (guna2DataGridView1.Columns.Contains("dgvCredit"))
                {
                    // Binding alias — designer pe DataPropertyName na hone se pehle 0 dikhta tha
                    guna2DataGridView1.Columns["dgvCredit"].DataPropertyName =
                        dt.Columns.Contains("CreditVal") ? "CreditVal" : "Credit";
                    guna2DataGridView1.Columns["dgvCredit"].MinimumWidth = 90;
                    guna2DataGridView1.Columns["dgvCredit"].Width = 110;
                    guna2DataGridView1.Columns["dgvCredit"].DefaultCellStyle.ForeColor = Color.White;
                    guna2DataGridView1.Columns["dgvCredit"].DefaultCellStyle.Format = "N2";
                    guna2DataGridView1.Columns["dgvCredit"].ValueType = typeof(decimal);
                }

                guna2DataGridView1.DataSource = dt;

                // Guna/grid kabhi alias miss karta hai — Credit/Balance seedha DataRow se cell pe likho
                ForceCreditCellsFromData();
                ForceBalanceCellsFromData();

                foreach (DataGridViewColumn c in guna2DataGridView1.Columns)
                {
                    if (c.Name == "IsInitialEntry" || c.DataPropertyName == "IsInitialEntry")
                        c.Visible = false;
                }

                MainClass.SrNo(guna2DataGridView1);
                SetColumnOrder();
            }
            finally
            {
                guna2DataGridView1.ResumeLayout(true);
            }

            CalculateTotalLitter();
            guna2DataGridView1.Invalidate();
            guna2DataGridView1.Refresh();
        }

        /// Credit column = DataTable CreditVal/Credit (binding miss pe bhi 0 na aaye).
        private void ForceCreditCellsFromData()
        {
            if (!guna2DataGridView1.Columns.Contains("dgvCredit")) return;

            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                if (row.IsNewRow) continue;
                if (!(row.DataBoundItem is DataRowView drv)) continue;

                decimal c = 0m;
                if (drv.Row.Table.Columns.Contains("CreditVal"))
                    c = ToDec(drv["CreditVal"]);
                else if (drv.Row.Table.Columns.Contains("Credit"))
                    c = ToDec(drv["Credit"]);

                row.Cells["dgvCredit"].Value = c;
            }
        }

        private void ForceBalanceCellsFromData()
        {
            if (!guna2DataGridView1.Columns.Contains("dgvBalance")) return;

            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                if (row.IsNewRow) continue;
                if (!(row.DataBoundItem is DataRowView drv)) continue;
                if (!drv.Row.Table.Columns.Contains("Balance")) continue;
                row.Cells["dgvBalance"].Value = ToDec(drv["Balance"]);
            }
        }

        private void ApplyCustomerTotalBalances()
        {
            decimal runningTotalBalance = 0;
            string previousCustomer = string.Empty;
            int firstCustomerRowIndex = -1;

            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                if (row.IsNewRow) continue;

                string currentCustomer = row.Cells["dgvName"].Value?.ToString() ?? string.Empty;

                if (currentCustomer != previousCustomer && firstCustomerRowIndex != -1)
                {
                    guna2DataGridView1.Rows[firstCustomerRowIndex].Cells["dgvTotalBalance"].Value =
                        runningTotalBalance.ToString("F2");
                    runningTotalBalance = 0;
                }

                if (row.Cells["dgvBalance"].Value != null && row.Cells["dgvBalance"].Value != DBNull.Value)
                    runningTotalBalance += Convert.ToDecimal(row.Cells["dgvBalance"].Value);

                if (currentCustomer != previousCustomer)
                    firstCustomerRowIndex = row.Index;
                else
                    row.Cells["dgvTotalBalance"].Value = DBNull.Value;

                previousCustomer = currentCustomer;
            }

            if (firstCustomerRowIndex != -1)
                guna2DataGridView1.Rows[firstCustomerRowIndex].Cells["dgvTotalBalance"].Value =
                    runningTotalBalance.ToString("F2");
        }


        private void SetColumnOrder()
        {
            guna2DataGridView1.Columns["dgvName"].DisplayIndex = 1;         // Name
            guna2DataGridView1.Columns["dgvDate"].DisplayIndex = 2;         // Date
            guna2DataGridView1.Columns["dgvreciptno"].DisplayIndex = 3;     // ReceiptNo
            guna2DataGridView1.Columns["dgvVechleNo"].DisplayIndex = 4;     // Vehicle
            guna2DataGridView1.Columns["dgvLitter"].DisplayIndex = 5;       // Litter
            guna2DataGridView1.Columns["dgvrate"].DisplayIndex = 6;         // Rate
            guna2DataGridView1.Columns["dgvAdvance"].DisplayIndex = 7;      // Advance
            guna2DataGridView1.Columns["dgvAmount"].DisplayIndex = 8;       // Amount
            guna2DataGridView1.Columns["dgvCredit"].DisplayIndex = 9;       // Credit
            guna2DataGridView1.Columns["dgvBalance"].DisplayIndex = 10;     // Balance
            guna2DataGridView1.Columns["dgvNote"].DisplayIndex = 11;        // Note
            guna2DataGridView1.Columns["dgvTotalBalance"].DisplayIndex = 12;// TotalBalance
        }


        // Method to update the TotalBalance in the database
        private void UpdateTotalBalanceInDatabase(int pid, decimal totalBalance)
        {
            string qry = "UPDATE PetrolAdd SET TotalBalance = @TotalBalance WHERE pid = @pid";

            Hashtable ht = new Hashtable();
            ht.Add("@TotalBalance", totalBalance);
            ht.Add("@pid", pid);

            MainClass.DataInsertUpdateDelete(qry, ht);  // Update the database
        }
        private void guna2DataGridView1_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
        {
            if (e.RowIndex < 0) return;
            string col = guna2DataGridView1.Columns[e.ColumnIndex].Name;

            // Credit + Note → red (VIP). Value DataRow se force — binding miss pe bhi Credit dikhe.
            if (col == "dgvCredit")
            {
                decimal c = 0m;
                var row = guna2DataGridView1.Rows[e.RowIndex];
                if (row.DataBoundItem is DataRowView drv && drv.Row.Table.Columns.Contains("CreditVal"))
                    c = ToDec(drv["CreditVal"]);
                else if (row.DataBoundItem is DataRowView drvOld && drvOld.Row.Table.Columns.Contains("Credit"))
                    c = ToDec(drvOld["Credit"]);
                else if (e.Value != null && e.Value != DBNull.Value)
                    decimal.TryParse(e.Value.ToString(), out c);

                e.Value = c.ToString("N2");
                e.FormattingApplied = true;
                e.CellStyle.ForeColor = Color.White;
                e.CellStyle.Font = new Font(guna2DataGridView1.Font, FontStyle.Bold);

                // Credit Customer row highlight
                if (row.DataBoundItem is DataRowView drv2 &&
                    drv2.Row.Table.Columns.Contains("IsInitialEntry") &&
                    ToDec(drv2["IsInitialEntry"]) == 0)
                {
                    e.CellStyle.BackColor = Color.FromArgb(60, 30, 35);
                }
                return;
            }
            if (col == "dgvNote")
            {
                var row = guna2DataGridView1.Rows[e.RowIndex];
                bool isCreditRow = row.DataBoundItem is DataRowView drvN &&
                    drvN.Row.Table.Columns.Contains("IsInitialEntry") &&
                    ToDec(drvN["IsInitialEntry"]) == 0;
                if (isCreditRow || (e.Value != null && !string.IsNullOrWhiteSpace(e.Value.ToString())))
                {
                    e.CellStyle.ForeColor = Color.White;
                    e.CellStyle.Font = new Font(guna2DataGridView1.Font, FontStyle.Bold);
                }
                if (isCreditRow)
                    e.CellStyle.BackColor = Color.FromArgb(60, 30, 35);
                return;
            }

            // Credit Customer rows — thora highlight (Amount/Litter bhi)
            if (e.RowIndex >= 0 &&
                guna2DataGridView1.Rows[e.RowIndex].DataBoundItem is DataRowView drvRow &&
                drvRow.Row.Table.Columns.Contains("IsInitialEntry") &&
                ToDec(drvRow["IsInitialEntry"]) == 0)
            {
                e.CellStyle.BackColor = Color.FromArgb(60, 30, 35);
            }

            if ((col == "dgvBalance" || col == "dgvTotalBalance") && e.Value != null && e.Value != DBNull.Value)
            {
                if (decimal.TryParse(e.Value.ToString(), out decimal balanceValue))
                {
                    e.Value = balanceValue.ToString("N2");
                    e.FormattingApplied = true;
                    ApplyBalanceCellColor(e, balanceValue);
                }
            }
        }

        private static void ApplyBalanceCellColor(DataGridViewCellFormattingEventArgs e, decimal balanceValue)
        {
            decimal abs = Math.Abs(balanceValue);
            if (abs > 10000m)
            {
                e.CellStyle.BackColor = Color.FromArgb(220, 53, 69);
                e.CellStyle.ForeColor = Color.White;
            }
            else if (abs > 1000m)
            {
                e.CellStyle.BackColor = Color.FromArgb(255, 255, 0);
                e.CellStyle.ForeColor = Color.Black;
            }
            else
            {
                e.CellStyle.BackColor = Color.FromArgb(255, 140, 0);
                e.CellStyle.ForeColor = Color.White;
            }
        }

        // Method to set the order of the columns in DataGridView
        private void guna2DataGridView1_CellDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            if (e.RowIndex < 0 || guna2DataGridView1.CurrentRow == null) return;
            int id = Convert.ToInt32(guna2DataGridView1.CurrentRow.Cells["dgvid"].Value);

            int isInitial = 1;
            object raw = null;
            if (guna2DataGridView1.CurrentRow.DataBoundItem is DataRowView drv &&
                drv.Row.Table.Columns.Contains("IsInitialEntry"))
                raw = drv.Row["IsInitialEntry"];
            if (raw != null && raw != DBNull.Value)
                isInitial = Convert.ToInt32(raw);

            if (isInitial == 0)
            {
                var frm = new frmCreditAdjustAdd { id = id };
                frm.ShowDialog();
            }
            else
            {
                var frm = new frmDiselAdd { id = id };
                frm.ShowDialog();
            }
            LoadData1();
        }



        private void txtSearch_TextChanged(object sender, EventArgs e)
        {
            _searchDebounceTimer.Stop();
            _searchDebounceTimer.Start();
        }

        private void guna2DataGridView1_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Delete)
            {
                if (guna2DataGridView1.CurrentRow != null)
                {
                    // Confirm deletion
                    DialogResult confirmDelete = MessageBox.Show("Are you sure you want to delete this record?",
                                                                "Confirm Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);

                    if (confirmDelete == DialogResult.Yes)
                    {
                        int id = Convert.ToInt32(guna2DataGridView1.CurrentRow.Cells["dgvid"].Value);
                        int customerIdForRepair = 0;
                        try
                        {
                            var htC = new Hashtable { { "@pid", id } };
                            DataTable dtC = MainClass.ExecuteSelectQuery(
                                "SELECT CustomerId FROM PetrolAdd WHERE pid=@pid LIMIT 1", htC);
                            if (dtC != null && dtC.Rows.Count > 0 && dtC.Rows[0][0] != DBNull.Value)
                                customerIdForRepair = Convert.ToInt32(dtC.Rows[0][0]);
                        }
                        catch { }
                        MainClass.DeleteWithTombstone("PetrolAdd", "pid", id, "zaib_petrol_entries");
                        if (customerIdForRepair > 0)
                            Services.BalanceConfirmationService.RecalculateCustomerPetrolBalances(customerIdForRepair);
                        MessageBox.Show("Record deleted successfully.");
                        LoadData1();
                    }
                }
            }
        }

        private void btnDel_Click(object sender, EventArgs e)
        {
            if (comboBox1.SelectedItem != null)
            {
                string selectedOption = comboBox1.SelectedItem.ToString();

                if (selectedOption == "Rate")
                {
                    CalculateAverage("Rate");
                }
                else
                {
                    CustomeMessage noDataMessage = new CustomeMessage("Please select a valid option!", "Info");
                    noDataMessage.ShowDialog();
                }
            }
        }

        private void CalculateAverage(string type)
        {
            DateTime startDate = dtpStart.Value.Date; // Start date
            DateTime endDate = dtpEnd.Value.Date; // End date
            decimal totalSum = 0;
            decimal totalLitterSum = 0;
            int rowCount = 0;

            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                DateTime rowDate = Convert.ToDateTime(row.Cells["dgvDate"].Value).Date;

                // Check if row date is equal to or between start and end dates (inclusive)
                if (rowDate >= startDate && rowDate <= endDate)
                {
                    if (row.Cells["dgvAmount"].Value != DBNull.Value && row.Cells["dgvLitter"].Value != DBNull.Value)
                    {
                        decimal amount = Convert.ToDecimal(row.Cells["dgvAmount"].Value);
                        decimal litter = Convert.ToDecimal(row.Cells["dgvLitter"].Value);

                        totalSum += amount;
                        totalLitterSum += litter;
                        rowCount++;
                    }
                }
            }

            // Displaying the results
            if (rowCount > 0)
            {
                if (totalLitterSum != 0) // Ensure no division by zero
                {
                    decimal ratio = totalSum / totalLitterSum;
                    lblResult.Text = $"Sum Amount: {totalSum:F2}, Sum Litter: {totalLitterSum:F2}, Average: {ratio:F2}";
                }
                else
                {
                    lblResult.Text = "Total Litter is zero, cannot calculate ratio.";
                }
            }
            else
            {
                lblResult.Text = "No data found for the selected date range.";
            }
        }

        private void btnAverage_Click_1(object sender, EventArgs e)
        {
            // Calculate Average based on the selected ComboBox option (Rate)
            if (comboBox1.Visible && comboBox1.SelectedItem != null)
            {
                string selectedOption = comboBox1.SelectedItem.ToString();
                if (selectedOption == "Rate")
                {
                    CalculateAverage("Rate");
                }
                else
                {
                    CustomeMessage noDataMessage = new CustomeMessage("Please select a valid option!", "Info");
                    noDataMessage.ShowDialog();
                }
            }
        }


        // Method to calculate TotalBalance for each customer
        private void CalculateTotalBalance()
        {
            decimal runningTotalBalance = 0;
            string previousCustomer = "";
            int firstCustomerRowIndex = -1;

            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                string currentCustomer = row.Cells["dgvName"].Value?.ToString() ?? string.Empty;

                // If a new customer starts, show TotalBalance in the first row of the previous customer
                if (currentCustomer != previousCustomer && firstCustomerRowIndex != -1)
                {
                    guna2DataGridView1.Rows[firstCustomerRowIndex].Cells["dgvTotalBalance"].Value = runningTotalBalance.ToString("F2");
                    runningTotalBalance = 0; // Reset for new customer
                }

                // Calculate current customer's running total balance
                if (row.Cells["dgvBalance"].Value != DBNull.Value)
                {
                    decimal currentBalance = Convert.ToDecimal(row.Cells["dgvBalance"].Value);
                    runningTotalBalance += currentBalance;
                }

                // Track first row index for current customer
                if (currentCustomer != previousCustomer)
                {
                    firstCustomerRowIndex = row.Index; // Store first index for the customer
                }

                previousCustomer = currentCustomer; // Update previous customer
            }

            // Update TotalBalance for the last customer
            if (firstCustomerRowIndex != -1)
            {
                guna2DataGridView1.Rows[firstCustomerRowIndex].Cells["dgvTotalBalance"].Value = runningTotalBalance.ToString("F2");
            }
        }

        private void DatePickers_ValueChanged(object sender, EventArgs e)
        {
            LoadData1();
        }

        private void CalculateTotalLitter()
        {
            decimal totalLitterSum = 0;
            decimal totalAmountSum = 0;
            decimal totalCreditSum = 0;
            bool hasRow = false;

            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                if (row.IsNewRow) continue;
                hasRow = true;

                if (row.Cells["dgvLitter"].Value != null && row.Cells["dgvLitter"].Value != DBNull.Value)
                    totalLitterSum += Convert.ToDecimal(row.Cells["dgvLitter"].Value);

                if (row.Cells["dgvAmount"].Value != null && row.Cells["dgvAmount"].Value != DBNull.Value)
                    totalAmountSum += Convert.ToDecimal(row.Cells["dgvAmount"].Value);

                // Credit: pehle cell, warna DataRow CreditVal (summary 0 na ho)
                decimal rowCredit = 0m;
                if (row.Cells["dgvCredit"].Value != null && row.Cells["dgvCredit"].Value != DBNull.Value)
                    rowCredit = ToDec(row.Cells["dgvCredit"].Value);
                else if (row.DataBoundItem is DataRowView drvSum)
                {
                    if (drvSum.Row.Table.Columns.Contains("CreditVal"))
                        rowCredit = ToDec(drvSum["CreditVal"]);
                    else if (drvSum.Row.Table.Columns.Contains("Credit"))
                        rowCredit = ToDec(drvSum["Credit"]);
                }
                totalCreditSum += rowCredit;
            }

            lblLitter.Text = $"Total Litter: {totalLitterSum:F2} L";
            lblAmount.Text = $"Total Amount: {totalAmountSum:F2}";

            decimal periodNet = totalAmountSum - totalCreditSum;
            // Footer = sirf is list ki period movement; Balance column = poori history running (SQL).
            if (!string.IsNullOrWhiteSpace(txtSearch.Text) && hasRow)
            {
                lblResult.Text =
                    $"VIP period: Amount {totalAmountSum:F2} − Credit {totalCreditSum:F2} = {periodNet:F2}  |  Balance column = running";
                lblResult.ForeColor = Color.FromArgb(255, 215, 0);
            }
            else if (hasRow)
            {
                lblResult.Text =
                    $"Credit {totalCreditSum:F2}  |  Period net {periodNet:F2}  |  Balance column = full running";
                lblResult.ForeColor = Color.White;
            }
            else
            {
                lblResult.Text = "0.00";
                lblResult.ForeColor = Color.White;
            }
        }

    }
}