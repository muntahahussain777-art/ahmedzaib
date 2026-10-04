using System;
using System.Collections;
using System.Data;
using System.Drawing;
using System.Windows.Forms;
using Guna.UI2.WinForms;

namespace ZaibPetroleumService.Model
{
    public class frmBulMalEntryAdd : Form
    {
        private readonly Panel _scroll = new Panel();
        private readonly ComboBox _cbOwner = new ComboBox();
        private readonly DateTimePicker _date = new DateTimePicker();
        private readonly ComboBox _cbType = new ComboBox();
        private readonly Guna2TextBox _txtAmount = new Guna2TextBox();
        private readonly Guna2TextBox _txtNote = new Guna2TextBox();
        private readonly Label _lblIn = new Label();
        private readonly Label _lblOut = new Label();
        private readonly Label _lblBal = new Label();
        private readonly Label _lblStatus = new Label();
        public int Id;

        public frmBulMalEntryAdd()
        {
            Text = "Add Bul Mal Entry";
            Size = new Size(560, 520);
            MinimumSize = new Size(520, 420);
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.Sizable;
            MaximizeBox = true;
            MinimizeBox = false;
            BackColor = Color.FromArgb(28, 32, 56);
            KeyPreview = true;
            BuildUi();
            Load += (s, e) =>
            {
                Text = Id > 0 ? "Update Bul Mal Entry" : "Add Bul Mal Entry";
                LoadOwners();
                if (Id > 0) LoadRecord();
                else _date.Value = DateTime.Today;
                RefreshTotals();
            };
            KeyDown += (s, e) =>
            {
                if (e.Control && e.KeyCode == Keys.S) { Save(); e.Handled = true; }
                if (e.KeyCode == Keys.Escape) Close();
            };
        }

        private void BuildUi()
        {
            var banner = new Panel
            {
                Dock = DockStyle.Top,
                Height = 58,
                BackColor = Color.FromArgb(18, 24, 48)
            };
            banner.Controls.Add(new Panel
            {
                Dock = DockStyle.Bottom,
                Height = 4,
                BackColor = Color.FromArgb(212, 175, 55)
            });
            banner.Controls.Add(new Label
            {
                Text = "BUL MAL  •  ENTRY FORM",
                ForeColor = Color.FromArgb(212, 175, 55),
                Font = new Font("Segoe UI Semibold", 15F, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(20, 14)
            });
            Controls.Add(banner);

            // Scrollable body — neeche buttons tak scroll
            _scroll.Dock = DockStyle.Fill;
            _scroll.AutoScroll = true;
            _scroll.BackColor = Color.FromArgb(28, 32, 56);
            _scroll.Padding = new Padding(0, 0, 8, 0);
            Controls.Add(_scroll);
            _scroll.BringToFront();
            banner.BringToFront();

            int y = 16;
            int left = 24;
            int fieldW = 480;

            AddOnScroll(MakeLabel("Owner *", left, y)); y += 26;
            StyleCombo(_cbOwner);
            _cbOwner.Location = new Point(left, y);
            _cbOwner.Size = new Size(fieldW, 34);
            _cbOwner.SelectedIndexChanged += (s, e) => RefreshTotals();
            _scroll.Controls.Add(_cbOwner); y += 48;

            AddOnScroll(MakeLabel("Date", left, y)); y += 26;
            _date.Format = DateTimePickerFormat.Custom;
            _date.CustomFormat = "dd-MMM-yyyy";
            _date.Font = new Font("Segoe UI Semibold", 12F);
            _date.Location = new Point(left, y);
            _date.Size = new Size(220, 32);
            _scroll.Controls.Add(_date); y += 48;

            AddOnScroll(MakeLabel("In / Out *", left, y)); y += 26;
            StyleCombo(_cbType);
            _cbType.Items.AddRange(new object[] { "In", "Out" });
            _cbType.SelectedIndex = 0;
            _cbType.Location = new Point(left, y);
            _cbType.Size = new Size(220, 34);
            _scroll.Controls.Add(_cbType); y += 48;

            AddOnScroll(MakeLabel("Amount *", left, y)); y += 26;
            StyleText(_txtAmount);
            _txtAmount.PlaceholderText = "Amount likhein";
            _txtAmount.Location = new Point(left, y);
            _txtAmount.Size = new Size(220, 42);
            _scroll.Controls.Add(_txtAmount); y += 56;

            AddOnScroll(MakeLabel("Note", left, y)); y += 26;
            StyleText(_txtNote);
            _txtNote.PlaceholderText = "Note (optional)…";
            _txtNote.Location = new Point(left, y);
            _txtNote.Size = new Size(fieldW, 42);
            _scroll.Controls.Add(_txtNote); y += 58;

            var strip = new Panel
            {
                Location = new Point(left, y),
                Size = new Size(fieldW, 64),
                BackColor = Color.FromArgb(18, 24, 48)
            };
            StyleMini(_lblIn, "TOTAL IN\n0", Color.FromArgb(46, 204, 113), 14);
            StyleMini(_lblOut, "TOTAL OUT\n0", Color.FromArgb(231, 76, 60), 175);
            StyleMini(_lblBal, "TOTAL BALANCE\n0", Color.FromArgb(212, 175, 55), 340);
            strip.Controls.Add(_lblIn);
            strip.Controls.Add(_lblOut);
            strip.Controls.Add(_lblBal);
            _scroll.Controls.Add(strip); y += 80;

            _lblStatus.ForeColor = Color.FromArgb(120, 255, 170);
            _lblStatus.Font = new Font("Segoe UI Semibold", 9.5F);
            _lblStatus.AutoSize = true;
            _lblStatus.Location = new Point(left, y);
            _lblStatus.Text = "Neeche scroll karke Save button dekhein";
            _scroll.Controls.Add(_lblStatus); y += 30;

            var btnSave = new Guna2Button
            {
                Text = "Save Entry  (Ctrl+S)",
                Location = new Point(left, y),
                Size = new Size(260, 48),
                BorderRadius = 14,
                FillColor = Color.FromArgb(212, 175, 55),
                ForeColor = Color.FromArgb(28, 32, 56),
                Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold),
                Animated = true
            };
            btnSave.Click += (s, e) => Save();
            _scroll.Controls.Add(btnSave);

            var btnClose = new Guna2Button
            {
                Text = "Close",
                Location = new Point(left + 280, y),
                Size = new Size(140, 48),
                BorderRadius = 14,
                FillColor = Color.FromArgb(60, 70, 100),
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 12F, FontStyle.Bold)
            };
            btnClose.Click += (s, e) => Close();
            _scroll.Controls.Add(btnClose);

