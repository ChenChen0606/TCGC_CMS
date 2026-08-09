
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:clinicmanagementsystem/screen/splash_screen.dart'; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, 
  ));

  runApp(const TCGCClinicApp());
}

class TCGCClinicApp extends StatelessWidget {
  const TCGCClinicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TCGC Clinic MS',
      
      theme: ThemeData(
        useMaterial3: true,
        
        
        fontFamily: 'Inter', 

        // --- CORE COLORS ---
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF008080), 
          primary: const Color(0xFF008080),
          secondary: const Color(0xFF00C853), 
          surface: Colors.white,
          onSurface: const Color(0xFF1E293B),
        ),

        // --- BUTTON DESIGN ---
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: const Color(0xFF008080),
            foregroundColor: Colors.white,
            // default button text style
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),

        // --- TEXTFIELD DESIGN ---
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.all(16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF008080), width: 2),
          ),
        ),
        
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),

      home: const SplashScreen(),

      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => const SplashScreen(),
      ),
    );
  }
}