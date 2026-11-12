import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:clinicmanagementsystem/features/dashboard/screens/clinic_dashboard_screen.dart';
import 'package:clinicmanagementsystem/features/auth/screens/force_password_change_screen.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/services/app_warmup.dart';
import 'package:clinicmanagementsystem/core/platform/browser_tabs.dart';
import 'package:clinicmanagementsystem/features/auth/recovery_state.dart';
import 'package:clinicmanagementsystem/features/auth/widgets/forgot_password_dialog.dart';
import 'package:clinicmanagementsystem/features/auth/screens/reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  bool _recoveryOpen = false;

  @override
void initState() {
  super.initState();
  RecoveryState.pending.addListener(_checkRecovery);
  WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
}

Future<void> _checkRecovery() async {
  if (RecoveryState.linkError != null) {
    final msg = RecoveryState.linkError;
    RecoveryState.linkError = null;
    if (mounted) setState(() => _error = msg);
    return;
  }

  if (!RecoveryState.pending.value || _recoveryOpen) return;

  // Wait up to ~5 seconds for Supabase to finish creating the session.
  for (var i = 0; i < 20; i++) {
    if (!mounted) return;
    if (supabaseClient.auth.currentSession != null) {
      _openReset();
      return;
    }
    await Future.delayed(const Duration(milliseconds: 250));
  }

  if (!mounted) return;
  RecoveryState.pending.value = false;
  setState(() => _error =
      'This reset link could not be verified. Please request a new one '
      'in the same browser.');
}

void _openReset() {
  if (_recoveryOpen || !mounted) return;
  _recoveryOpen = true;
  RecoveryState.pending.value = false;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
  );
}

