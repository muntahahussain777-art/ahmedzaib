import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class VipScaffold extends StatelessWidget {
  const VipScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.floatingActionButton,
    this.showBack = true,
    this.backResult,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBack;
  /// List refresh ke liye — continuous save ke baad back pe true.
  final Object? backResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0E1628),
              Color(0xFF1A2744),
              Color(0xFF243356),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    if (showBack && Navigator.canPop(context))
                      IconButton(
                        onPressed: () => Navigator.pop(context, backResult),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.gold),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.cinzel(
                          color: AppColors.gold,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ...?actions,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class VipField extends StatelessWidget {
  const VipField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.readOnly = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.onChanged,
    this.onTap,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool readOnly;
  final bool obscureText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        onChanged: onChanged,
        onTap: onTap,
        style: const TextStyle(color: AppColors.cream),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 15),
        ),
      ),
    );
  }
}
