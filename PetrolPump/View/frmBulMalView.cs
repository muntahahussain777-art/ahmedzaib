using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows.Forms;
using Guna.UI2.WinForms;
using ZaibPetroleumService.Model;

namespace ZaibPetroleumService.View
{
    /// <summary>
    /// Bul Mal — stylish VIP view (In/Out/Balance + PDF). Sync/pull nahi.
    /// </summary>
    public class frmBulMalView : SampleView
    {
        private readonly Panel _banner = new Panel();
        private readonly Label _lblIn = new Label();
        private readonly Label _lblOut = new Label();
        private readonly Label _lblBalance = new Label();
        private readonly Label _lblHint = new Label();
        private readonly DateTimePicker _from = new DateTimePicker();
        private readonly DateTimePicker _to = new DateTimePicker();
        private readonly CheckBox _chkDate = new CheckBox();
        private readonly Guna2Button _btnOwners = new Guna2Button();
        private readonly Guna2Button _btnPdf = new Guna2Button();
        private readonly Guna2DataGridView _grid = new Guna2DataGridView();
        private DataTable _currentRows = new DataTable();

        public frmBulMalView()
        {
            Name = "frmBulMalView";
            Text = "Bul Mal";
            KeyPreview = true;
            BuildChrome();
            Load += (s, e) =>
            {
                label1.Text = "Bul Mal Search";
                txtSearch.PlaceholderText = "Exact owner name / note…";
                btnAdd.Text = "Add Entry";
                LoadData();
            };
            KeyDown += Frm_KeyDown;
        }

