using Guna.UI2.WinForms;
using ZaibPetroleumService.Model;
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Windows.Forms.DataVisualization.Charting;
using System.Xml.Linq;

namespace ZaibPetroleumService.View
{
    public partial class frmCustomerView : SampleView
    {
        public frmCustomerView()
        {
            InitializeComponent();
        }

        private void frmCustomerView_Load(object sender, EventArgs e)
        {
            LoadData1();
        }
   

        public override void btnAdd_Click(object sender, EventArgs e)
        {
            frmCustomerAdd frm = new frmCustomerAdd();
            frm.ShowDialog();
            LoadData1();
        }

        private void LoadData1()
        {

            string qry = "SELECT id, Name, Mobile, Date FROM AddCustomer WHERE " +
              "Name LIKE '%" + txtSearch.Text + "%' order by id";

            ListBox lb = new ListBox();
            lb.Items.Add(dgvid);
            lb.Items.Add(dgvName);
            lb.Items.Add(dgvPhone);
            lb.Items.Add(dgvDate);
            MainClass.loadData(qry, guna2DataGridView1, lb);

            foreach (DataGridViewColumn column in guna2DataGridView1.Columns)
            {
                column.SortMode = DataGridViewColumnSortMode.NotSortable;
            }
        }

        private void guna2DataGridView1_CellDoubleClick(object sender, DataGridViewCellEventArgs e)
        {
            int id = Convert.ToInt32(guna2DataGridView1.CurrentRow.Cells["dgvid"].Value);
            frmCustomerAdd frm = new frmCustomerAdd();
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
