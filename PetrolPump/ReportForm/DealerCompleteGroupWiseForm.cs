using Microsoft.Reporting.WinForms;
using Guna.UI2.WinForms;
using ZaibPetroleumService;
using ZaibPetroleumService.ReportForm;
using ZaibPetroleumService.ProjectConnection;
using System;
using System.Data;
using System.Data.SQLite;
using System.IO;
using System.Windows.Forms;

namespace HajiBalochSoftwere.ReportForm
{
    public partial class DealerCompleteGroupWiseForm : Sample
    {
        public DealerCompleteGroupWiseForm()
        {
            InitializeComponent();
        }

        private void DealerCompleteGroupWiseForm_Load(object sender, EventArgs e)
        {
            try
            {
                fromdate.Value = DateTime.Now;
                todate.Value = DateTime.Now;
                LoadAllRecords();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Dealer Group Wise open nahi ho saka:\n" + ex.Message,
                    "Report Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void LoadAllRecords()
        {
            BindReport(@"
SELECT
    d.Did,
    d.DealerName,
    IFNULL(d.DDAmount, 0) AS DDAmount_Master,
    IFNULL(d.DAmount, 0) AS DAmount_Master,
    (IFNULL(d.DDAmount, 0) - IFNULL(d.DAmount, 0)) AS Balance_Master,
    s.Date AS StockDate,
    s.Vehicle AS VehicleNo,
    IFNULL(s.AddDisel, 0) AS Litter,
    IFNULL(s.Rate, 0) AS Rate,
    (IFNULL(s.AddDisel, 0) * IFNULL(s.Rate, 0)) AS Amount,
    (CAST(IFNULL(s.AddDisel, 0) AS TEXT) || ' x ' || CAST(IFNULL(s.Rate, 0) AS TEXT)) AS LitterRateDetail
FROM AddDealer d
LEFT JOIN AddStock s ON s.DealerId = d.Did
ORDER BY d.DealerName, s.Date, s.Sid;", null, null, null);
        }

        private void btnSearch_Click(object sender, EventArgs e)
        {
            try
            {
                string searchText = txtSearch.Text ?? "";
                if (fromdate.Value.Date > todate.Value.Date)
                {
                    MessageBox.Show("To Date, From Date se chhoti nahi ho sakti.",
                        "Date Range Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                BindReport(@"
SELECT
    d.Did,
    d.DealerName,
    IFNULL(d.DDAmount, 0) AS DDAmount_Master,
    IFNULL(d.DAmount, 0) AS DAmount_Master,
    (IFNULL(d.DDAmount, 0) - IFNULL(d.DAmount, 0)) AS Balance_Master,
    s.Date AS StockDate,
    s.Vehicle AS VehicleNo,
    IFNULL(s.AddDisel, 0) AS Litter,
    IFNULL(s.Rate, 0) AS Rate,
    (IFNULL(s.AddDisel, 0) * IFNULL(s.Rate, 0)) AS Amount,
    (CAST(IFNULL(s.AddDisel, 0) AS TEXT) || ' x ' || CAST(IFNULL(s.Rate, 0) AS TEXT)) AS LitterRateDetail
FROM AddDealer d
LEFT JOIN AddStock s ON s.DealerId = d.Did
WHERE
    (
        @SearchText = ''
        OR TRIM(IFNULL(d.DealerName,'')) = @SearchText COLLATE NOCASE
        OR IFNULL(s.Vehicle, '') LIKE @SearchLike COLLATE NOCASE
    )
    AND (s.Date IS NULL OR (date(s.Date) >= date(@FromDate) AND date(s.Date) <= date(@ToDate)))
ORDER BY d.DealerName, s.Date, s.Sid;", searchText, fromdate, todate);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Search fail:\n" + ex.Message, "Report Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BindReport(string sql, string searchText, Guna2DateTimePicker from, Guna2DateTimePicker to)
        {
            string reportPath = ResolveReportPath("DealerGroupWise.rdlc");
            if (reportPath == null)
            {
                MessageBox.Show("Report file nahi mili: Reports\\DealerGroupWise.rdlc",
                    "Missing Report", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string connectionString = projectconnection.conReturn();
            using (SQLiteConnection con = new SQLiteConnection(connectionString))
            using (SQLiteCommand cmd = new SQLiteCommand(sql, con))
            {
                con.Open();
                if (from != null && to != null)
                    ReportDateRangeHelper.AddToCommand(cmd, from, to);
                if (searchText != null)
                    ReportSearchHelper.BindSearch(cmd, searchText);

                DataTable dt = new DataTable();
                using (SQLiteDataAdapter sd = new SQLiteDataAdapter(cmd))
                    sd.Fill(dt);

                if (dt.Rows.Count == 0 && searchText != null)
                {
                    MessageBox.Show("Koi data nahi mila.", "Information",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                reportViewer1.Reset();
                reportViewer1.ProcessingMode = ProcessingMode.Local;
                reportViewer1.LocalReport.ReportPath = reportPath;
                reportViewer1.LocalReport.DataSources.Clear();
                reportViewer1.LocalReport.DataSources.Add(new ReportDataSource("DataSet1", dt));
                reportViewer1.RefreshReport();
            }
        }

        private static string ResolveReportPath(string fileName)
        {
            string[] roots =
            {
                Application.StartupPath,
                AppDomain.CurrentDomain.BaseDirectory,
                Path.GetFullPath(Path.Combine(Application.StartupPath, "..", ".."))
            };
            foreach (string root in roots)
            {
                string p = Path.Combine(root, "Reports", fileName);
                if (File.Exists(p)) return p;
            }
            return null;
        }
    }
}