        private void Frm_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Control && e.KeyCode == Keys.R) { LoadData(); e.Handled = true; }
            if (e.Control && e.KeyCode == Keys.N) { OpenEntry(); e.Handled = true; }
            if (e.KeyCode == Keys.Delete) DeleteSelected();
        }

        public override void btnAdd_Click(object sender, EventArgs e) => OpenEntry();

        public override void txtSearch_TextChanged_1(object sender, EventArgs e) => LoadData();

        private void BuildChrome()
        {
            // SampleView already has panel1 (search + add). Banner below it.
            _banner.Dock = DockStyle.Top;
            _banner.Height = 96;
            _banner.BackColor = Color.FromArgb(20, 28, 52);
            _banner.Padding = new Padding(12, 8, 12, 8);

            StyleStatCard(_lblIn, "TOTAL IN", "0", Color.FromArgb(46, 204, 113), 12);
            StyleStatCard(_lblOut, "TOTAL OUT", "0", Color.FromArgb(231, 76, 60), 230);
            StyleStatCard(_lblBalance, "TOTAL BALANCE", "0", Color.FromArgb(212, 175, 55), 448);

            _lblHint.Text = "Developed by Irtaza Hussain  •  Ctrl+N Add Entry  •  Delete = remove";
            _lblHint.ForeColor = Color.FromArgb(160, 170, 190);
            _lblHint.Font = new Font("Segoe UI", 8.5F);
            _lblHint.AutoSize = true;
            _lblHint.Location = new Point(670, 62);
            _banner.Controls.Add(_lblHint);

            _chkDate.Text = "Date filter";
            _chkDate.ForeColor = Color.White;
            _chkDate.Font = new Font("Segoe UI Semibold", 9F);
            _chkDate.AutoSize = true;
            _chkDate.Location = new Point(670, 14);
            _chkDate.CheckedChanged += (s, e) => LoadData();
            _banner.Controls.Add(_chkDate);

            _from.Format = DateTimePickerFormat.Custom;
            _from.CustomFormat = "dd-MMM-yyyy";
            _from.Width = 110;
            _from.Location = new Point(760, 10);
            _from.ValueChanged += (s, e) => { if (_chkDate.Checked) LoadData(); };
            _banner.Controls.Add(_from);

            _to.Format = DateTimePickerFormat.Custom;
            _to.CustomFormat = "dd-MMM-yyyy";
            _to.Width = 110;
            _to.Location = new Point(880, 10);
            _to.ValueChanged += (s, e) => { if (_chkDate.Checked) LoadData(); };
            _banner.Controls.Add(_to);

            StyleAction(_btnOwners, "Owners", Color.FromArgb(212, 175, 55), Color.FromArgb(32, 36, 61));
            _btnOwners.Click += (s, e) =>
            {
                using (var f = new frmBulMalOwnerAdd())
                    f.ShowDialog(FindForm());
                LoadData();
            };

            StyleAction(_btnPdf, "VIP PDF", Color.FromArgb(52, 73, 94), Color.White);
            _btnPdf.Click += (s, e) => ExportPdf();

            panel1.Controls.Add(_btnPdf);
            panel1.Controls.Add(_btnOwners);
            panel1.Resize += (s, e) => PositionTopButtons();
            PositionTopButtons();

            // Dock order: Fill pehle, phir Top (last Top = sab se upar)
            panel1.Dock = DockStyle.Top;
            panel1.Height = 86;
            SetupGrid();
            _grid.Dock = DockStyle.Fill;
            Controls.Add(_grid);
            Controls.Add(_banner);
            Controls.Add(panel1);
            panel1.BringToFront();
        }

        private void PositionTopButtons()
        {
            int right = btnAdd.Left - 8;
            _btnPdf.Size = new Size(100, 33);
            _btnOwners.Size = new Size(100, 33);
            _btnPdf.Location = new Point(right - _btnPdf.Width, btnAdd.Top);
            _btnOwners.Location = new Point(_btnPdf.Left - 8 - _btnOwners.Width, btnAdd.Top);
            _btnPdf.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            _btnOwners.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            _btnPdf.BringToFront();
            _btnOwners.BringToFront();
        }

        private void LayoutGrid()
        {
            // Dock Fill — manual layout ki zaroorat nahi
        }

        private void StyleStatCard(Label lbl, string title, string value, Color accent, int x)
        {
            lbl.Text = title + "\nRs. " + value;
            lbl.ForeColor = Color.White;
            lbl.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
            lbl.AutoSize = false;
            lbl.Size = new Size(200, 72);
            lbl.Location = new Point(x, 10);
            lbl.TextAlign = ContentAlignment.MiddleLeft;
            lbl.BackColor = Color.FromArgb(39, 49, 70);
            lbl.Padding = new Padding(14, 8, 14, 8);
            lbl.BorderStyle = BorderStyle.FixedSingle;
            // Title color via Tag for SetBanner
            lbl.Tag = accent;
            _banner.Controls.Add(lbl);
            // Colored left bar
            var bar = new Panel
            {
                BackColor = accent,
                Size = new Size(6, 72),
                Location = new Point(x, 10)
            };
            _banner.Controls.Add(bar);
            bar.BringToFront();
        }

        private static void StyleAction(Guna2Button btn, string text, Color fill, Color fore)
        {
            btn.Text = text;
            btn.Animated = true;
            btn.AutoRoundedCorners = true;
            btn.BorderRadius = 15;
            btn.FillColor = fill;
            btn.ForeColor = fore;
            btn.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        }

        private void SetupGrid()
        {
            var header = new DataGridViewCellStyle
            {
                Alignment = DataGridViewContentAlignment.MiddleLeft,
                BackColor = Color.FromArgb(100, 88, 255),
                Font = new Font("Segoe UI Semibold", 11.25F, FontStyle.Bold),
                ForeColor = Color.White,
                SelectionBackColor = Color.FromArgb(100, 88, 255),
                SelectionForeColor = Color.White,
                WrapMode = DataGridViewTriState.True
            };
            var cell = new DataGridViewCellStyle
            {
                Alignment = DataGridViewContentAlignment.MiddleLeft,
                BackColor = Color.FromArgb(32, 36, 66),
                Font = new Font("Segoe UI Semibold", 11.25F, FontStyle.Bold),
                ForeColor = Color.White,
                SelectionBackColor = Color.FromArgb(60, 70, 110),
                SelectionForeColor = Color.White,
                WrapMode = DataGridViewTriState.False
            };
            var alt = new DataGridViewCellStyle
            {
                BackColor = Color.FromArgb(37, 41, 74),
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 11.25F, FontStyle.Bold),
                SelectionBackColor = Color.FromArgb(60, 70, 110),
                SelectionForeColor = Color.White
            };

            _grid.AllowUserToAddRows = false;
            _grid.AllowUserToDeleteRows = false;
            _grid.ReadOnly = true;
            _grid.MultiSelect = false;
            _grid.RowHeadersVisible = false;
            _grid.BorderStyle = BorderStyle.None;
            _grid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            _grid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None;
            _grid.EnableHeadersVisualStyles = false;
            _grid.BackgroundColor = Color.FromArgb(32, 36, 66);
            _grid.GridColor = Color.FromArgb(50, 56, 90);
            _grid.ColumnHeadersHeight = 42;
            _grid.RowTemplate.Height = 34;
            _grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            _grid.ColumnHeadersDefaultCellStyle = header;
            _grid.DefaultCellStyle = cell;
            _grid.AlternatingRowsDefaultCellStyle = alt;
            _grid.ThemeStyle.BackColor = Color.FromArgb(32, 36, 66);
            _grid.ThemeStyle.GridColor = Color.FromArgb(50, 56, 90);
            _grid.ThemeStyle.HeaderStyle.BackColor = Color.FromArgb(100, 88, 255);
            _grid.ThemeStyle.HeaderStyle.ForeColor = Color.White;
            _grid.ThemeStyle.HeaderStyle.Font = header.Font;
            _grid.ThemeStyle.HeaderStyle.Height = 42;
            _grid.ThemeStyle.RowsStyle.BackColor = Color.FromArgb(32, 36, 66);
            _grid.ThemeStyle.RowsStyle.ForeColor = Color.White;
            _grid.ThemeStyle.RowsStyle.Font = cell.Font;
            _grid.ThemeStyle.RowsStyle.Height = 34;
            _grid.ThemeStyle.RowsStyle.SelectionBackColor = Color.FromArgb(60, 70, 110);
            _grid.ThemeStyle.RowsStyle.SelectionForeColor = Color.White;
            _grid.ThemeStyle.AlternatingRowsStyle.BackColor = Color.FromArgb(37, 41, 74);
            _grid.ThemeStyle.AlternatingRowsStyle.ForeColor = Color.White;
            _grid.ThemeStyle.ReadOnly = true;

            _grid.CellDoubleClick += (s, e) =>
            {
                if (e.RowIndex < 0 || _grid.CurrentRow == null) return;
                object idObj = _grid.CurrentRow.Cells["id"].Value;
                if (idObj == null || idObj == DBNull.Value) return;
                using (var f = new frmBulMalEntryAdd { Id = Convert.ToInt32(idObj) })
                    f.ShowDialog(FindForm());
                LoadData();
            };
            _grid.CellFormatting += Grid_CellFormatting;
            _grid.DataBindingComplete += (s, e) => FormatColumns();
        }

        private void Grid_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            string col = _grid.Columns[e.ColumnIndex].Name;
            if (col == "Type" && e.Value != null)
            {
                string t = e.Value.ToString();
                e.CellStyle.ForeColor = string.Equals(t, "Out", StringComparison.OrdinalIgnoreCase)
                    ? Color.FromArgb(255, 120, 120)
                    : Color.FromArgb(120, 255, 170);
                e.CellStyle.Font = new Font("Segoe UI Semibold", 11.25F, FontStyle.Bold);
            }
            if (col == "Note")
                e.CellStyle.ForeColor = Color.FromArgb(255, 140, 140);
            if (col == "Amount" && e.Value != null && e.Value != DBNull.Value)
            {
                if (decimal.TryParse(e.Value.ToString(), out decimal amt))
                    e.Value = amt.ToString("#,##0.##");
                e.FormattingApplied = true;
                e.CellStyle.Alignment = DataGridViewContentAlignment.MiddleRight;
            }
            if (col == "Sr")
                e.Value = (e.RowIndex + 1).ToString();
        }

        private void FormatColumns()
        {
            if (_grid.Columns.Contains("id"))
                _grid.Columns["id"].Visible = false;

            // Amount aur Note door — fixed widths, Fill sirf Note pe
            _grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
            SetFixed("Sr", "Sr#", 55);
            SetFixed("Owner", "Owner", 160);
            SetFixed("Date", "Date", 110);
            SetFixed("Type", "In/Out", 80);
            SetFixed("Amount", "Amount", 120);
            if (_grid.Columns.Contains("Note"))
            {
                var note = _grid.Columns["Note"];
                note.HeaderText = "Note";
                note.AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
                note.MinimumWidth = 200;
                note.DefaultCellStyle.Padding = new Padding(16, 0, 4, 0); // Amount se door
            }
            if (_grid.Columns.Contains("Amount"))
            {
                _grid.Columns["Amount"].DefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleRight;
                _grid.Columns["Amount"].DefaultCellStyle.Padding = new Padding(4, 0, 20, 0);
            }
        }

        private void SetFixed(string name, string header, int width)
        {
            if (!_grid.Columns.Contains(name)) return;
            var c = _grid.Columns[name];
            c.HeaderText = header;
            c.AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
            c.Width = width;
            c.MinimumWidth = width;
        }

        private void SetCol(string name, string header, float weight)
        {
            if (!_grid.Columns.Contains(name)) return;
            _grid.Columns[name].HeaderText = header;
            _grid.Columns[name].FillWeight = weight;
            _grid.Columns[name].MinimumWidth = 60;
        }

        private void OpenEntry()
        {
            using (var f = new frmBulMalEntryAdd())
                f.ShowDialog(FindForm());
            LoadData();
        }

        private void DeleteSelected()
        {
            if (_grid.CurrentRow == null) return;
            object idObj = _grid.CurrentRow.Cells["id"].Value;
            if (idObj == null || idObj == DBNull.Value) return;
            if (MessageBox.Show("Is entry ko delete karein?", "Bul Mal",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;
            MainClass.DataInsertUpdateDelete("DELETE FROM BulMalEntry WHERE id=@id",
                new Hashtable { { "@id", Convert.ToInt32(idObj) } });
            LoadData();
        }

        private void LoadData()
        {
            string q = (txtSearch.Text ?? "").Trim();
            string sql = @"
SELECT e.id AS id,
       '' AS Sr,
       IFNULL(o.Name,'') AS Owner,
       IFNULL(e.Date,'') AS Date,
       IFNULL(e.Type,'In') AS Type,
       IFNULL(e.Amount,0) AS Amount,
       IFNULL(e.Note,'') AS Note
FROM BulMalEntry e
LEFT JOIN BulMalOwner o ON o.id = e.OwnerId
WHERE 1=1";
            var ht = new Hashtable();
            if (!string.IsNullOrEmpty(q))
            {
                sql += " AND (lower(trim(IFNULL(o.Name,''))) = lower(@q) OR IFNULL(e.Note,'') LIKE @like)";
                ht["@q"] = q;
                ht["@like"] = "%" + q + "%";
            }
            if (_chkDate.Checked)
            {
                sql += " AND date(e.Date) >= date(@from) AND date(e.Date) <= date(@to)";
                ht["@from"] = _from.Value.ToString("yyyy-MM-dd");
                ht["@to"] = _to.Value.ToString("yyyy-MM-dd");
            }
            sql += " ORDER BY date(e.Date) DESC, e.id DESC";

            _currentRows = MainClass.ExecuteSelectQuery(sql, ht.Count == 0 ? null : ht) ?? new DataTable();
            _grid.DataSource = _currentRows;
            UpdateTotals(q);
        }

        private void UpdateTotals(string ownerExact)
        {
            string filter = " WHERE 1=1";
            var ht = new Hashtable();
            if (!string.IsNullOrEmpty(ownerExact))
            {
                // Exact owner match for banner (same as search exact)
                DataTable own = MainClass.ExecuteSelectQuery(
                    "SELECT id FROM BulMalOwner WHERE lower(trim(Name))=lower(@q) LIMIT 1",
                    new Hashtable { { "@q", ownerExact } });
                if (own != null && own.Rows.Count > 0)
                {
                    filter += " AND OwnerId=@oid";
                    ht["@oid"] = Convert.ToInt32(own.Rows[0][0]);
                }
                else
                {
                    // note search — totals for filtered grid rows
                    double gin = 0, gout = 0;
                    foreach (DataRow r in _currentRows.Rows)
                    {
                        double a = r["Amount"] == DBNull.Value ? 0 : Convert.ToDouble(r["Amount"]);
                        if (string.Equals(r["Type"]?.ToString(), "Out", StringComparison.OrdinalIgnoreCase))
                            gout += a;
                        else
                            gin += a;
                    }
                    SetBanner(gin, gout);
                    return;
                }
            }
            if (_chkDate.Checked)
            {
                filter += " AND date(Date) >= date(@from) AND date(Date) <= date(@to)";
                ht["@from"] = _from.Value.ToString("yyyy-MM-dd");
                ht["@to"] = _to.Value.ToString("yyyy-MM-dd");
            }

            double tin = Scalar("SELECT IFNULL(SUM(Amount),0) FROM BulMalEntry" + filter + " AND lower(IFNULL(Type,''))='in'", ht);
            double tout = Scalar("SELECT IFNULL(SUM(Amount),0) FROM BulMalEntry" + filter + " AND lower(IFNULL(Type,''))='out'", ht);
            SetBanner(tin, tout);
        }

        private void SetBanner(double tin, double tout)
        {
            _lblIn.Text = "TOTAL IN\nRs. " + tin.ToString("#,##0.##");
            _lblOut.Text = "TOTAL OUT\nRs. " + tout.ToString("#,##0.##");
            _lblBalance.Text = "TOTAL BALANCE\nRs. " + (tin - tout).ToString("#,##0.##");
            if (_lblIn.Tag is Color cIn) _lblIn.ForeColor = cIn;
            if (_lblOut.Tag is Color cOut) _lblOut.ForeColor = cOut;
            if (_lblBalance.Tag is Color cBal) _lblBalance.ForeColor = cBal;
        }

        private static double Scalar(string sql, Hashtable ht)
        {
            DataTable dt = MainClass.ExecuteSelectQuery(sql, ht.Count == 0 ? null : ht);
            if (dt == null || dt.Rows.Count == 0 || dt.Rows[0][0] == DBNull.Value) return 0;
            return Convert.ToDouble(dt.Rows[0][0]);
        }

        // ── VIP PDF (Stock/Closing style raw PDF) ─────────────────────────────

        private void ExportPdf()
        {
            if (_currentRows == null || _currentRows.Rows.Count == 0)
            {
                MessageBox.Show("PDF ke liye koi entry nahi.", "VIP PDF",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            using (var sfd = new SaveFileDialog())
            {
                sfd.Filter = "PDF File (*.pdf)|*.pdf";
                sfd.Title = "Bul Mal VIP PDF";
                sfd.FileName = "BulMal_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".pdf";
                if (sfd.ShowDialog() != DialogResult.OK) return;

                string sub = "All Entries";
                if (!string.IsNullOrWhiteSpace(txtSearch.Text))
                    sub = "Filter: " + txtSearch.Text.Trim();
                if (_chkDate.Checked)
                    sub += $"  |  {_from.Value:dd-MMM-yyyy} to {_to.Value:dd-MMM-yyyy}";

                WriteBulMalPdf(sfd.FileName, BuildPdfRows(), sub);
                MessageBox.Show("VIP PDF ban gayi.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                Process.Start(new ProcessStartInfo { FileName = sfd.FileName, UseShellExecute = true });
            }
        }

        private enum BmKind { Section, Header, Normal, Bold, Empty }
        private sealed class BmRow
        {
            public BmKind Kind;
            public string[] Cells;
            public bool IsOut;
        }

        private List<BmRow> BuildPdfRows()
        {
            var rows = new List<BmRow>();
            double tin = 0, tout = 0;
            foreach (DataRow r in _currentRows.Rows)
            {
                double a = r["Amount"] == DBNull.Value ? 0 : Convert.ToDouble(r["Amount"]);
                if (string.Equals(r["Type"]?.ToString(), "Out", StringComparison.OrdinalIgnoreCase))
                    tout += a;
                else
                    tin += a;
            }

            rows.Add(new BmRow { Kind = BmKind.Section, Cells = new[] { "TOTAL SUMMARY" } });
            rows.Add(new BmRow { Kind = BmKind.Header, Cells = new[] { "Total In", "Total Out", "Total Balance", "", "", "" } });
            rows.Add(new BmRow
            {
                Kind = BmKind.Bold,
                Cells = new[]
                {
                    "Rs. " + tin.ToString("#,##0.##", CultureInfo.InvariantCulture),
                    "Rs. " + tout.ToString("#,##0.##", CultureInfo.InvariantCulture),
                    "Rs. " + (tin - tout).ToString("#,##0.##", CultureInfo.InvariantCulture),
                    "", "", ""
                }
            });
            rows.Add(new BmRow { Kind = BmKind.Empty, Cells = new[] { "" } });
            rows.Add(new BmRow { Kind = BmKind.Section, Cells = new[] { "ALL ENTRIES" } });
            rows.Add(new BmRow { Kind = BmKind.Header, Cells = new[] { "Sr", "Owner", "Date", "Type", "Amount", "Note" } });

            // Chronological for report
            var list = new List<DataRow>();
            foreach (DataRow r in _currentRows.Rows) list.Add(r);
            list.Reverse();
            int sr = 1;
            foreach (DataRow r in list)
            {
                bool isOut = string.Equals(r["Type"]?.ToString(), "Out", StringComparison.OrdinalIgnoreCase);
                string amt = "Rs. " + Convert.ToDouble(r["Amount"] == DBNull.Value ? 0 : r["Amount"])
                    .ToString("#,##0.##", CultureInfo.InvariantCulture);
                string date = r["Date"]?.ToString() ?? "";
                if (DateTime.TryParse(date, out DateTime d)) date = d.ToString("dd-MMM-yy");
                rows.Add(new BmRow
                {
                    Kind = BmKind.Normal,
                    IsOut = isOut,
                    Cells = new[]
                    {
                        sr.ToString(),
                        r["Owner"]?.ToString() ?? "",
                        date,
                        r["Type"]?.ToString() ?? "",
                        amt,
                        r["Note"]?.ToString() ?? ""
                    }
                });
                sr++;
            }
            return rows;
        }

        private sealed class BmCol { public float Left; public float Width; public bool Right; }
        // Landscape columns — Amount aur Note ke beech clear gap
        private static readonly BmCol[] BmCols =
        {
            new BmCol { Left = 30f,  Width = 30f,  Right = false }, // Sr
            new BmCol { Left = 65f,  Width = 140f, Right = false }, // Owner
            new BmCol { Left = 215f, Width = 75f,  Right = false }, // Date
            new BmCol { Left = 300f, Width = 45f,  Right = false }, // Type
            new BmCol { Left = 355f, Width = 95f,  Right = true  }, // Amount (ends ~450)
            new BmCol { Left = 470f, Width = 340f, Right = false }  // Note — door
        };

        private const float BmW = 842f, BmH = 595f, BmM = 26f, BmRowH = 14f, BmBanner = 58f, BmFoot = 28f;
        private const string CNavy = "0.098 0.153 0.318";
        private const string CNavyLt = "0.152 0.239 0.462";
        private const string CBlue = "0.180 0.459 0.714";
        private const string CGold = "0.831 0.686 0.216";
        private const string CZebra = "0.945 0.957 0.972";
        private const string CLine = "0.796 0.831 0.871";
        private const string CText = "0.129 0.145 0.180";
        private const string CWhite = "1 1 1";
        private const string CRed = "0.698 0.114 0.153";
        private const string CGreen = "0.106 0.541 0.286";
        private const string CMuted = "0.451 0.482 0.529";

        private static void WriteBulMalPdf(string path, List<BmRow> rows, string subtitle)
        {
            var pages = new List<StringBuilder>();
            StringBuilder page = StartPage(pages, subtitle);
            float tableW = BmW - BmM * 2f;
            float y = BmH - BmBanner - 20f;
            BmRow lastHeader = null;
            bool zebra = false;

            foreach (BmRow row in rows)
            {
                if (y < BmFoot + 24f)
                {
                    page = StartPage(pages, subtitle);
                    y = BmH - BmBanner - 20f;
                    zebra = false;
                    if (lastHeader != null)
                    {
                        DrawRow(page, lastHeader, y, tableW, false);
                        y -= BmRowH;
                    }
                }
                if (row.Kind == BmKind.Header) { lastHeader = row; zebra = false; }
                if (row.Kind == BmKind.Empty) { y -= BmRowH * 0.65f; continue; }
                if (row.Kind == BmKind.Section) y -= 5f;
                DrawRow(page, row, y, tableW, row.Kind == BmKind.Normal && zebra);
                if (row.Kind == BmKind.Normal) zebra = !zebra;
                y -= BmRowH;
            }
            for (int i = 0; i < pages.Count; i++) DrawFooter(pages[i], i + 1, pages.Count);
            File.WriteAllBytes(path, BuildPdf(pages));
        }

        private static StringBuilder StartPage(List<StringBuilder> pages, string subtitle)
        {
            var page = new StringBuilder();
            pages.Add(page);
            Fill(page, 0, BmH - BmBanner, BmW, BmBanner, CNavy);
            Fill(page, 0, BmH - BmBanner, BmW, 5f, CGold);
            // Gold accent strip at bottom of banner
            Fill(page, 0, BmH - BmBanner - 2f, BmW, 2f, CGold);
            TextPdf(page, "/F2", 18f, BmM + 10f, BmH - 24f, "ZAIB PETROLEUM SERVICE", CWhite);
            TextPdf(page, "/F1", 11f, BmM + 10f, BmH - 44f, "Bul Mal  |  VIP Report  |  Total In / Total Out / Total Balance", CGold);
            string sub = Fit(subtitle, BmW - BmM * 2f - 24f, 9f);
            TextPdf(page, "/F2", 10f, BmW - BmM - 10f - Measure(sub, 10f), BmH - 26f, sub, CWhite);
            string stamp = "Printed: " + DateTime.Now.ToString("dd-MMM-yyyy  hh:mm tt");
            TextPdf(page, "/F1", 8f, BmW - BmM - 10f - Measure(stamp, 8f), BmH - 44f, stamp, CLine);
            return page;
        }

        private static void DrawFooter(StringBuilder page, int n, int total)
        {
            Line(page, BmM, BmFoot + 12f, BmW - BmM, BmFoot + 12f, CLine, 0.6f);
            Fill(page, 0, 0, BmW, 5f, CNavy);
            TextPdf(page, "/F1", 8f, BmM, BmFoot, "ZAIB PETROLEUM SERVICE  -  Bul Mal  |  Developed by Irtaza Hussain", CMuted);
            string pt = $"Page {n} of {total}";
            TextPdf(page, "/F2", 8f, BmW - BmM - Measure(pt, 8f), BmFoot, pt, CNavy);
        }

        private static void DrawRow(StringBuilder page, BmRow row, float y, float tableW, bool zebra)
        {
            if (row.Cells == null || row.Cells.Length == 0) return;
            float bottom = y - 4f;
            if (row.Kind == BmKind.Section)
            {
                Fill(page, BmM, bottom, tableW, BmRowH, CNavyLt);
                Fill(page, BmM, bottom, 4f, BmRowH, CGold);
                TextPdf(page, "/F2", 10f, BmM + 12f, y, row.Cells[0], CWhite);
                return;
            }
            if (row.Kind == BmKind.Header)
            {
                Fill(page, BmM, bottom, tableW, BmRowH, CBlue);
                for (int i = 0; i < row.Cells.Length && i < BmCols.Length; i++)
                    DrawCell(page, row.Cells[i], i, y, "/F2", 9f, CWhite);
                return;
            }
            if (row.Kind == BmKind.Bold)
            {
                Fill(page, BmM, bottom, tableW, BmRowH + 4f, CNavy);
                // Total In green, Total Out red, Total Balance gold
                string[] tones = { CGreen, CRed, CGold, CWhite, CWhite, CWhite };
                for (int i = 0; i < row.Cells.Length && i < BmCols.Length; i++)
                    DrawCell(page, row.Cells[i], i, y, "/F2", 10.5f, tones[i]);
                return;
            }
            if (zebra) Fill(page, BmM, bottom, tableW, BmRowH, CZebra);
            Line(page, BmM, bottom, BmM + tableW, bottom, CLine, 0.4f);
            for (int i = 0; i < row.Cells.Length && i < BmCols.Length; i++)
            {
                string color = CText;
                if (i == 3) color = row.IsOut ? CRed : CGreen;
                if (i == 5) color = CRed;
                DrawCell(page, row.Cells[i], i, y, "/F1", 9f, color);
            }
        }

        private static void DrawCell(StringBuilder page, string text, int i, float y, string font, float size, string color)
        {
            if (string.IsNullOrEmpty(text)) return;
            text = Fit(text, BmCols[i].Width - 4f, size);
            float x = BmCols[i].Left;
            if (BmCols[i].Right) x = BmCols[i].Left + BmCols[i].Width - Measure(text, size);
            TextPdf(page, BmCols[i].Right ? "/F2" : font, size, x, y, text, color);
        }

        private static void Fill(StringBuilder p, float x, float y, float w, float h, string c) =>
            p.Append(c).Append(" rg ").Append(F(x)).Append(' ').Append(F(y)).Append(' ')
             .Append(F(w)).Append(' ').Append(F(h)).AppendLine(" re f");

        private static void Line(StringBuilder p, float x1, float y1, float x2, float y2, string c, float w) =>
            p.Append(c).Append(" RG ").Append(F(w)).Append(" w ")
             .Append(F(x1)).Append(' ').Append(F(y1)).Append(" m ")
             .Append(F(x2)).Append(' ').Append(F(y2)).AppendLine(" l S");

        private static void TextPdf(StringBuilder p, string font, float size, float x, float y, string text, string c) =>
            p.Append(c).Append(" rg BT ").Append(font).Append(' ').Append(F(size))
             .Append(" Tf 1 0 0 1 ").Append(F(x)).Append(' ').Append(F(y))
             .Append(" Tm (").Append(Escape(text)).AppendLine(") Tj ET");

        private static string F(float v) => v.ToString("0.##", CultureInfo.InvariantCulture);
        private static float Measure(string t, float size) => (t?.Length ?? 0) * size * 0.5f;
        private static string Fit(string t, float maxW, float size)
        {
            if (string.IsNullOrEmpty(t)) return "";
            if (Measure(t, size) <= maxW) return t;
            while (t.Length > 1 && Measure(t + "…", size) > maxW) t = t.Substring(0, t.Length - 1);
            return t + "…";
        }
        private static string Escape(string t) =>
            (t ?? "").Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");

        private static byte[] BuildPdf(List<StringBuilder> pages)
        {
            var objects = new List<byte[]>();
            objects.Add(Enc("<< /Type /Catalog /Pages 2 0 R >>"));
            var kids = new StringBuilder("<< /Type /Pages /Count ");
            kids.Append(pages.Count).Append(" /Kids [");
            int pageObjStart = 3;
            int contentStart = pageObjStart + pages.Count;
            int font1 = contentStart + pages.Count;
            int font2 = font1 + 1;
            for (int i = 0; i < pages.Count; i++)
                kids.Append(pageObjStart + i).Append(" 0 R ");
            kids.Append("] >>");
            objects.Add(Enc(kids.ToString()));

            for (int i = 0; i < pages.Count; i++)
            {
                string pageDict = $"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {F(BmW)} {F(BmH)}] " +
                                  $"/Contents {contentStart + i} 0 R /Resources << /Font << /F1 {font1} 0 R /F2 {font2} 0 R >> >> >>";
                objects.Add(Enc(pageDict));
            }
            for (int i = 0; i < pages.Count; i++)
            {
                byte[] stream = Enc(pages[i].ToString());
                var sb = new StringBuilder();
                sb.Append("<< /Length ").Append(stream.Length).Append(" >>\nstream\n");
                var full = new List<byte>();
                full.AddRange(Enc(sb.ToString()));
                full.AddRange(stream);
                full.AddRange(Enc("\nendstream"));
                objects.Add(full.ToArray());
            }
            objects.Add(Enc("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"));
            objects.Add(Enc("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"));

            using (var ms = new MemoryStream())
            {
                byte[] header = Enc("%PDF-1.4\n");
                ms.Write(header, 0, header.Length);
                var offsets = new List<long> { 0 };
                for (int i = 0; i < objects.Count; i++)
                {
                    offsets.Add(ms.Position);
                    byte[] objHead = Enc($"{i + 1} 0 obj\n");
                    ms.Write(objHead, 0, objHead.Length);
                    ms.Write(objects[i], 0, objects[i].Length);
                    byte[] objTail = Enc("\nendobj\n");
                    ms.Write(objTail, 0, objTail.Length);
                }
                long xref = ms.Position;
                var xrefSb = new StringBuilder();
                xrefSb.Append("xref\n0 ").Append(objects.Count + 1).Append("\n");
                xrefSb.Append("0000000000 65535 f \n");
                for (int i = 1; i < offsets.Count; i++)
                    xrefSb.Append(offsets[i].ToString("0000000000")).Append(" 00000 n \n");
                xrefSb.Append("trailer\n<< /Size ").Append(objects.Count + 1)
                      .Append(" /Root 1 0 R >>\nstartxref\n").Append(xref).Append("\n%%EOF");
                byte[] xrefBytes = Enc(xrefSb.ToString());
                ms.Write(xrefBytes, 0, xrefBytes.Length);
                return ms.ToArray();
            }
        }

        private static byte[] Enc(string s) => Encoding.ASCII.GetBytes(s);
    }
}
