using Microsoft.Reporting.WinForms;
using ZaibPetroleumService.ProjectConnection;
using System;
using System.Data;
using System.Data.SQLite; // SQL Server کی جگہ SQLite استعمال کریں
using System.IO;
using System.Windows.Forms;

namespace ZaibPetroleumService.ReportForm
{
    public partial class frmReportButton : Sample
    {
        public frmReportButton()
        {
            InitializeComponent();
        }

        public string ReportName { get; set; }
        public DataTable ReportData { get; set; }

        // فارم لوڈ ہوتے ہی customer names کے ساتھ ComboBox populate کریں اور تمام records لوڈ کریں
        private void frmReportButton_Load(object sender, EventArgs e)
        {
            PopulateCustomerComboBox();
            LoadAllRecords(); // فارم لوڈ ہونے پر تمام records لوڈ کریں
        }

        private void PopulateCustomerComboBox()
        {
            string connectionString = projectconnection.conReturn();

            using (SQLiteConnection con = new SQLiteConnection(connectionString))
            {
                con.Open();
                // distinct customer names حاصل کرنے کے لیے SQL query
                SQLiteCommand cmd = new SQLiteCommand(@"
                    SELECT DISTINCT AddCustomer.Name
                    FROM AddCustomer
                    INNER JOIN PetrolAdd ON AddCustomer.Id = PetrolAdd.CustomerId", con);

                SQLiteDataAdapter sd = new SQLiteDataAdapter(cmd);
                DataTable dt = new DataTable();
                sd.Fill(dt);

                // ComboBox میں customer names populate کریں
                comboBoxCustomer.DataSource = dt;
                comboBoxCustomer.DisplayMember = "Name";
                comboBoxCustomer.ValueMember = "Name";  // filtering کے لیے Name ہی استعمال کریں
                comboBoxCustomer.DropDownHeight = 200;
                comboBoxCustomer.IntegralHeight = false;
            }
        }

        private void LoadAllRecords()
        {
            string connectionString = projectconnection.conReturn();

            using (SQLiteConnection con = new SQLiteConnection(connectionString))
            {
                con.Open();
                SQLiteCommand cmd = new SQLiteCommand(@"
            SELECT 
                PetrolAdd.pid, 
                PetrolAdd.Date, 
                PetrolAdd.ReceiptNo, 
                PetrolAdd.vehicle, 
                PetrolAdd.Litter, 
                PetrolAdd.Rate, 
                PetrolAdd.Advance, 

                -- 🔹 Amount: direct amount ho to PetrolAdd.Amount use karo
                CASE 
                    WHEN IFNULL(PetrolAdd.Litter, 0) = 0 
                      AND IFNULL(PetrolAdd.Rate, 0) = 0
                    THEN IFNULL(PetrolAdd.Amount, 0)
                    ELSE (PetrolAdd.Litter * PetrolAdd.Rate + IFNULL(PetrolAdd.Advance, 0))
                END AS Amount,

                PetrolAdd.Credit, 

                -- 🔹 Balance: direct wali entry ho to table ka Balance use karo
                CASE 
                    WHEN IFNULL(PetrolAdd.Litter, 0) = 0 
                      AND IFNULL(PetrolAdd.Rate, 0) = 0
                    THEN IFNULL(PetrolAdd.Balance, 0)
                    ELSE ((PetrolAdd.Litter * PetrolAdd.Rate + IFNULL(PetrolAdd.Advance, 0)) 
                          - IFNULL(PetrolAdd.Credit, 0))
                END AS Balance,

                PetrolAdd.Note, 
                AddCustomer.Name 
            FROM 
                PetrolAdd 
            INNER JOIN 
                AddCustomer ON PetrolAdd.CustomerId = AddCustomer.Id
            ORDER BY 
                PetrolAdd.Date ASC", con);

                SQLiteDataAdapter sd = new SQLiteDataAdapter(cmd);
                DataTable dt = new DataTable();
                sd.Fill(dt);

                ReportDataSource rds = new ReportDataSource("DataSet1", dt);
                string reportPath = Path.Combine(Application.StartupPath, "Reports", "AddPetrol.rdlc");
                reportViewer1.LocalReport.ReportPath = reportPath;

                reportViewer1.LocalReport.DataSources.Clear();
                reportViewer1.LocalReport.DataSources.Add(rds);

                reportViewer1.RefreshReport();
            }
        }

        private void btnSearch_Click(object sender, EventArgs e)
        {
            string selectedCustomer = comboBoxCustomer.SelectedValue?.ToString();

            if (string.IsNullOrEmpty(selectedCustomer))
            {
                MessageBox.Show("Please select a customer.");
                return;
            }

            string connectionString = projectconnection.conReturn();

            using (SQLiteConnection con = new SQLiteConnection(connectionString))
            {
                con.Open();
                SQLiteCommand cmd = new SQLiteCommand(@"
            SELECT 
                PetrolAdd.pid, 
                PetrolAdd.Date, 
                PetrolAdd.ReceiptNo, 
                PetrolAdd.vehicle, 
                PetrolAdd.Litter, 
                PetrolAdd.Rate, 
                PetrolAdd.Advance, 

                CASE 
                    WHEN IFNULL(PetrolAdd.Litter, 0) = 0 
                      AND IFNULL(PetrolAdd.Rate, 0) = 0
                    THEN IFNULL(PetrolAdd.Amount, 0)
                    ELSE (PetrolAdd.Litter * PetrolAdd.Rate + IFNULL(PetrolAdd.Advance, 0))
                END AS Amount,

                PetrolAdd.Credit, 

                CASE 
                    WHEN IFNULL(PetrolAdd.Litter, 0) = 0 
                      AND IFNULL(PetrolAdd.Rate, 0) = 0
                    THEN IFNULL(PetrolAdd.Balance, 0)
                    ELSE ((PetrolAdd.Litter * PetrolAdd.Rate + IFNULL(PetrolAdd.Advance, 0)) 
                          - IFNULL(PetrolAdd.Credit, 0))
                END AS Balance,

                PetrolAdd.Note, 
                AddCustomer.Name 
            FROM 
                PetrolAdd 
            INNER JOIN 
                AddCustomer ON PetrolAdd.CustomerId = AddCustomer.Id 
            WHERE 
                TRIM(AddCustomer.Name) = @SearchText COLLATE NOCASE
            ORDER BY 
                PetrolAdd.Date ASC", con);

                ReportSearchHelper.BindSearch(cmd, selectedCustomer);

                SQLiteDataAdapter sd = new SQLiteDataAdapter(cmd);
                DataTable dt = new DataTable();
                sd.Fill(dt);

                ReportDataSource rds = new ReportDataSource("DataSet1", dt);
                string reportPath = Path.Combine(Application.StartupPath, "Reports", "AddPetrol.rdlc");
                reportViewer1.LocalReport.ReportPath = reportPath;

                reportViewer1.LocalReport.DataSources.Clear();
                reportViewer1.LocalReport.DataSources.Add(rds);

                reportViewer1.RefreshReport();
            }
        }
    }
}
