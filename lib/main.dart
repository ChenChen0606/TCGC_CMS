import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/app/app.dart';
import 'package:flutter/services.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/platform/browser_tabs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  installHistoryRouteGuard();

  await initSupabase();

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
