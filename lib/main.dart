import 'package:clinicmanagementsystem/features/auth/recovery_state.dart';
import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/app/app.dart';
import 'package:flutter/services.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/platform/browser_tabs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture the URL before anything can rewrite it.
  final launchUri = Uri.base;
  debugPrint('MAIN launch uri: $launchUri');

  // Supabase must read the code/token BEFORE the history guard runs.
  await initSupabase();

  // Fallback: code present but Supabase did not create a session.
  final code = launchUri.queryParameters['code'];
  if (code != null) {
    // Let Supabase's own auto-exchange finish first (a code is single-use).
    for (var i = 0;
        i < 8 && supabaseClient.auth.currentSession == null;
        i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (supabaseClient.auth.currentSession == null) {
      try {
        await supabaseClient.auth.exchangeCodeForSession(code);
      } catch (e) {
        debugPrint('RECOVERY: manual code exchange failed: $e');
      }
    }
  }

  installHistoryRouteGuard(); // AFTER Supabase has consumed the URL

  RecoveryState.start(launchUri);

  ErrorWidget.builder = (FlutterErrorDetails details) {
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

  await ReferenceCatalog.loadQuietly();

  supabaseClient.auth.onAuthStateChange.listen((event) {
    if (event.session == null) {
      return;
    }
    ReferenceCatalog.loadAfterSignIn();
  });

  runApp(const TCGCClinicApp());

  if (browserHistoryEnabled) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemNavigator.selectMultiEntryHistory();
    });
  }
}