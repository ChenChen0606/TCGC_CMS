import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    
    // Mo-wait og 3 seconds ayha mo-balhin sa Login Screen
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF006D6D), Color(0xFF004D40)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),

              // --- MAIN CLINIC ICON (CENTER) ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF), // Solid replacement for opacity
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
                  color: Color(0xFFB2DFDB), 
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
              
              const Spacer(flex: 1),

              // --- LOADING INDICATOR ---
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C853)),
              ),

              const Spacer(flex: 2),

              // --- FOOTER BRANDING (WITH TWO LOGOS) ---
              const Text(
                "Powered by",
                style: TextStyle(color: Color(0x80FFFFFF), fontSize: 10),
              ),
              const SizedBox(height: 15),
              
              // Gi-pwesto ang duha ka logo sa ubos
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFooterLogo('asset/tcgc.png'), // Imong TCGC Logo
                  const SizedBox(width: 15),
                  Container(width: 1, height: 25, color: const Color(0x33FFFFFF)), // Gamay nga divider
                  const SizedBox(width: 15),
                  _buildFooterLogo('asset/cliniclogo.png'), // Imong Clinic Logo
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

  // Helper function para dili mag-balik2 ang code sa logos
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
          // Kon dili makit-an ang image, naay fallback icon para dili error
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.image_not_supported_rounded, 
            size: 15, 
            color: Color(0xFF006D6D)
          ),
        ),
      ),
    );
  }
}