using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Windows.Forms;
using ZaibPetroleumService.Services;

namespace ZaibPetroleumService.Model
{
    public partial class frmDiselAdd : SampleAdd
    {
        private List<string> existingCustomerNames = new List<string>();
        public int id = 0;
        private decimal TotalBalance = 0;
        private bool _blockSaveCreditRow; // credit entry sale form pe edit nahi
        private bool _loadingData; // LoadData ke dauran recalc Amount mat mitao
        private bool _syncingFields; // Amount/Balance sync loop rokne ke liye

        public frmDiselAdd()
        {
            try
            {
                InitializeComponent();
                txtlitter.TextChanged += TriggerRecalculation;
                txtrate.TextChanged += TriggerRecalculation;
                txtlitter.Leave += txtlitter_Leave;
                txtrate.Leave += txtrate_Leave;
                txtadvance.TextChanged += TriggerRecalculation;
                txtcredit.TextChanged += TriggerRecalculation;
                this.KeyPreview = true;
                this.KeyDown += new KeyEventHandler(frmDiselAdd_KeyDown);
                PopulateCustomerNames();

                // ⭐ yeh do nayi lines:
                txtVehicle.Leave += txtVehicle_Leave;
                txtVehicle.KeyDown += txtVehicle_KeyDown;
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (Constructor): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }


        private void frmDiselAdd_Load(object sender, EventArgs e)
        {
            try
            {
                LoadCustomers();

                if (id > 0)
                {
                    LoadData();
                }
                else
                {
                    txtdate.Value = DateTime.Now;
                }
                txtbalance.TextChanged += new EventHandler(txtbalance_TextChanged);
                txtamount.TextChanged += new EventHandler(txtamount_TextChanged);
                txtadvance.TextChanged += new EventHandler(txtadvance_TextChanged);
                txtcredit.TextChanged += new EventHandler(txtcredit_TextChanged);
                txtamount.Leave += (s, ev) => SyncBalanceFromAmount();
                txtbalance.Leave += (s, ev) => SyncBalanceFromAmount(); // alag type kiya ho to Amount se wapas sync

                SetupCustomerCreditDisplay();
                RefreshCustomerCreditDisplay();

                BeginInvoke(new Action(() =>
                {
                    txtVehicle.Focus();
                    txtVehicle.Select();
                }));
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (Form Load): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }
        // Enter dabao to bhi suggest chale
        private void txtVehicle_KeyDown(object sender, KeyEventArgs e)
        {
            try
            {
                if (e.KeyCode == Keys.Enter)
                {
                    e.SuppressKeyPress = true;
                    SuggestCustomerByVehicle();
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtVehicle_KeyDown): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        // Focus chhorne par bhi suggest kare
        private void txtVehicle_Leave(object sender, EventArgs e)
        {
            try
            {
                SuggestCustomerByVehicle();
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtVehicle_Leave): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }
        /// <summary>
        /// txtVehicle mein jo vehicle number likha gaya hai,
        /// us ke liye PetrolAdd history se sab se zyada use hone wala customer nikalta hai
        /// aur cbName + txtName set kar deta hai.
        /// </summary>
        private void SuggestCustomerByVehicle()
        {
            try
            {
                string vehicle = (txtVehicle.Text ?? "").Trim();
                if (string.IsNullOrEmpty(vehicle))
                    return;

                string qry = @"
            SELECT 
                p.CustomerId,
                c.Name,
                COUNT(*) AS UseCount
            FROM PetrolAdd p
            INNER JOIN AddCustomer c ON c.Id = p.CustomerId
            WHERE TRIM(IFNULL(p.vehicle, '')) = @veh
            GROUP BY p.CustomerId, c.Name
            ORDER BY UseCount DESC
            LIMIT 1;
        ";

                Hashtable ht = new Hashtable
        {
            { "@veh", vehicle }
        };

                DataTable dt = MainClass.ExecuteSelectQuery(qry, ht);

                if (dt != null && dt.Rows.Count > 0)
                {
                    // sab se zyada use hone wala customer
                    int customerId = Convert.ToInt32(dt.Rows[0]["CustomerId"]);
                    string customerName = dt.Rows[0]["Name"].ToString();

                    // ComboBox select karo
                    if (cbName.DataSource != null)
                    {
                        cbName.SelectedValue = customerId;
                    }

                    // Agar txtName mode use kar rahe ho (Ctrl+1), usme bhi naam dikhao
                    txtName.Text = customerName;
                }
                else
                {
                    // koi history nahi mili to kuch force mat karo, sirf optional message:
                    // CustomeMessage msg = new CustomeMessage("Is vehicle ke liye koi purana customer record nahi mila.", "Info");
                    // msg.ShowDialog();
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (SuggestCustomerByVehicle): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void LoadCustomers()
        {
            try
            {
                string customerQry = "SELECT Id, Name FROM AddCustomer";
                DataTable customerData = MainClass.ExecuteSelectQuery(customerQry, null);

                if (customerData != null)
                {
                    cbName.DisplayMember = "Name";
                    cbName.ValueMember = "Id";
                    cbName.DataSource = customerData;
                }
                else
                {
                    cbName.DataSource = null;
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (LoadCustomers): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void frmDiselAdd_KeyDown(object sender, KeyEventArgs e)
        {
            try
            {
                if (e.Control)
                {
                    if (e.KeyCode == Keys.D1)
                    {
                        txtName.Visible = true;
                        cbName.Visible = false;
                        txtName.Focus();
                    }
                    else if (e.KeyCode == Keys.D2)
                    {
                        cbName.Visible = true;
                        txtName.Visible = false;
                        cbName.Focus();
                    }
                    else if (e.KeyCode == Keys.S)
                    {
                        btnSave_Click(sender, e);
                    }
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (KeyDown): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void PopulateCustomerNames()
        {
            try
            {
                string query = "SELECT Id, Name FROM AddCustomer";
                DataTable dt = MainClass.ExecuteSelectQuery(query, null);

                if (dt != null && dt.Rows.Count > 0)
                {
                    cbName.DataSource = dt;
                    cbName.DisplayMember = "Name";
                    cbName.ValueMember = "Id";
                    cbName.DropDownHeight = 200;
                    cbName.IntegralHeight = false;

                    AutoCompleteStringCollection customerNames = new AutoCompleteStringCollection();
                    foreach (DataRow row in dt.Rows)
                    {
                        customerNames.Add(row["Name"].ToString());
                    }

                    txtName.AutoCompleteMode = AutoCompleteMode.SuggestAppend;
                    txtName.AutoCompleteSource = AutoCompleteSource.CustomSource;
                    txtName.AutoCompleteCustomSource = customerNames;

                    cbName.SelectedIndexChanged += new EventHandler(cbName_SelectedIndexChanged);
                }
                else
                {
                    CustomeMessage noDataMessage = new CustomeMessage("Koi customer data nahi mila!", "Warning");
                    noDataMessage.ShowDialog();
                    cbName.DataSource = null;
                    txtName.AutoCompleteCustomSource = null;
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (PopulateCustomerNames): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void cbName_SelectedIndexChanged(object sender, EventArgs e)
        {
            try
            {
                // Agar txtName visible hai aur uska text cbName ke selected item se match karta hai, to validation skip karo
                if (txtName.Visible && !string.IsNullOrWhiteSpace(txtName.Text) && cbName.Text == txtName.Text.Trim())
                {
                    return; // No validation message jab txtName se select ho raha hai
                }

                if (cbName.SelectedValue != null && cbName.SelectedValue != DBNull.Value)
                {
                    if (!int.TryParse(cbName.SelectedValue.ToString(), out int customerId))
                    {
                        CustomeMessage warningMessage = new CustomeMessage("Selected value valid integer nahi hai!", "Warning");
                        warningMessage.ShowDialog();
                    }
                }
                else if (cbName.SelectedIndex != -1) // Agar koi item select hua hai lekin value null hai
                {
                    CustomeMessage warningMessage = new CustomeMessage("Koi valid customer select nahi hua!", "Warning");
                    warningMessage.ShowDialog();
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (cbName_SelectedIndexChanged): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void TriggerRecalculation(object sender, EventArgs e)
        {
            if (_loadingData || _syncingFields) return;
            try
            {
                _syncingFields = true;

                decimal litter = 0, rate = 0, advance = 0, credit = 0, amount = 0;

                bool hasLitter = decimal.TryParse((txtlitter.Text ?? "").Replace(",", ""), out litter) && litter > 0;
                bool hasRate = decimal.TryParse((txtrate.Text ?? "").Replace(",", ""), out rate) && rate > 0;
                decimal.TryParse((txtadvance.Text ?? "").Replace(",", ""), out advance);
                decimal.TryParse((txtcredit.Text ?? "").Replace(",", ""), out credit);
                bool isAmountValid = decimal.TryParse((txtamount.Text ?? "").Replace(",", ""), out amount);

                // Litter+Rate mode: Amount = Litter×Rate, Balance hamesha usi se
                if (hasLitter && hasRate)
                {
                    amount = litter * rate;
                    decimal finalBalance = amount - credit + advance;
                    txtamount.Text = FmtMoney(amount);
                    txtbalance.Text = FmtMoney(finalBalance);
                }
                // Direct Amount mode: Balance = Amount − Credit + Advance (Amount alag / Balance alag nahi reh sakta)
                else if (isAmountValid)
                {
                    decimal finalBalance = amount - credit + advance;
                    txtbalance.Text = FmtMoney(finalBalance);
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (TriggerRecalculation): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
            finally
            {
                _syncingFields = false;
            }
        }

        /// Balance hamesha Amount se — manual alag Balance ignore / wapas sync.
        private void SyncBalanceFromAmount()
        {
            TriggerRecalculation(null, EventArgs.Empty);
        }

        private static string FmtMoney(decimal v)
        {
            return string.Format(CultureInfo.InvariantCulture, "{0:N0}", v);
        }

        private void LoadData()
        {
            try
            {
                _loadingData = true;
                string qry = "SELECT PetrolAdd.Date, PetrolAdd.ReceiptNo, PetrolAdd.vehicle, PetrolAdd.Litter, PetrolAdd.Rate, " +
                       "PetrolAdd.Advance, " +
                       "IFNULL(PetrolAdd.Amount, 0) AS Amount, " +
                       "IFNULL(PetrolAdd.Balance, 0) AS Balance, " +
                       "IFNULL(PetrolAdd.Credit, 0) AS Credit, PetrolAdd.Note, PetrolAdd.CustomerId, " +
                       "IFNULL(PetrolAdd.IsInitialEntry, 1) AS IsInitialEntry " +
                       "FROM PetrolAdd " +
                       "INNER JOIN AddCustomer ON PetrolAdd.CustomerId = AddCustomer.Id " +
                       "WHERE PetrolAdd.pid = @id";

                Hashtable ht = new Hashtable();
                ht.Add("@id", id);

                DataTable dt = MainClass.ExecuteSelectQuery(qry, ht);
                if (dt != null && dt.Rows.Count > 0)
                {
                    DataRow row = dt.Rows[0];

                    txtdate.Text = row["Date"].ToString();
                    txtrecipt.Text = row["ReceiptNo"].ToString();
                    txtVehicle.Text = row["vehicle"].ToString();

                    // 0 litter/rate ko khali dikhao taake direct-amount mode rahe
                    decimal lit = row["Litter"] != DBNull.Value ? Convert.ToDecimal(row["Litter"]) : 0;
                    decimal rt = row["Rate"] != DBNull.Value ? Convert.ToDecimal(row["Rate"]) : 0;
                    txtlitter.Text = lit > 0 ? lit.ToString("G") : "";
                    txtrate.Text = rt > 0 ? FormatRate(rt) : "";
                    txtadvance.Text = row["Advance"] != DBNull.Value
                        ? FmtMoney(Convert.ToDecimal(row["Advance"]))
                        : "0";

                    decimal amount = row["Amount"] != DBNull.Value ? Convert.ToDecimal(row["Amount"]) : 0;
                    decimal credit = row["Credit"] != DBNull.Value ? Convert.ToDecimal(row["Credit"]) : 0;
                    decimal balance = row["Balance"] != DBNull.Value ? Convert.ToDecimal(row["Balance"]) : 0;

                    // Comma format — hazar / lac / crore clear (LoadData mein TextChanged skip hota hai)
                    txtamount.Text = FmtMoney(amount);
                    txtcredit.Text = FmtMoney(credit);
                    txtbalance.Text = FmtMoney(balance);

                    txtnote.Text = row["Note"].ToString();

                    if (cbName.Items.Count > 0)
                    {
                        cbName.SelectedValue = row["CustomerId"];
                    }

                    // Credit Customer entry yahan edit nahi (Daily Diesel credit form kholta hai)
                    int isInitial = Convert.ToInt32(row["IsInitialEntry"]);
                    _blockSaveCreditRow = (isInitial == 0);
                    if (_blockSaveCreditRow)
                    {
                        CustomeMessage info = new CustomeMessage(
                            "Ye Credit Customer entry hai — Daily Diesel se dobara double-click karein.",
                            "INFORMATION");
                        info.ShowDialog();
                    }
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (LoadData): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
            finally
            {
                _loadingData = false;
                // Open pe Balance = Amount − Credit + Advance (mismatch na rahe)
                SyncBalanceFromAmount();
            }
        }

        public override void btnSave_Click(object sender, EventArgs e)
        {
            try
            {
                if (_blockSaveCreditRow)
                {
                    CustomeMessage validationMessage = new CustomeMessage(
                        "Ye Credit Customer entry hai — is form se update nahi hogi.", "Warning");
                    validationMessage.ShowDialog();
                    return;
                }

                // 🔹 Save se pehle last selected customer yaad rakh lo
                object lastCustomerId = cbName.SelectedValue;

                string customerName = string.Empty;

                if (txtName.Visible && !string.IsNullOrWhiteSpace(txtName.Text))
                {
                    customerName = txtName.Text;
                }
                else if (cbName.SelectedIndex != -1)
                {
                    customerName = cbName.Text;
                }
                else
                {
                    CustomeMessage validationMessage = new CustomeMessage("Customer select karein ya naam daalein!", "Warning");
                    validationMessage.ShowDialog();
                    return;
                }
                // ... (baaki tumhara code same ka same)


                decimal advance;
                if (!decimal.TryParse(txtadvance.Text.Replace(",", ""), out advance))
                    advance = 0;

                decimal credit;
                if (!decimal.TryParse(txtcredit.Text.Replace(",", ""), out credit))
                    credit = 0;

                decimal litter;
                if (!decimal.TryParse(txtlitter.Text.Replace(",", ""), out litter))
                    litter = 0;

                decimal rate;
                if (!decimal.TryParse(txtrate.Text.Replace(",", ""), out rate))
                    rate = 0;

                decimal amount = 0;
                string amountText = (txtamount.Text ?? "").Replace(",", "").Trim();
                if (!string.IsNullOrEmpty(amountText) &&
                    !decimal.TryParse(amountText, NumberStyles.Any, CultureInfo.InvariantCulture, out amount))
                {
                    CustomeMessage validationMessage = new CustomeMessage("Valid amount daalein!", "Warning");
                    validationMessage.ShowDialog();
                    return;
                }

                // Sirf Credit (litter/rate/amount sab 0) → Credit Customer entry (IsInitialEntry=0)
                bool isCreditOnly = litter <= 0 && rate <= 0 && amount <= 0 && credit > 0;

                if (!isCreditOnly && amount <= 0 && !(litter > 0 && rate > 0))
                {
                    CustomeMessage validationMessage = new CustomeMessage(
                        "Sale ke liye Litter+Rate ya Amount daalein.\nSirf Credit ke liye Amount khali rakhein aur Credit likhein.",
                        "Warning");
                    validationMessage.ShowDialog();
                    return;
                }

                if (!DateTime.TryParse(txtdate.Text, out DateTime dateValue))
                {
                    CustomeMessage validationMessage = new CustomeMessage("Valid date daalein!", "Warning");
                    validationMessage.ShowDialog();
                    return;
                }

                int customerId = ResolveCustomerIdForSave(customerName);
                if (customerId <= 0)
                {
                    CustomeMessage validationMessage = new CustomeMessage(
                        "Customer select karein ya sahi naam likhein!\n(Milta-julta naam mix nahi hoga — exact naam chahiye.)",
                        "Warning");
                    validationMessage.ShowDialog();
                    return;
                }

                if (isCreditOnly)
                {
                    string creditLabel = string.IsNullOrWhiteSpace(customerName) ? cbName.Text : customerName;
                    if (!BalanceConfirmationService.ConfirmCustomerPetrolCredit(customerId, credit, creditLabel))
                        return;

                    // Balance snapshot — Credit Customer form jaisa
                    decimal totalAmt = 0, totalCred = 0;
                    try
                    {
                        string balQ = @"SELECT SUM(IFNULL(Amount,0)+IFNULL(Advance,0)) AS TA,
                                               SUM(IFNULL(Credit,0)) AS TC
                                        FROM PetrolAdd WHERE CustomerId=@cid" +
                                      (id > 0 ? " AND pid<>@pid" : "");
                        var htBal = new Hashtable { { "@cid", customerId } };
                        if (id > 0) htBal.Add("@pid", id);
                        DataTable dtBal = MainClass.ExecuteSelectQuery(balQ, htBal);
                        if (dtBal != null && dtBal.Rows.Count > 0)
                        {
                            if (dtBal.Rows[0]["TA"] != DBNull.Value) totalAmt = Convert.ToDecimal(dtBal.Rows[0]["TA"]);
                            if (dtBal.Rows[0]["TC"] != DBNull.Value) totalCred = Convert.ToDecimal(dtBal.Rows[0]["TC"]);
                        }
                    }
                    catch { /* optional */ }

                    decimal creditBalance = totalAmt - (totalCred + credit);
                    bool isEditCredit = id > 0;
                    string qryCredit;
                    Hashtable htCredit = new Hashtable
                    {
                        { "@customerId", customerId },
                        { "@date", dateValue.ToString("yyyy-MM-dd") },
                        { "@recipt", txtrecipt.Text },
                        { "@credit", credit.ToString("F2") },
                        { "@balance", creditBalance.ToString("F2") },
                        { "@note", txtnote.Text }
                    };

                    if (!isEditCredit)
                    {
                        qryCredit = @"INSERT INTO PetrolAdd (CustomerId, Date, ReceiptNo, Credit, Balance, Note, IsInitialEntry)
                                      VALUES (@customerId, @date, @recipt, @credit, @balance, @note, 0)";
                    }
                    else
                    {
                        // Sirf credit row update — sale touch nahi
                        qryCredit = @"UPDATE PetrolAdd SET CustomerId=@customerId, Date=@date, ReceiptNo=@recipt,
                                      Credit=@credit, Balance=@balance, Note=@note
                                      WHERE pid=@pid AND IFNULL(IsInitialEntry,1)=0";
                        htCredit.Add("@pid", id);
                    }

                    int rCredit = MainClass.DataInsertUpdateDelete(qryCredit, htCredit);
                    if (rCredit > 0)
                    {
                        CustomeMessage successMessage = new CustomeMessage(
                            isEditCredit
                                ? "Credit entry update ho gayi! (Credit Customer mein bhi)"
                                : "Credit entry save ho gayi! (Credit Customer mein bhi)",
                            "Success");
                        successMessage.ShowDialog();

                        if (isEditCredit)
                        {
                            DialogResult = DialogResult.OK;
                            Close();
                            return;
                        }

                        string lastTypedName = txtName.Text.Trim();
                        ResetFormKeepSelectedDate();
                        id = 0;
                        TotalBalance = 0;
                        if (txtName.Visible)
                        {
                            txtName.Text = lastTypedName;
                            txtName.Focus();
                        }
                        else
                        {
                            cbName.SelectedValue = lastCustomerId;
                            cbName.Focus();
                        }
                        txtamount.Clear();
                        txtbalance.Clear();
                        txtcredit.Clear();
                    }
                    else if (isEditCredit)
                    {
                        ErrorFormMessage errorMessage = new ErrorFormMessage(
                            "Credit update nahi hua. Credit Customer form se try karein.", "Error");
                        errorMessage.ShowDialog();
                    }
                    return;
                }

                // ——— Normal SALE (IsInitialEntry=1) ———
                if (litter > 0 && rate > 0 && amount <= 0)
                    amount = litter * rate;

                decimal balance = amount - credit;
                decimal finalBalance = balance + advance;
                TotalBalance += finalBalance;

                string qry;
                Hashtable htSave = new Hashtable();
                bool isEdit = id > 0;

                if (!isEdit)
                {
                    qry = "INSERT INTO PetrolAdd (CustomerId, Date, ReceiptNo, vehicle, Litter, Rate, Advance, Amount, Credit, Balance, Note, IsInitialEntry) " +
                          "VALUES (@customerId, @date, @recipt, @veh, @litter, @rate, @advance, @amount, @credit, @balance, @note, 1)";
                }
                else
                {
                    // Sirf sale row (IsInitialEntry=1) — credit entry touch nahi
                    qry = "UPDATE PetrolAdd SET CustomerId = @customerId, Date = @date, ReceiptNo = @recipt, vehicle = @veh, " +
                          "Litter = @litter, Rate = @rate, Advance = @advance, Amount = @amount, Credit = @credit, " +
                          "Balance = @balance, Note = @note WHERE pid = @pid AND IFNULL(IsInitialEntry,1)=1";
                    htSave.Add("@pid", id);
                }

                htSave.Add("@customerId", customerId);
                htSave.Add("@date", dateValue.ToString("yyyy-MM-dd"));
                htSave.Add("@recipt", txtrecipt.Text);
                htSave.Add("@veh", txtVehicle.Text);
                htSave.Add("@litter", litter.ToString("F2"));
                htSave.Add("@rate", FormatRate(rate));
                htSave.Add("@advance", advance.ToString("F2"));
                htSave.Add("@amount", amount.ToString("F2"));
                htSave.Add("@credit", credit.ToString("F2"));
                htSave.Add("@balance", finalBalance.ToString("F2"));
                htSave.Add("@note", txtnote.Text);

                int r = MainClass.DataInsertUpdateDelete(qry, htSave);
                string lastTypedNameSale = txtName.Text.Trim();

                if (r > 0)
                {
                    CustomeMessage successMessage = new CustomeMessage(
                        isEdit ? "Entry update ho gayi!" : "Entry save ho gayi!", "Success");
                    successMessage.ShowDialog();

                    if (isEdit)
                    {
                        DialogResult = DialogResult.OK;
                        Close();
                        return;
                    }

                    ResetFormKeepSelectedDate();
                    id = 0;
                    TotalBalance = 0;

                    if (txtName.Visible)
                    {
                        txtName.Text = lastTypedNameSale;
                        txtName.Focus();
                    }
                    else
                    {
                        cbName.SelectedValue = lastCustomerId;
                        cbName.Focus();
                    }

                    txtamount.Clear();
                    txtbalance.Clear();
                }
                else if (isEdit)
                {
                    ErrorFormMessage errorMessage = new ErrorFormMessage(
                        "Update nahi hua. Ye Credit entry ho sakti hai — Daily Diesel se double-click karein.", "Error");
                    errorMessage.ShowDialog();
                }


            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (Save): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        public override void btnDel_Click(object sender, EventArgs e)
        {
            try
            {
                if (id > 0)
                {
                    YesOrNoMessage confirmDelete = new YesOrNoMessage("Kya aap is record ko delete karna chahte hain?", "Confirm Delete");
                    if (confirmDelete.ShowDialog() == DialogResult.Yes)
                    {
                        try
                        {
                            int r = MainClass.DeleteWithTombstone("PetrolAdd", "pid", id, "zaib_petrol_entries");
                            if (r > 0)
                            {
                                CustomeMessage successMessage = new CustomeMessage("Record delete ho gaya!", "Success");
                                successMessage.ShowDialog();
                                ResetFormKeepSelectedDate();
                                id = 0;
                            }
                            else
                            {
                                ErrorFormMessage errorMessage = new ErrorFormMessage("Record delete nahi hua!", "Error");
                                errorMessage.ShowDialog();
                            }
                        }
                        catch (Exception exInner)
                        {
                            ErrorFormMessage errorMessage = new ErrorFormMessage("Error (Delete Inner): " + exInner.Message, "Error");
                            errorMessage.ShowDialog();
                        }
                    }
                }
                else
                {
                    CustomeMessage noSelectionMessage = new CustomeMessage("Pehle ek record select karein!", "Warning");
                    noSelectionMessage.ShowDialog();
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (Delete): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtbalance_TextChanged(object sender, EventArgs e)
        {
            if (_loadingData || _syncingFields) return;
            try
            {
                string currentText = txtbalance.Text.Replace(",", "");
                if (decimal.TryParse(currentText, out decimal value))
                {
                    _syncingFields = true;
                    txtbalance.Text = string.Format(CultureInfo.InvariantCulture, "{0:N0}", value);
                    txtbalance.SelectionStart = txtbalance.Text.Length;
                    _syncingFields = false;
                }
            }
            catch (Exception ex)
            {
                _syncingFields = false;
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtbalance_TextChanged): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtcredit_TextChanged(object sender, EventArgs e)
        {
            if (_loadingData || _syncingFields) return;
            try
            {
                string currentText = txtcredit.Text.Replace(",", "");
                if (decimal.TryParse(currentText, out decimal value))
                {
                    _syncingFields = true;
                    txtcredit.Text = string.Format(CultureInfo.InvariantCulture, "{0:N0}", value);
                    txtcredit.SelectionStart = txtcredit.Text.Length;
                    _syncingFields = false;
                    SyncBalanceFromAmount();
                }
            }
            catch (Exception ex)
            {
                _syncingFields = false;
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtcredit_TextChanged): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtamount_TextChanged(object sender, EventArgs e)
        {
            if (_loadingData || _syncingFields) return;
            try
            {
                string currentText = txtamount.Text.Replace(",", "");
                if (decimal.TryParse(currentText, out decimal value))
                {
                    _syncingFields = true;
                    txtamount.Text = string.Format(CultureInfo.InvariantCulture, "{0:N0}", value);
                    txtamount.SelectionStart = txtamount.Text.Length;
                    _syncingFields = false;
                    // Amount badla → Balance turant sync (alag Balance issue nahi)
                    SyncBalanceFromAmount();
                }
            }
            catch (Exception ex)
            {
                _syncingFields = false;
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtamount_TextChanged): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtadvance_TextChanged(object sender, EventArgs e)
        {
            if (_loadingData || _syncingFields) return;
            try
            {
                string currentText = txtadvance.Text.Replace(",", "");
                if (decimal.TryParse(currentText, out decimal value))
                {
                    _syncingFields = true;
                    txtadvance.Text = string.Format(CultureInfo.InvariantCulture, "{0:N0}", value);
                    txtadvance.SelectionStart = txtadvance.Text.Length;
                    _syncingFields = false;
                    SyncBalanceFromAmount();
                }
            }
            catch (Exception ex)
            {
                _syncingFields = false;
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtadvance_TextChanged): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtlitter_KeyPress(object sender, KeyPressEventArgs e)
        {
            try
            {
                if (char.IsControl(e.KeyChar))
                    return;

                var tb = sender as Control;
                string text = tb is Guna.UI2.WinForms.Guna2TextBox gtb ? gtb.Text : (tb as TextBox)?.Text ?? "";

                // Starting mein point (.) allow nahi
                if (e.KeyChar == '.' && (text.Length == 0 || GetSelectionStart(tb) == 0))
                {
                    e.Handled = true;
                    return;
                }

                if (!char.IsDigit(e.KeyChar) && e.KeyChar != '.')
                    e.Handled = true;
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtlitter_KeyPress): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private const int RateDecimalPlaces = 4;

        private static string FormatRate(decimal rate)
        {
            return rate == decimal.Truncate(rate)
                ? rate.ToString("0", CultureInfo.InvariantCulture)
                : rate.ToString("0.0####", CultureInfo.InvariantCulture);
        }

        private void txtrate_KeyPress(object sender, KeyPressEventArgs e)
        {
            try
            {
                if (char.IsControl(e.KeyChar))
                    return;

                var tb = sender as Control;
                string text = tb is Guna.UI2.WinForms.Guna2TextBox gtb ? gtb.Text : (tb as TextBox)?.Text ?? "";
                int selStart = GetSelectionStart(tb);
                int selLen = GetSelectionLength(tb);

                if (e.KeyChar == '.')
                {
                    if (text.Contains(".") || selStart == 0)
                    {
                        e.Handled = true;
                        return;
                    }
                    return;
                }

                if (!char.IsDigit(e.KeyChar))
                {
                    e.Handled = true;
                    return;
                }

                string before = text.Substring(0, selStart);
                string after = text.Substring(selStart + selLen);
                string newText = before + e.KeyChar + after;

                int dotIdx = newText.IndexOf('.');
                if (dotIdx >= 0 && newText.Length - dotIdx - 1 > RateDecimalPlaces)
                    e.Handled = true;
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtrate_KeyPress): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtlitter_Leave(object sender, EventArgs e)
        {
            try
            {
                string t = txtlitter.Text ?? "";
                if (t.StartsWith("."))
                    txtlitter.Text = t.TrimStart('.');
            }
            catch { }
        }

        private void txtrate_Leave(object sender, EventArgs e)
        {
            try
            {
                SanitizeRateText();
            }
            catch { }
        }

        private void SanitizeRateText()
        {
            string t = (txtrate.Text ?? "").Trim().Replace(",", "");
            if (string.IsNullOrEmpty(t))
                return;

            if (t.StartsWith("."))
                t = "0" + t;

            if (t.EndsWith("."))
            {
                txtrate.Text = t.TrimEnd('.');
                return;
            }

            if (decimal.TryParse(t, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out decimal rate))
            {
                string formatted = FormatRate(rate);

                if (formatted != txtrate.Text)
                    txtrate.Text = formatted;
            }
        }

        private static int GetSelectionStart(Control ctrl)
        {
            if (ctrl is Guna.UI2.WinForms.Guna2TextBox g) return g.SelectionStart;
            if (ctrl is TextBox t) return t.SelectionStart;
            return 0;
        }

        private static int GetSelectionLength(Control ctrl)
        {
            if (ctrl is Guna.UI2.WinForms.Guna2TextBox g) return g.SelectionLength;
            if (ctrl is TextBox t) return t.SelectionLength;
            return 0;
        }

        private void txtamount_KeyPress(object sender, KeyPressEventArgs e)
        {
            try
            {
                if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar) && e.KeyChar != '.')
                {
                    e.Handled = true;
                    CustomeMessage customMessageBox = new CustomeMessage("آپ یہاں صرف نمبر درج کر سکتے ہیں۔", "غلطی");
                    customMessageBox.ShowDialog();
                }
                if (e.KeyChar == '.' && (sender as TextBox).Text.Contains("."))
                {
                    e.Handled = true;
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtamount_KeyPress): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtcredit_KeyPress(object sender, KeyPressEventArgs e)
        {
            try
            {
                if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar) && e.KeyChar != '.')
                {
                    e.Handled = true;
                    CustomeMessage customMessageBox = new CustomeMessage("آپ یہاں صرف نمبر درج کر سکتے ہیں۔", "غلطی");
                    customMessageBox.ShowDialog();
                }
                if (e.KeyChar == '.' && (sender as TextBox).Text.Contains("."))
                {
                    e.Handled = true;
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtcredit_KeyPress): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtbalance_KeyPress(object sender, KeyPressEventArgs e)
        {
            try
            {
                if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar) && e.KeyChar != '.')
                {
                    e.Handled = true;
                    CustomeMessage customMessageBox = new CustomeMessage("آپ یہاں صرف نمبر درج کر سکتے ہیں۔", "غلطی");
                    customMessageBox.ShowDialog();
                }
                if (e.KeyChar == '.' && (sender as TextBox).Text.Contains("."))
                {
                    e.Handled = true;
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtbalance_KeyPress): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private void txtadvance_KeyPress(object sender, KeyPressEventArgs e)
        {
            try
            {
                if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar) && e.KeyChar != '.')
                {
                    e.Handled = true;
                    CustomeMessage customMessageBox = new CustomeMessage("آپ یہاں صرف نمبر درج کر سکتے ہیں۔", "غلطی");
                    customMessageBox.ShowDialog();
                }
                if (e.KeyChar == '.' && (sender as TextBox).Text.Contains("."))
                {
                    e.Handled = true;
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtadvance_KeyPress): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }

        private int ResolveCustomerIdForSave(string customerName)
        {
            if (cbName.SelectedValue != null && cbName.SelectedValue != DBNull.Value &&
                int.TryParse(cbName.SelectedValue.ToString(), out int selectedId) && selectedId > 0)
                return selectedId;

            if (string.IsNullOrWhiteSpace(customerName))
                return 0;

            var ht = new Hashtable { { "@name", customerName.Trim() } };
            DataTable dt = MainClass.ExecuteSelectQuery(
                "SELECT id FROM AddCustomer WHERE TRIM(Name) = @name COLLATE NOCASE LIMIT 1", ht);
            if (dt != null && dt.Rows.Count > 0)
                return Convert.ToInt32(dt.Rows[0]["id"]);
            return 0;
        }

        private void txtName_TextChanged(object sender, EventArgs e)
        {
            try
            {
                string enteredName = txtName.Text.Trim();
                if (!string.IsNullOrEmpty(enteredName))
                {
                    DataTable dt = cbName.DataSource as DataTable;
                    if (dt != null)
                    {
                        DataRow match = null;
                        foreach (DataRow row in dt.Rows)
                        {
                            if (string.Equals(Convert.ToString(row["Name"]), enteredName,
                                StringComparison.OrdinalIgnoreCase))
                            {
                                match = row;
                                break;
                            }
                        }

                        if (match != null)
                            cbName.SelectedValue = match["Id"];
                        else
                            cbName.SelectedIndex = -1;
                    }
                }
            }
            catch (Exception ex)
            {
                ErrorFormMessage errorMessage = new ErrorFormMessage("Error (txtName_TextChanged): " + ex.Message, "Error");
                errorMessage.ShowDialog();
            }
        }
    }
}
