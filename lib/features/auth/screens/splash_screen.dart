import 'dart:async';
import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/features/auth/screens/login_screen.dart';
import 'package:clinicmanagementsystem/features/auth/screens/reset_password_screen.dart';
import 'package:clinicmanagementsystem/features/auth/recovery_state.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // Opened from a password reset email link
    if (RecoveryState.pending.value) {
      // Wait up to ~5 seconds for Supabase to create the recovery session.
      for (var i = 0;
          i < 20 && supabaseClient.auth.currentSession == null;
          i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
      }

      if (supabaseClient.auth.currentSession != null) {
        RecoveryState.pending.value = false;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
        return;
      }

      // The link did not produce a session. Show an error on the login page.
      RecoveryState.pending.value = false;
      RecoveryState.linkError =
          'This reset link could not be verified. Please request a new one '
          'in the same browser.';
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primaryDark,
              AppColors.primaryDeep
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x33FFFFFF),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  size: 90,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "TCGC CLINIC",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
              const Text(
                "Management System",
                style: TextStyle(
                  color: Color(0xFFCCFBF1),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(flex: 1),
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const Spacer(flex: 2),
              const Text(
                "Powered by",
                style: TextStyle(color: Color(0x80FFFFFF), fontSize: 10),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFooterLogo('asset/tcgc.png'),
                  const SizedBox(width: 15),
                  Container(
                      width: 1, height: 25, color: const Color(0x33FFFFFF)),
                  const SizedBox(width: 15),
                  _buildFooterLogo('asset/cliniclogo.png'),
                ],
              ),
              const SizedBox(height: 15),
              const Text(
                "Tangub City Global College",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLogo(String assetPath) {
    return Container(
      height: 40,
      width: 40,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.image_not_supported_rounded,
              size: 15,
              color: AppColors.primaryDeep),
        ),
      ),
    );
  }
}