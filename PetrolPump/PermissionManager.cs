using System;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;

namespace ApplicationPermissions
{
    public class PermissionManager
    {
        // Method jo application ke folder ko full control permissions de ga
        public static void GrantFullControlToAppFolder()
        {
            try
            {
                // Application jis folder mein run ho rahi hai uska path lein
                string folderPath = AppDomain.CurrentDomain.BaseDirectory;

                // Directory ke security permissions lein
                DirectoryInfo directoryInfo = new DirectoryInfo(folderPath);
                DirectorySecurity directorySecurity = directoryInfo.GetAccessControl();

                // Rule banaye jo full control de sab users ko
                FileSystemAccessRule accessRule = new FileSystemAccessRule(
                    new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null), // Built-in Users group ke liye apply karain
                    FileSystemRights.FullControl,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, // Subfolders aur files pe bhi apply ho
                    PropagationFlags.None,
                    AccessControlType.Allow);

                // Security settings ko directory ke sath add karein
                directorySecurity.AddAccessRule(accessRule);

                // Updated security settings ko apply karain
                directoryInfo.SetAccessControl(directorySecurity);

                Console.WriteLine("Full control permissions application ke folder ko de di gayi hain.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error permissions set karte waqt: {ex.Message}");
            }
        }
    }
}
