import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/vip_widgets.dart';
import 'backup_restore_screen.dart';
import 'change_password_screen.dart';
import 'closing2_screen.dart';
import 'credit_dealer_money_screens.dart';
import 'customer_screens.dart';
import 'dashboard_screen.dart';
import 'dealer_screens.dart';
import 'diesel_sales_screens.dart';
import 'login_screen.dart';
import 'reports_screens.dart';
import 'stock_bank_screens.dart';
import 'bul_mal_screens.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _open(BuildContext context, Widget screen) async {
    // Form turant kholo (offline OK) — sync background
    unawaited(SyncService.instance.syncNow());
    if (!context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <_MenuItem>[
      _MenuItem(Icons.dashboard_customize_rounded, 'Dashboard', 'Totals, litter, graphs', const DashboardScreen()),
      _MenuItem(Icons.account_balance_wallet_outlined, 'Bul Mal', 'Owner In / Out + VIP PDF', const BulMalListScreen()),
      _MenuItem(Icons.people_alt_rounded, 'Add Customer', 'Customer name, mobile, date', const CustomerListScreen()),
      _MenuItem(Icons.local_gas_station_rounded, 'Daily Diesel Sales', 'Litter, rate, amount, credit, balance', const DieselSalesListScreen()),
      _MenuItem(Icons.payments_outlined, 'Credit Customer', 'Customer wasooli / credit adjust', const CreditCustomerListScreen()),
      _MenuItem(Icons.add_business_rounded, 'Add Dealer', 'Dealer + DDAmount / DAmount', const DealerListScreen()),
      _MenuItem(Icons.outbox_outlined, 'Dealer Payout', 'Payment to dealer (DAmount +=)', const DealerPayoutListScreen()),
      _MenuItem(Icons.local_shipping_outlined, 'DealerAmount', 'Purchase liters from dealer', const DealerAmountListScreen()),
      _MenuItem(Icons.add_card_outlined, 'Direct Dealer Amount', 'Direct DDAmount entry', const DirectDealerListScreen()),
      _MenuItem(Icons.inventory_2_outlined, 'Stock', 'Stock diesel add / minus', const StockListScreen()),
      _MenuItem(Icons.account_balance_outlined, 'Bank Account', 'Bank In / Out transactions', const BankListScreen()),
      _MenuItem(Icons.assessment_outlined, 'Reports', 'Diesel / Dealer / Stock reports', const ReportsHubScreen()),
      _MenuItem(Icons.insights_rounded, 'Closing 2', 'Profit + receivable / payable', const Closing2Screen()),
      _MenuItem(Icons.backup_rounded, 'Backup / Restore', 'PC ↔ Mobile both ways', const BackupRestoreScreen()),
      _MenuItem(Icons.lock_outline_rounded, 'Change Password', 'Password + fingerprint', const ChangePasswordScreen()),
    ];

    return VipScaffold(
      title: 'Zaib Petroleum',
      showBack: false,
      actions: [
        IconButton(
          tooltip: 'Logout',
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout_rounded, color: AppColors.gold),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF243356), Color(0xFF121A2E)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ZAIB PETROLEUM SERVICE',
                  style: GoogleFonts.cinzel(
                    color: AppColors.gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Developed by Irtaza Hussain',
                  style: GoogleFonts.manrope(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final t in tiles) ...[
            _MenuTile(
              icon: t.icon,
              title: t.title,
              subtitle: t.subtitle,
              onTap: () => _open(context, t.screen),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.title, this.subtitle, this.screen);
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppColors.panel.withValues(alpha: 0.9),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppColors.gold),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.goldSoft, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
