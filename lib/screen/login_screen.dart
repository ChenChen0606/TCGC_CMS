import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'clinic_dashboard_screen.dart';
import 'force_password_change_screen.dart';
import 'app_colors.dart';
import '../services/supabase_config.dart';
import '../services/account_service.dart';
import '../services/reference_data_service.dart';

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

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
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
      // ── Resolve the typed value to the Auth email ────────────────────────
      // Staff sign in with a USERNAME, but Supabase Auth only accepts an
      // EMAIL. The address is looked up in `useraccount` first, then derived
      // as `<username>@clinic.local`. Unknown entries produce a usable but
      // non-existent address, so the generic "incorrect" error below never
      // reveals whether a username exists (no account enumeration).
      final email =
          await AccountService.resolveAuthEmailForIdentifier(username);
      if (email == null || email.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'Incorrect username or password.');
        return;
      }

      // ── Sign in ─────────────────────────────────────────────────────────
      final response = await supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final authUser = response.user;
      if (authUser == null) {
        if (!mounted) return;
        setState(() => _error = 'Unable to sign in. Please try again.');
        return;
      }

      // ── Load the account row + this user's Auth metadata ─────────────────
      // `useraccount` holds role / is_active / avatar; the person's name is
      // only in Auth metadata, so the two are joined.
      Map<String, dynamic>? accountRow;
      try {
        accountRow = await supabaseClient
            .from('useraccount')
            .select()
            .eq('user_id', authUser.id)
            .maybeSingle();
      } catch (_) {
        // Table unreadable → fall back to metadata-only below.
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

      // ── Reference data, now that there is a session to read it with ──────
      // The five reference tables are behind Row Level Security, so a read made
      // before this point comes back as an empty list rather than as an error —
      // which is why they are not read at start-up (see `ReferenceCatalog.load`)
      // and why this is the first moment they can be read properly.
      //
      // Awaited so the dashboard's first paint already has the real term,
      // institutes, programs, departments and positions. Skipping this is what
      // left the school year / semester dropdowns empty and the roster table
      // with no rows in it: with no term resolved there is no period for the
      // roster query to ask for, and neither of those shows an error.
      await ReferenceCatalog.loadAfterSignIn();

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

      if (forceChange) {
        // New account or Head reset the password → force a fresh password now.
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
      if (!mounted) return;
      final message = e.message.toLowerCase();
      if (message.contains('not confirmed') ||
          message.contains('email_not_confirmed')) {
        setState(() => _error =
            'This account has not been activated yet. Please contact the '
                'Clinic Head.');
      } else {
        setState(() => _error = 'Incorrect username or password.');
      }
    } catch (err) {
      if (!mounted) return;
      if ('$err'.contains('ACCOUNT_DEACTIVATED')) {
        setState(() => _error =
            'Your account has been deactivated. Please contact the Clinic Head.');
      } else {
        setState(() => _error = 'Incorrect username or password.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Whether the account is active according to the user's Auth metadata.
  /// Used only when the `useraccount` row cannot be read, so that a missing row
  /// is never mistaken for a deactivated account.
  bool _metaIsActive(User user) {
    final raw = AccountService.metadataOf(user)['is_active'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() != 'false';
    return true;
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ───────────────────────────────────────────────────────────────────────────
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
        child: SafeArea(
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
      ),
    );
  }

  // ── Branding / hero panel ────────────────────────────────────────────────
  Widget _heroPanel({bool compact = false}) {
    return Container(
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _logoChip('asset/tcgc.png', Icons.school_rounded),
            const SizedBox(width: 16),
            _logoChip('asset/cliniclogo.png', Icons.health_and_safety_rounded),
          ]),
          const SizedBox(height: 24),
          const Text('Clinic Management System',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.15)),
          const SizedBox(height: 8),
          const Text('Tangub City Global College • School Clinic',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF99F6E4), fontSize: 13.5)),
          const SizedBox(height: 22),
          Container(
              width: 60,
              height: 2,
              color: Colors.white.withValues(alpha: 0.35)),
          const SizedBox(height: 22),
          Text('© 2026 Tangub City Global College',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _logoChip(String path, IconData fallback) {
    return Container(
      height: 92,
      width: 92,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6))
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

  // ── Sign-in form panel ───────────────────────────────────────────────────
  Widget _formPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
            child: ElevatedButton(
              onPressed: _submitting ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Tangub City Global College • Clinic Management System',
                style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.9),
                    fontSize: 12)),
          ]),
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
