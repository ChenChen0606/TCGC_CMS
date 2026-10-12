import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clinicmanagementsystem/screen/splash_screen.dart';
import 'package:clinicmanagementsystem/screen/app_colors.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';
import 'package:clinicmanagementsystem/services/reference_data_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initSupabase();

  // ── DIAGNOSTIC: show real build errors on screen ────────────────────
  // By default Flutter shows a helpful red error screen ONLY in debug
  // builds. In profile/release builds (and some web preview/hosting
  // setups run release by default) a widget that throws while building
  // just renders as a blank box — no error, no text, nothing in the UI.
  // That's exactly the "a dashboard page shows nothing" symptom.
  // This override makes the actual error message visible everywhere,
  // in every build mode, so a broken screen shows its exception text
  // right on the page instead of going silently blank.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Still log to the console/terminal as usual too.
    FlutterError.presentError(details);
    return Material(
      color: AppColors.dangerContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This screen failed to load.',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  };

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // ── Reference data, before any screen builds ─────────────────────────
  // The five reference tables (academic periods, institutes, programs,
  // departments/offices, positions) are what every dropdown in the app offers,
  // and `ReferenceCatalog` starts life holding a hard-coded offline seed. If the
  // seed is still in place when the first screen builds, the Add Visitor dialog
  // offers 2024-2025 · 1st Semester, refuses to enrol anyone because no current
  // term resolves, and lists program names that may not exist any more — all
  // because nobody had read the database yet.
  //
  // Awaited rather than fired off: it is five small reads and it is the input to
  // every term, program and position the UI is about to render. Not fatal if it
  // fails — the seed is left in place so the app still opens — which is why this
  // does not throw.
  //
  // It is also deliberately NOT the only attempt. Row Level Security hides these
  // five tables from the anon / publishable key and hides them the quiet way —
  // `HTTP 200` with an empty body — so a read made before sign-in cannot be
  // trusted and `ReferenceCatalog.load` refuses to make one. On a warm start
  // (a desktop build, or any web origin that still holds the session) there IS a
  // session here and this really does read the database; on a cold one there is
  // not, so it returns immediately rather than holding the splash up for a
  // round trip that cannot work. The auth listener below covers that case.
  await ReferenceCatalog.loadQuietly();

  // The other half: fill the catalog in the moment a session exists, wherever
  // the sign-in happened — so no future entry point can leave it on the seed.
  // This matters most on web, where `flutter run -d chrome` starts a fresh
  // browser profile and every run therefore begins signed out.
  supabaseClient.auth.onAuthStateChange.listen((event) {
    if (event.session == null) {
      return; // signed out — there is nothing to read as
    }
    ReferenceCatalog.loadAfterSignIn();
  });

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

        // ── CORE COLOR SYSTEM ────────────────────────────────────────────
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

        // ── APP BAR ──────────────────────────────────────────────────────
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

        // ── BUTTON DESIGN ────────────────────────────────────────────────
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

        // ── TEXTFIELD DESIGN ─────────────────────────────────────────────
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

        // ── CARDS ────────────────────────────────────────────────────────
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

        // ── DIALOGS ──────────────────────────────────────────────────────
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

        // ── SNACKBARS / SCROLL INDICATOR ─────────────────────────────────
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

        // ── CHIPS / BADGES ───────────────────────────────────────────────
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

        // ── DIVIDER / PROGRESS / TOOLTIP ─────────────────────────────────
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

        // ── SELECTORS (radio / checkbox / switch / tab / slider) ───────────
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

        // ── DATE / TIME PICKERS ──────────────────────────────────────────
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

        // ── MISC ─────────────────────────────────────────────────────────
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
