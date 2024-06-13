using System;
using System.Collections;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PetrolPump
{
    internal class MainClass
    {
        public static readonly string cons = "Data Source=(LocalDb)\\v11.0;Initial Catalog=islampetrolpump;Integrated Security=True";
        public static SqlConnection con = new SqlConnection(cons);

        public static bool IsValidUser(string user, string pass)
        {
            bool isValid = false;

            string qry = "Select * from tblUser where uUsername = @user and uPass = @pass";
            SqlCommand cmd = new SqlCommand(qry, con);
            cmd.Parameters.AddWithValue("@user", user);
            cmd.Parameters.AddWithValue("@pass", pass);
            DataTable dt = new DataTable();
            SqlDataAdapter da = new SqlDataAdapter(cmd);
            da.Fill(dt);
            if (dt.Rows.Count > 0)
            {
                isValid = true;
            }
            return isValid;
        }

        public static DataTable GetData(string qry)
        {
            DataTable dt = new DataTable();
            try
            {
                SqlCommand cmd = new SqlCommand(qry, MainClass.con);
                cmd.CommandType = System.Data.CommandType.Text;
                SqlDataAdapter da = new SqlDataAdapter(cmd);
                da.Fill(dt);
            }
            catch (Exception ex)
            {
                MainClass.con.Close();
                MessageBox.Show(ex.ToString());
            }
            return dt;
        }

        public static void loadData(string qry, DataGridView gv, ListBox lb)
        {
            try
            {
                SqlCommand cmd = new SqlCommand(qry, MainClass.con);
                SqlDataAdapter da = new SqlDataAdapter(cmd);
                DataTable dt = new DataTable();
                da.Fill(dt);

                for (int i = 0; i < lb.Items.Count; i++)
                {
                    string colName1 = ((DataGridViewColumn)lb.Items[i]).Name;
                    gv.Columns[colName1].DataPropertyName = dt.Columns[i].ToString();
                }
                gv.DataSource = dt;
            }
            catch (Exception ex)
            {
                MainClass.con.Close();
                MessageBox.Show(ex.ToString());
            }
        }

        public static void SrNo(Guna.UI2.WinForms.Guna2DataGridView gv)
        {
            try
            {
                int count = 0;
                foreach (DataGridViewRow row in gv.Rows)
                {
                    count++;
                    row.Cells[0].Value = count;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.ToString());
                con.Close();
            }
        }

        public static int DataInsertUpdateDelete(string qry, Hashtable ht)
        {
            int res = 0;
            try
            {
                SqlCommand cmd = new SqlCommand(qry, MainClass.con);
                cmd.CommandType = CommandType.Text;
                foreach (DictionaryEntry item in ht)
                {
                    cmd.Parameters.AddWithValue(item.Key.ToString(), item.Value);
                }
                MainClass.con.Open();
                res = cmd.ExecuteNonQuery();
                MainClass.con.Close();
            }
            catch (Exception ex)
            {
                MainClass.con.Close();
                MessageBox.Show(ex.Message);
            }
            return res;
        }

        private static Color vColor = Color.FromArgb(245, 29, 70);

        public static bool Validation(Form f)
        {
            bool isValid = true;

            var dynamicalLabels = f.Controls.OfType<Label>().Where(c => c.Tag != null && c.Tag.ToString() == "remove").ToList();
            foreach (var lbl in dynamicalLabels)
            {
                f.Controls.Remove(lbl);
            }

            foreach (Control c in f.Controls)
            {
                if (c is Guna.UI2.WinForms.Guna2Button)
                {
                    // Validation logic for buttons (if any)
                }
                else if (string.IsNullOrEmpty(c.Text))
                {
                    isValid = false;
                    Label lbl = new Label();
                    lbl.Text = "Field is required";
                    lbl.ForeColor = vColor;
                    lbl.Tag = "remove";
                    lbl.Location = new Point(c.Location.X, c.Location.Y + c.Height);
                    f.Controls.Add(lbl);
                }
            }

            return isValid;
        }
        public static void Enable_reset(Form p)
        {
            foreach (Control c in p.Controls)
            {
                if (c is Guna.UI2.WinForms.Guna2TextBox)
                {
                    Guna.UI2.WinForms.Guna2TextBox t = (Guna.UI2.WinForms.Guna2TextBox)c;
                    t.Text = "";
                }
                if (c is Guna.UI2.WinForms.Guna2ComboBox)
                {
                    Guna.UI2.WinForms.Guna2ComboBox cb = (Guna.UI2.WinForms.Guna2ComboBox)c;
                    cb.SelectedIndex = 0;
                    cb.SelectedIndex = 1;
                }
                if (c is Guna.UI2.WinForms.Guna2RadioButton)
                {
                    Guna.UI2.WinForms.Guna2RadioButton rb = (Guna.UI2.WinForms.Guna2RadioButton)c;
                    rb.Checked = false;
                }
                if (c is Guna.UI2.WinForms.Guna2CheckBox)
                {
                    Guna.UI2.WinForms.Guna2CheckBox ck = (Guna.UI2.WinForms.Guna2CheckBox)c;
                    ck.Checked = false;
                }
                if (c is Guna.UI2.WinForms.Guna2DateTimePicker)
                {
                    Guna.UI2.WinForms.Guna2DateTimePicker dp = (Guna.UI2.WinForms.Guna2DateTimePicker)c;
                    dp.Value = DateTime.Today;
                }
                if (c is ListBox)
                {
                    ListBox list = (ListBox)c;
                }
                if (c is NumericUpDown)
                {
                    NumericUpDown cb = (NumericUpDown)c;
                    cb.Value = 0;
                }
                if (c is MaskedTextBox)
                {
                    MaskedTextBox cb = (MaskedTextBox)c;
                    cb.Text = "";
                }
            }
        }
        //next other form code 
        public static int SQL(string qry, Hashtable ht)
        {
            int res = 0;
            try
            {
                SqlCommand cmd = new SqlCommand(qry, con);
                cmd.CommandType = CommandType.Text;
                foreach (DictionaryEntry item in ht)
                {
                    cmd.Parameters.AddWithValue(item.Key.ToString(), item.Value);
                }
                if (con.State == System.Data.ConnectionState.Closed) { con.Open(); }
                res = cmd.ExecuteNonQuery();
                if (con.State == System.Data.ConnectionState.Open) { con.Close(); }

            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.ToString());
                con.Close();
            }
            return res;
        }

        private static void gv_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
        {
            Guna.UI2.WinForms.Guna2DataGridView gv = (Guna.UI2.WinForms.Guna2DataGridView)sender;
            int count = 0;
            foreach (DataGridViewRow row in gv.Rows)
            {
                count++;
                row.Cells[0].Value = count;
            }
        }
        public static void BlurBackground(Form Model)
        {
            Form Background = new Form();
            using (Model)
            {
                Background.StartPosition = FormStartPosition.CenterScreen;
                Background.FormBorderStyle = FormBorderStyle.None;
                Background.Opacity = 0.5d;
                Background.BackColor = Color.Black;
                Background.Size = frmMain.instance.Size;
                Background.Location = frmMain.instance.Location;
                Background.WindowState = FormWindowState.Maximized;
                Background.ShowInTaskbar = false;
                Background.Show();
                Model.Owner = Background;
                Model.ShowDialog(Background);
                Background.Dispose();
            }
        }
        public static void CBFill(string qry, ComboBox cb)
        {
            SqlCommand cmd = new SqlCommand(qry, con);
            cmd.CommandType = CommandType.Text;
            SqlDataAdapter da = new SqlDataAdapter(cmd);
            DataTable dt = new DataTable();
            da.Fill(dt);
            cb.DisplayMember = "Name";
            cb.ValueMember = "id";
            cb.DataSource = dt;
            cb.SelectedIndex = -1;

        }
    }
}