@override
void dispose() {
  RecoveryState.pending.removeListener(_checkRecovery);
  _usernameCtrl.dispose();
  _passwordCtrl.dispose();
  _passwordFocus.dispose();
  super.dispose();
}

  Future<void> _forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ForgotPasswordDialog(initial: _usernameCtrl.text.trim()),
    );
  }

  

  Future<void> _login() async {
  final username = _usernameCtrl.text.trim();
  final password = _passwordCtrl.text;

  if (username.isEmpty || password.isEmpty) {
    setState(() => _error = 'Enter your username and password to sign in.');
    return;
  }

  if (!isSupabaseConfigured) {
    setState(() => _error =
        'Unable to sign in. The app is not connected to the server yet.');
    return;
  }

  if (_submitting) return;
  setState(() {
    _submitting = true;
    _error = null;
  });

  try {
    final email =
        await AccountService.resolveAuthEmailForIdentifier(username);
    debugPrint('LOGIN: username="$username" -> email="$email"');

    if (email == null || email.isEmpty) {
      if (!mounted) return;
      setState(() => _error = 'Incorrect username or password.');
      return;
    }

    final response = await supabaseClient.auth.signInWithPassword(
      email: email,
      password: password,
    );
    debugPrint('LOGIN: signIn OK for ${response.user?.id}');

    final authUser = response.user;
    if (authUser == null) {
      if (!mounted) return;
      setState(() => _error = 'Unable to sign in. Please try again.');
      return;
    }

    Map<String, dynamic>? accountRow;
    try {
      accountRow = await supabaseClient
          .from('useraccount')
          .select()
          .eq('user_id', authUser.id)
          .maybeSingle();
    } catch (e) {
      debugPrint('LOGIN: useraccount fetch failed: $e');
    }

    final isActive = accountRow != null && accountRow['is_active'] is bool
        ? accountRow['is_active'] as bool
        : _metaIsActive(authUser);

    if (!isActive) {
      await supabaseClient.auth.signOut();
      if (!mounted) return;
      setState(() => _error =
          'Your account has been deactivated. Please contact the Clinic Head.');
      return;
    }

    await ReferenceCatalog.loadAfterSignIn();

    // Start downloading the dashboard, Clinic Visit and Individual Record
    // data now (not awaited) so those screens open without a loading wait.
    AppWarmup.start();

    final profile = accountRow != null
        ? AppProfile.fromSupabase(accountRow)
            .withNamesFrom(AccountService.profileFromAuthUser(authUser))
        : AccountService.profileFromAuthUser(authUser);

    final role = profile.role;
    final userEmail = authUser.email ?? '';
    final userUsername = profile.username.isNotEmpty
        ? profile.username
        : AccountService.usernameFromAuthEmail(authUser.email);
    final userName =
        profile.displayName.isNotEmpty ? profile.displayName : userUsername;
    final forceChange = profile.mustChangePassword;

    if (!mounted) return;

    resetTabHistory();

    if (forceChange) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ForcePasswordChangeScreen(
            userRole: role,
            userEmail: userEmail,
            userName: userName,
            userUsername: userUsername,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicDashboard(
          userRole: role,
          userEmail: userEmail,
          userName: userName,
          userUsername: userUsername,
        ),
      ),
    );
    } on AuthException catch (e) {
      debugPrint('AUTH ERROR: status=${e.statusCode} message=${e.message}');
      if (!mounted) return;
      final message = e.message.toLowerCase();

      String text;
      if (message.contains('not confirmed') ||
          message.contains('email_not_confirmed')) {
        text = 'This account has not been activated yet. '
            'Please contact the Clinic Head.';
      } else if (message.contains('invalid login') ||
          message.contains('invalid credentials') ||
          e.statusCode == '400') {
        text = 'Incorrect username or password.';
      } else if (message.contains('rate limit') ||
          message.contains('too many') ||
          e.statusCode == '429') {
        text = 'Too many attempts. Please wait a moment and try again.';
      } else {
        text = 'Unable to sign in. Please try again.';
      }
      setState(() => _error = text);
    } catch (err) {
      debugPrint('LOGIN ERROR: $err');
      if (!mounted) return;
      final text = '$err'.toLowerCase();

      String msg;
      if (text.contains('account_deactivated')) {
        msg = 'Your account has been deactivated. Please contact the Clinic Head.';
      } else if (text.contains('socket') ||
          text.contains('network') ||
          text.contains('failed host lookup') ||
          text.contains('clientexception') ||
          text.contains('timeout')) {
        msg = 'No connection. Please check your internet and try again.';
      } else {
        msg = 'Something went wrong. Please try again.';
      }
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
}

  bool _metaIsActive(User user) {
    final raw = AccountService.metadataOf(user)['is_active'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() != 'false';
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bgAlt, AppColors.primaryContainer],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
                top: -90,
                left: -70,
                child:
                    _pageBlob(240, AppColors.primary.withValues(alpha: 0.10))),
            Positioned(
                bottom: -110,
                right: -80,
                child: _pageBlob(
                    300, AppColors.secondary.withValues(alpha: 0.12))),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                              color: AppColors.shadowStrong,
                              blurRadius: 48,
                              offset: Offset(0, 24)),
                        ],
                      ),
                      child: LayoutBuilder(builder: (context, cons) {
                        final isWide = cons.maxWidth >= 720;
                        if (isWide) {
                          return IntrinsicHeight(
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 5, child: _heroPanel()),
                                  Expanded(flex: 6, child: _formPanel()),
                                ]),
                          );
                        }
                        return Column(children: [
                          _heroPanel(compact: true),
                          _formPanel(),
                        ]);
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroPanel({bool compact = false}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding:
          EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 28 : 44),
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
      child: Stack(
        children: [
          Positioned(
              top: -50,
              left: -60,
              child: _pageBlob(170, Colors.white.withValues(alpha: 0.06))),
          Positioned(
              bottom: -60,
              right: -50,
              child: _pageBlob(210, Colors.white.withValues(alpha: 0.05))),
          Positioned(
              top: 130,
              right: -35,
              child: _pageBlob(90, Colors.white.withValues(alpha: 0.05))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _logoChip('asset/tcgc.png', Icons.school_rounded),
                  const SizedBox(width: 16),
                  _logoChip(
                      'asset/cliniclogo.png', Icons.health_and_safety_rounded),
                ]),
                const SizedBox(height: 24),
                const Text('Clinic Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        height: 1.15,
                        shadows: [
                          Shadow(
                              color: Color(0x33000000),
                              blurRadius: 10,
                              offset: Offset(0, 3))
                        ])),
                const SizedBox(height: 16),
                Container(
                  width: 140,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Tangub City Global College • School Clinic',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF99F6E4),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageBlob(double size, Color color) => Container(
        height: size,
        width: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _logoChip(String path, IconData fallback) {
    return Container(
      height: 92,
      width: 92,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x2E000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      child: ClipOval(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Image.asset(path,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(fallback, color: AppColors.primary, size: 46)),
        ),
      ),
    );
  }

  Widget _formPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.secondary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text('Sign In',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDark,
                  letterSpacing: -1)),
          const SizedBox(height: 6),
          const Text('Use your clinic username and password to continue.',
              style: TextStyle(color: AppColors.textSub, fontSize: 14)),
          const SizedBox(height: 30),
          _label('Username'),
          TextField(
            controller: _usernameCtrl,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: _inputDeco(
                icon: Icons.person_outline, hint: 'Enter your username'),
          ),
          const SizedBox(height: 20),
          _label('Password'),
          TextField(
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            decoration: _inputDeco(
              icon: Icons.lock_outline_rounded,
              hint: 'Enter your password',
              suffix: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textMuted),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
           const SizedBox(height:12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _forgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Forgot password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.dangerContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                            height: 1.35))),
              ]),
            ),
          ],
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: ElevatedButton(
                onPressed: _submitting ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Sign In',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub)),
      );

  InputDecoration _inputDeco(
      {required IconData icon, String? hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.fieldFill,
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
    );
  }
}