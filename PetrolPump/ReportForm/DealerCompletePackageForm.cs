using Microsoft.Reporting.WinForms;
using ZaibPetroleumService;
using ZaibPetroleumService.ReportForm;
using ZaibPetroleumService.ProjectConnection;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SQLite;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HajiBalochSoftwere.ReportForm
{
    public partial class DealerCompletePackageForm : Sample
    {
        public DealerCompletePackageForm()
        {
            InitializeComponent();
        }

        private void DealerCompletePackageForm_Load(object sender, EventArgs e)
        {
            try
            {
                fromdate.Value = DateTime.Now;
                todate.Value = DateTime.Now;
                LoadAllRecords();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Dealer Complete open nahi ho saka:\n" + ex.Message,
                    "Report Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        private void LoadAllRecords()
        {
            string connectionString = projectconnection.conReturn();
            string reportPath = Path.Combine(Application.StartupPath, "Reports", "DealerCompleteReportForm.rdlc");
            if (!File.Exists(reportPath))
            {
                MessageBox.Show("Report file nahi mili: Reports\\DealerCompleteReportForm.rdlc",
                    "Missing Report", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            using (SQLiteConnection con = new SQLiteConnection(connectionString))
            {
                SQLiteCommand cmd = new SQLiteCommand(@"
               SELECT
                d.Did,
                d.DealerName,
                IFNULL(d.DDAmount, 0)  AS DDAmount_Master,
                IFNULL(d.DAmount, 0)   AS DAmount_Master,
                (IFNULL(d.DDAmount, 0) - IFNULL(d.DAmount, 0)) AS Balance_Master,
                s.Date                 AS StockDate,
                s.Vehicle              AS VehicleNo,
                IFNULL(s.AddDisel, 0)  AS Litter,
                IFNULL(s.Rate, 0)      AS Rate,
                (IFNULL(s.AddDisel, 0) * IFNULL(s.Rate, 0)) AS Amount
            FROM AddDealer d
            LEFT JOIN AddStock s 
                ON s.DealerId = d.Did
            ORDER BY 
                d.DealerName,
                s.Date,
                s.Sid;", con);

                SQLiteDataAdapter sd = new SQLiteDataAdapter(cmd);
                DataTable dt = new DataTable();
                sd.Fill(dt);

                reportViewer1.Reset();
                reportViewer1.ProcessingMode = ProcessingMode.Local;
                reportViewer1.LocalReport.ReportPath = reportPath;
                reportViewer1.LocalReport.DataSources.Clear();
                reportViewer1.LocalReport.DataSources.Add(new ReportDataSource("DataSet1", dt));
                reportViewer1.RefreshReport();
            }
        }

        private void btnSearch_Click(object sender, EventArgs e)
        {
            string searchText = txtSearch.Text;

            // 🔹 Prevent wrong date range
            if (fromdate.Value.Date > todate.Value.Date)
            {
                MessageBox.Show("To Date, From Date se chhoti nahi ho sakti.",
                                "Date Range Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string connectionString = projectconnection.conReturn();

            using (SQLiteConnection con = new SQLiteConnection(connectionString))
            {
                con.Open();

                SQLiteCommand cmd = new SQLiteCommand(@"
        SELECT
    d.Did,
    d.DealerName,

    IFNULL(d.DDAmount, 0)  AS DDAmount_Master,
    IFNULL(d.DAmount, 0)   AS DAmount_Master,
    (IFNULL(d.DDAmount, 0) - IFNULL(d.DAmount, 0)) AS Balance_Master,

    s.Date                 AS StockDate,
    s.Vehicle              AS VehicleNo,
    IFNULL(s.AddDisel, 0)  AS Litter,
    IFNULL(s.Rate, 0)      AS Rate,

    (IFNULL(s.AddDisel, 0) * IFNULL(s.Rate, 0)) AS Amount

FROM AddDealer d
LEFT JOIN AddStock s 
    ON s.DealerId = d.Did

WHERE 
    (
        @SearchText = ''
        OR TRIM(IFNULL(d.DealerName,'')) = @SearchText COLLATE NOCASE
        OR IFNULL(s.Vehicle, '') LIKE @SearchLike COLLATE NOCASE
    )
    AND (s.Date IS NULL OR (date(s.Date) >= date(@FromDate) AND date(s.Date) <= date(@ToDate)))

ORDER BY 
    d.DealerName,
    s.Date,
    s.Sid;", con);

                ReportDateRangeHelper.AddToCommand(cmd, fromdate, todate);
                ReportSearchHelper.BindSearch(cmd, searchText);

                SQLiteDataAdapter sd = new SQLiteDataAdapter(cmd);
                DataTable dt = new DataTable();
                sd.Fill(dt);

                if (dt.Rows.Count == 0)
                {
                    MessageBox.Show("Koi data nahi mila.",
                                    "Information", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                ReportDataSource rds = new ReportDataSource("DataSet1", dt);
                string reportPath = Path.Combine(Application.StartupPath, "Reports", "DealerCompleteReportForm.rdlc");
                reportViewer1.LocalReport.ReportPath = reportPath;

                reportViewer1.LocalReport.DataSources.Clear();
                reportViewer1.LocalReport.DataSources.Add(rds);
                reportViewer1.RefreshReport();
            }
        }
    }
}