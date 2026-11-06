import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/features/auth/screens/splash_screen.dart';

class TCGCClinicApp extends StatelessWidget {
  const TCGCClinicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TCGC CLINIC MANAGEMENT SYSTEM',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryDark,
          brightness: Brightness.light,
          primary: AppColors.primary,
          onPrimary: AppColors.surface,
          primaryContainer: AppColors.primaryContainer,
          onPrimaryContainer: AppColors.onPrimaryContainer,
          secondary: AppColors.secondary,
          onSecondary: AppColors.surface,
          secondaryContainer: AppColors.secondaryContainer,
          onSecondaryContainer: AppColors.primaryDeep,
          surface: AppColors.surface,
          onSurface: AppColors.textDark,
          onSurfaceVariant: AppColors.textSub,
          outline: AppColors.borderStrong,
          outlineVariant: AppColors.border,
          error: AppColors.danger,
          onError: AppColors.surface,
          errorContainer: AppColors.dangerContainer,
          onErrorContainer: AppColors.danger,
          surfaceTint: AppColors.primary,
          shadow: AppColors.shadowStrong,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textMain,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: AppColors.textMain),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
            fontFamily: 'Montserrat',
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled))
                return AppColors.borderStrong;
              return AppColors.primary;
            }),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            overlayColor: const WidgetStatePropertyAll(Color(0x14FFFFFF)),
            shadowColor: const WidgetStatePropertyAll(AppColors.shadowCard),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  letterSpacing: 0.2),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            elevation: const WidgetStatePropertyAll(0),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled))
                return AppColors.textMuted;
              return AppColors.primaryDark;
            }),
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            overlayColor: const WidgetStatePropertyAll(Color(0x140D9488)),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: AppColors.border);
              }
              return const BorderSide(
                  color: AppColors.borderStrong, width: 1.2);
            }),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 0.2),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled))
                return AppColors.textMuted;
              return AppColors.primaryDark;
            }),
            overlayColor: const WidgetStatePropertyAll(Color(0x0F0D9488)),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 0.2),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.fieldFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          labelStyle: const TextStyle(color: AppColors.textSub, fontSize: 14),
          prefixIconColor: AppColors.textMuted,
          suffixIconColor: AppColors.textMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger, width: 2),
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          titleTextStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
          contentTextStyle: const TextStyle(
              fontSize: 14.5, color: AppColors.textSub, height: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          shadowColor: AppColors.shadowStrong,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryDeep,
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          elevation: 4,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actionTextColor: AppColors.primaryContainer,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.bgAlt,
          selectedColor: AppColors.primaryContainer,
          disabledColor: AppColors.bg,
          labelStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark),
          secondaryLabelStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: AppColors.bgAlt,
          circularTrackColor: AppColors.bgAlt,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.textMain,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.textMuted;
          }),
          overlayColor: const WidgetStatePropertyAll(Color(0x0F0D9488)),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return Colors.transparent;
          }),
          checkColor: const WidgetStatePropertyAll(Colors.white),
          side: const BorderSide(color: AppColors.borderStrong, width: 1.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          overlayColor: const WidgetStatePropertyAll(Color(0x0F0D9488)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppColors.textMuted;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.borderStrong;
          }),
          trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primaryDark,
          unselectedLabelColor: AppColors.textSub,
          indicatorColor: AppColors.primary,
          labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          unselectedLabelStyle:
              TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
          dividerColor: AppColors.border,
          indicatorSize: TabBarIndicatorSize.label,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: AppColors.primaryDark,
          headerForegroundColor: Colors.white,
          dayStyle: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          weekdayStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSub,
              fontSize: 12.5),
          yearStyle: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          todayBorder: const BorderSide(color: AppColors.primary, width: 1.6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        timePickerTheme: TimePickerThemeData(
          backgroundColor: AppColors.surface,
          dialHandColor: AppColors.primary,
          hourMinuteTextColor: AppColors.textMain,
          dayPeriodTextColor: AppColors.primaryDark,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          hourMinuteShape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.primary,
          selectionColor: Color(0x33CCFBF1),
          selectionHandleColor: AppColors.primary,
        ),
        visualDensity: VisualDensity.standard,
      ),
      home: const SplashScreen(),
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => const SplashScreen(),
      ),
    );
  }
}