            // Extra bottom space so scroll clearly reaches buttons
            y += 70;
            _scroll.Controls.Add(new Panel
            {
                Location = new Point(0, y),
                Size = new Size(10, 40),
                BackColor = Color.Transparent
            });
        }

        private void AddOnScroll(Control c) => _scroll.Controls.Add(c);

        private static Label MakeLabel(string text, int x, int y) => new Label
        {
            Text = text,
            ForeColor = Color.White,
            Font = new Font("Segoe UI Semibold", 11F),
            Location = new Point(x, y),
            AutoSize = true
        };

        private static void StyleMini(Label lbl, string text, Color c, int x)
        {
            lbl.Text = text;
            lbl.ForeColor = c;
            lbl.Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);
            lbl.AutoSize = false;
            lbl.Size = new Size(150, 52);
            lbl.Location = new Point(x, 6);
            lbl.TextAlign = ContentAlignment.MiddleLeft;
        }

        private static void StyleCombo(ComboBox cb)
        {
            cb.DropDownStyle = ComboBoxStyle.DropDownList;
            cb.FlatStyle = FlatStyle.Flat;
            cb.BackColor = Color.FromArgb(37, 41, 74);
            cb.ForeColor = Color.White;
            cb.Font = new Font("Segoe UI Semibold", 12F);
        }

        private static void StyleText(Guna2TextBox t)
        {
            t.BorderRadius = 12;
            t.FillColor = Color.FromArgb(37, 41, 74);
            t.ForeColor = Color.White;
            t.Font = new Font("Segoe UI Semibold", 12F);
            t.BorderColor = Color.FromArgb(100, 88, 255);
            t.PlaceholderForeColor = Color.FromArgb(140, 150, 170);
        }

        private void LoadOwners()
        {
            DataTable dt = MainClass.ExecuteSelectQuery(
                "SELECT id, Name FROM BulMalOwner ORDER BY Name COLLATE NOCASE", null);
            _cbOwner.DisplayMember = "Name";
            _cbOwner.ValueMember = "id";
            _cbOwner.DataSource = dt;
            if (dt == null || dt.Rows.Count == 0)
                MessageBox.Show("Pehle Owners se name banao.", "Bul Mal");
        }

        private void LoadRecord()
        {
            DataTable dt = MainClass.ExecuteSelectQuery(
                "SELECT * FROM BulMalEntry WHERE id=@id", new Hashtable { { "@id", Id } });
            if (dt.Rows.Count == 0) return;
            DataRow r = dt.Rows[0];
            if (r["OwnerId"] != DBNull.Value)
                _cbOwner.SelectedValue = Convert.ToInt32(r["OwnerId"]);
            if (DateTime.TryParse(r["Date"]?.ToString(), out DateTime d))
                _date.Value = d;
            string t = r["Type"]?.ToString() ?? "In";
            _cbType.SelectedItem = string.Equals(t, "Out", StringComparison.OrdinalIgnoreCase) ? "Out" : "In";
            _txtAmount.Text = r["Amount"]?.ToString() ?? "";
            _txtNote.Text = r["Note"]?.ToString() ?? "";
        }

        private void RefreshTotals()
        {
            if (_cbOwner.SelectedValue == null || _cbOwner.SelectedValue == DBNull.Value)
            {
                _lblIn.Text = "TOTAL IN\n0";
                _lblOut.Text = "TOTAL OUT\n0";
                _lblBal.Text = "TOTAL BALANCE\n0";
                return;
            }
            int oid = Convert.ToInt32(_cbOwner.SelectedValue);
            double tin = Scalar("SELECT IFNULL(SUM(Amount),0) FROM BulMalEntry WHERE OwnerId=@id AND lower(IFNULL(Type,''))='in'", oid);
            double tout = Scalar("SELECT IFNULL(SUM(Amount),0) FROM BulMalEntry WHERE OwnerId=@id AND lower(IFNULL(Type,''))='out'", oid);
            _lblIn.Text = "TOTAL IN\nRs. " + tin.ToString("#,##0.##");
            _lblOut.Text = "TOTAL OUT\nRs. " + tout.ToString("#,##0.##");
            _lblBal.Text = "TOTAL BALANCE\nRs. " + (tin - tout).ToString("#,##0.##");
        }

        private static double Scalar(string sql, int id)
        {
            DataTable dt = MainClass.ExecuteSelectQuery(sql, new Hashtable { { "@id", id } });
            if (dt == null || dt.Rows.Count == 0 || dt.Rows[0][0] == DBNull.Value) return 0;
            return Convert.ToDouble(dt.Rows[0][0]);
        }

        private void Save()
        {
            if (_cbOwner.SelectedValue == null || _cbOwner.SelectedValue == DBNull.Value)
            {
                MessageBox.Show("Owner select karein.", "Bul Mal");
                return;
            }
            if (!decimal.TryParse(_txtAmount.Text.Replace(",", ""), out decimal amt) || amt <= 0)
            {
                MessageBox.Show("Valid amount likhein.", "Bul Mal");
                return;
            }

            var ht = new Hashtable
            {
                { "@oid", Convert.ToInt32(_cbOwner.SelectedValue) },
                { "@date", _date.Value.ToString("yyyy-MM-dd") },
                { "@type", _cbType.SelectedItem?.ToString() ?? "In" },
                { "@amt", amt },
                { "@note", (_txtNote.Text ?? "").Trim() },
                { "@id", Id }
            };

            string qry = Id == 0
                ? "INSERT INTO BulMalEntry (OwnerId, Date, Type, Amount, Note) VALUES (@oid, @date, @type, @amt, @note)"
                : "UPDATE BulMalEntry SET OwnerId=@oid, Date=@date, Type=@type, Amount=@amt, Note=@note WHERE id=@id";

            if (MainClass.DataInsertUpdateDelete(qry, ht) <= 0)
            {
                MessageBox.Show("Save fail.", "Bul Mal");
                return;
            }

            if (Id > 0)
            {
                Close();
                return;
            }

            _lblStatus.Text = "Saved — neeche scroll / Save dubara.";
            _txtAmount.Clear();
            _txtNote.Clear();
            RefreshTotals();
            _txtAmount.Focus();
        }
    }
}
