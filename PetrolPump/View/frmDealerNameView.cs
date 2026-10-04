using ZaibPetroleumService.Model;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ZaibPetroleumService.View
{
    public partial class frmDealerNameView : SampleView
    {
        public frmDealerNameView()
        {
            InitializeComponent();
        }

        private void frmDealerNameView_Load(object sender, EventArgs e)
        {
            LoadData1();
        }
        public override void btnAdd_Click(object sender, EventArgs e)
        {
            DealerAdd frm = new DealerAdd();
            frm.ShowDialog();
            LoadData1();
        }

        private void LoadData1()
        {
            string qry = "SELECT Did, DealerName, DDAmount, DAmount, (DDAmount - DAmount) AS Balance, Date FROM AddDealer " +
                         "WHERE DealerName LIKE '%" + txtSearch.Text + "%' ORDER BY Did";

            ListBox lb = new ListBox();
            lb.Items.Add(dgvid);
            lb.Items.Add(dgvName);
            lb.Items.Add(dgvDealerAmount);
            lb.Items.Add(dgvAmount);
            lb.Items.Add(dgvBalance); // Add Balance column
            lb.Items.Add(dgvDate);

            MainClass.loadData(qry, guna2DataGridView1, lb);

            foreach (DataGridViewColumn column in guna2DataGridView1.Columns)
            {
                column.SortMode = DataGridViewColumnSortMode.NotSortable;
            }

            // ───────────────────────────
            // [ADDED CODE] ↓↓↓
            // ───────────────────────────
            decimal sumDDAmount = 0;
            decimal sumDAmount = 0;

            // DataGridView ki sabhi rows ko loop karein:
            foreach (DataGridViewRow row in guna2DataGridView1.Rows)
            {
                // DealerAmount
                if (row.Cells["dgvDealerAmount"].Value != null && row.Cells["dgvDealerAmount"].Value != DBNull.Value)
                {
                    sumDDAmount += Convert.ToDecimal(row.Cells["dgvDealerAmount"].Value);
                }

                // DAmount
                if (row.Cells["dgvAmount"].Value != null && row.Cells["dgvAmount"].Value != DBNull.Value)
                {
                    sumDAmount += Convert.ToDecimal(row.Cells["dgvAmount"].Value);
                }
            }

            // Ab labels mein show karwa dein:
            lblDDAmount.Text = sumDDAmount.ToString();             // Pehla label (Total DDAmount)
            lblDAmount.Text = sumDAmount.ToString();               // Dosra label (Total DAmount)
            lblBalance.Text = (sumDDAmount - sumDAmount).ToString(); // Teesra label (Dono ka difference)
                                                                     // ───────────────────────────
                                                                     // [ADDED CODE] ↑↑↑
                                                                     // ───────────────────────────
        }

        private void guna2DataGridView1_CellDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            int id = Convert.ToInt32(guna2DataGridView1.CurrentRow.Cells["dgvid"].Value);
            DealerAdd frm = new DealerAdd();
            frm.id = id; // id set ki gayi
            frm.ShowDialog();
            LoadData1();
        }

        private void guna2DataGridView1_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
        {
            MainClass.SrNo(guna2DataGridView1);
        }
        private void txtSearch_TextChanged(object sender, EventArgs e)
        {
            LoadData1();
        }
    }
}
