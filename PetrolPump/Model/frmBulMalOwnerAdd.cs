using System;
using System.Collections;
using System.Data;
using System.Drawing;
using System.Windows.Forms;
using Guna.UI2.WinForms;

namespace ZaibPetroleumService.Model
{
    public class frmBulMalOwnerAdd : Form
    {
        private readonly Guna2TextBox _txtName = new Guna2TextBox();
        private readonly Guna2DataGridView _grid = new Guna2DataGridView();
        private readonly Label _title = new Label();
        public int Id;

        public frmBulMalOwnerAdd()
        {
            Text = "Bul Mal Owners";
            Size = new Size(520, 480);
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            BackColor = Color.FromArgb(32, 36, 61);
            BuildUi();
            Load += (s, e) => Reload();
            AcceptButton = null;
            KeyPreview = true;
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
                Height = 56,
                BackColor = Color.FromArgb(26, 39, 68)
            };
            _title.Text = "BUL MAL — OWNERS";
            _title.ForeColor = Color.FromArgb(212, 175, 55);
            _title.Font = new Font("Segoe UI Semibold", 14F, FontStyle.Bold);
            _title.AutoSize = true;
            _title.Location = new Point(18, 14);
            banner.Controls.Add(_title);
            Controls.Add(banner);

            var lbl = new Label
            {
                Text = "Owner Name *",
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 10F),
                Location = new Point(20, 72),
                AutoSize = true
            };
            Controls.Add(lbl);

            StyleTextBox(_txtName);
            _txtName.PlaceholderText = "Name likhein…";
            _txtName.Location = new Point(20, 96);
            _txtName.Size = new Size(330, 38);
            Controls.Add(_txtName);

            var btnSave = MakeBtn("Save Owner", Color.FromArgb(212, 175, 55), Color.FromArgb(32, 36, 61), 360, 96, 120, 38);
            btnSave.Click += (s, e) => Save();
            Controls.Add(btnSave);

            SetupGrid();
            _grid.Location = new Point(20, 150);
            _grid.Size = new Size(460, 270);
            Controls.Add(_grid);

            var tip = new Label
            {
                Text = "Double-click = edit  •  Delete key = remove  •  Ctrl+S = save",
                ForeColor = Color.FromArgb(160, 170, 190),
                Font = new Font("Segoe UI", 8.5F),
                Location = new Point(20, 430),
                AutoSize = true
            };
            Controls.Add(tip);
        }

        private static void StyleTextBox(Guna2TextBox t)
        {
            t.BorderRadius = 10;
            t.FillColor = Color.FromArgb(37, 41, 74);
            t.ForeColor = Color.White;
            t.Font = new Font("Segoe UI Semibold", 11F);
            t.BorderColor = Color.FromArgb(100, 88, 255);
            t.PlaceholderForeColor = Color.FromArgb(140, 150, 170);
        }

        private static Guna2Button MakeBtn(string text, Color fill, Color fore, int x, int y, int w, int h)
        {
            return new Guna2Button
            {
                Text = text,
                Location = new Point(x, y),
                Size = new Size(w, h),
                BorderRadius = 12,
                FillColor = fill,
                ForeColor = fore,
                Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold),
                Animated = true
            };
        }

        private void SetupGrid()
        {
            _grid.AllowUserToAddRows = false;
            _grid.ReadOnly = true;
            _grid.RowHeadersVisible = false;
            _grid.BorderStyle = BorderStyle.None;
            _grid.BackgroundColor = Color.FromArgb(32, 36, 66);
            _grid.EnableHeadersVisualStyles = false;
            _grid.ColumnHeadersHeight = 40;
            _grid.RowTemplate.Height = 32;
            _grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            _grid.ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle
            {
                BackColor = Color.FromArgb(100, 88, 255),
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold)
            };
            _grid.DefaultCellStyle = new DataGridViewCellStyle
            {
                BackColor = Color.FromArgb(32, 36, 66),
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold),
                SelectionBackColor = Color.FromArgb(60, 70, 110),
                SelectionForeColor = Color.White
            };
            _grid.AlternatingRowsDefaultCellStyle = new DataGridViewCellStyle
            {
                BackColor = Color.FromArgb(37, 41, 74),
                ForeColor = Color.White,
                SelectionBackColor = Color.FromArgb(60, 70, 110),
                SelectionForeColor = Color.White
            };
            _grid.CellDoubleClick += (s, e) =>
            {
                if (_grid.CurrentRow == null) return;
                Id = Convert.ToInt32(_grid.CurrentRow.Cells["id"].Value);
                _txtName.Text = _grid.CurrentRow.Cells["Name"].Value?.ToString() ?? "";
                _txtName.Focus();
            };
            _grid.KeyDown += (s, e) =>
            {
                if (e.KeyCode != Keys.Delete || _grid.CurrentRow == null) return;
                int id = Convert.ToInt32(_grid.CurrentRow.Cells["id"].Value);
                if (MessageBox.Show("Owner delete?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                    return;
                try
                {
                    MainClass.DataInsertUpdateDelete("DELETE FROM BulMalOwner WHERE id=@id", new Hashtable { { "@id", id } });
                    Id = 0;
                    _txtName.Clear();
                    Reload();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(ex.Message, "Error");
                }
            };
        }

        private void Save()
        {
            string name = (_txtName.Text ?? "").Trim();
            if (string.IsNullOrEmpty(name))
            {
                MessageBox.Show("Owner name likhein.", "Bul Mal");
                return;
            }
            string date = DateTime.Today.ToString("yyyy-MM-dd");
            if (Id == 0)
            {
                MainClass.DataInsertUpdateDelete(
                    "INSERT INTO BulMalOwner (Name, Date) VALUES (@n, @d)",
                    new Hashtable { { "@n", name }, { "@d", date } });
            }
            else
            {
                MainClass.DataInsertUpdateDelete(
                    "UPDATE BulMalOwner SET Name=@n WHERE id=@id",
                    new Hashtable { { "@n", name }, { "@id", Id } });
            }
            Id = 0;
            _txtName.Clear();
            Reload();
            _txtName.Focus();
        }

        private void Reload()
        {
            DataTable dt = MainClass.ExecuteSelectQuery(
                "SELECT id, Name, Date FROM BulMalOwner ORDER BY Name COLLATE NOCASE", null);
            _grid.DataSource = dt;
            if (_grid.Columns.Contains("id"))
                _grid.Columns["id"].Visible = false;
            if (_grid.Columns.Contains("Name"))
                _grid.Columns["Name"].HeaderText = "Owner Name";
            if (_grid.Columns.Contains("Date"))
                _grid.Columns["Date"].HeaderText = "Created";
        }
    }
}
