using ZaibPetroleumService.Model;
using ZaibPetroleumService.View;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ZaibPetroleumService
{
    internal static class Program
    {
        /// <summary>
        /// The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            // Silent cloud sync (zaibservice) — UI unchanged
            try { Services.SupabaseSyncService.StartSilent(); } catch { }
            Application.Run(new LoginForm());
        }
    }
}
