using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PetrolPump
{
    public partial class frmMain : Sample
    {
        public frmMain()
        {
            InitializeComponent();
        }

        static frmMain _obj;
        public static frmMain instance
        {
            get { if (_obj == null) { _obj = new frmMain(); } return _obj; }
        }


        private void AddControls(Form F)
        {
            Controlspanel.Controls.Clear();
            F.TopLevel = false;
            Controlspanel.Controls.Add(F);
            F.Dock = DockStyle.Fill;
            F.Show();
        }

        private void guna2Button2_Click(object sender, EventArgs e)
        {
            AddControls(new ());
        }
    }
}
