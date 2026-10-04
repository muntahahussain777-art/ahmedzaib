using ZaibPetroleumService.Model;
using System;
using System.Data;
using System.Windows.Forms;

namespace ZaibPetroleumService.View
{
    public partial class FrmDirectDealerPaymentAmountView : SampleView
    {
        public FrmDirectDealerPaymentAmountView()
        {
            InitializeComponent();
        }

        private void FrmDirectDealerPaymentAmountView_Load(object sender, EventArgs e)
        {
            LoadLedgerEntries();
        }

        public void LoadLedgerEntries()
        {
            string searchText = (txtSearch.Text ?? "").Trim().Replace("'", "''");

            string query = @"SELECT 
                    DL.LedgerID,   
                    DL.Did, 
                    DL.Date,
                    DA.DealerName,
                    DL.AmounGiven,
                    DL.Note
                FROM DieselLedgerDebit DL
                LEFT JOIN AddDealer DA ON DL.Did = DA.Did
                WHERE IFNULL(DA.DealerName, '') LIKE '%" + searchText + @"%'
                   OR IFNULL(DL.Note, '') LIKE '%" + searchText + @"%'
                ORDER BY DL.LedgerID ASC";

            DataTable dt = MainClass.GetData(query);

            guna2DataGridView1.AutoGenerateColumns = true;
            if (dt != null && dt.Rows.Count > 0)
            {
                guna2DataGridView1.DataSource = dt;
                if (guna2DataGridView1.Columns.Contains("dgvid"))
                    guna2DataGridView1.Columns["dgvid"].DataPropertyName = "LedgerID";
                if (guna2DataGridView1.Columns.Contains("LedgerID"))
                    guna2DataGridView1.Columns["LedgerID"].Visible = false;
                if (guna2DataGridView1.Columns.Contains("Did"))
                    guna2DataGridView1.Columns["Did"].Visible = false;
            }
            else
                guna2DataGridView1.DataSource = null;
        }

        public override void btnAdd_Click(object sender, EventArgs e)
        {
            FrmDirectDealerPaymentAmountAdd frmAdd = new FrmDirectDealerPaymentAmountAdd();
            if (frmAdd.ShowDialog() == DialogResult.OK)
                LoadLedgerEntries();
        }

        private void guna2DataGridView1_CellDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            OpenEdit();
        }

        private void OpenEdit()
        {
            if (guna2DataGridView1.CurrentRow == null || guna2DataGridView1.CurrentRow.IsNewRow)
            {
                MessageBox.Show("Please select a valid record.");
                return;
            }

            int id = TryGetLedgerId(guna2DataGridView1.CurrentRow);
            if (id <= 0)
            {
                MessageBox.Show("Please select a valid record.");
                return;
            }

            FrmDirectDealerPaymentAmountAdd frmEdit = new FrmDirectDealerPaymentAmountAdd(id);
            if (frmEdit.ShowDialog() == DialogResult.OK)
                LoadLedgerEntries();
        }

        private static int TryGetLedgerId(DataGridViewRow row)
        {
            try
            {
                if (row.DataBoundItem is DataRowView drv)
                {
                    if (drv.Row.Table.Columns.Contains("LedgerID") && drv["LedgerID"] != DBNull.Value)
                        return Convert.ToInt32(drv["LedgerID"]);
                }
                if (row.DataGridView.Columns.Contains("LedgerID") && row.Cells["LedgerID"].Value != null &&
                    row.Cells["LedgerID"].Value != DBNull.Value)
                    return Convert.ToInt32(row.Cells["LedgerID"].Value);
                if (row.DataGridView.Columns.Contains("dgvid") && row.Cells["dgvid"].Value != null &&
                    row.Cells["dgvid"].Value != DBNull.Value)
                    return Convert.ToInt32(row.Cells["dgvid"].Value);
            }
            catch { }
            return 0;
        }

        public override void txtSearch_TextChanged_1(object sender, EventArgs e) { }

        private void txtSearch_TextChanged(object sender, EventArgs e)
        {
            LoadLedgerEntries();
        }

        private void guna2DataGridView1_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
        {
            MainClass.SrNo(guna2DataGridView1);
        }
    }
}
