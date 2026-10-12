// ─────────────────────────────────────────────────────────────────────────────
//  force_password_change_screen.dart
//  Shown right after sign-in when the account is brand-new (Head registered it
//  with a one-time password) or the Head just reset the password. The user
//  CANNOT get into the clinic until they set their own private password.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/services/account_service.dart';
import 'clinic_dashboard_screen.dart';
import 'app_colors.dart';

class ForcePasswordChangeScreen extends StatefulWidget {
  final String userRole;
  final String userEmail;
  final String userName;
  final String userUsername;

  const ForcePasswordChangeScreen({
    super.key,
    this.userRole = 'Clinic Staff',
    this.userEmail = '',
    this.userName = '',
    this.userUsername = '',
  });

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConf = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  bool get _strongEnough {
    final v = _newCtrl.text;
    if (v.length < 10) return false;
    if (!RegExp(r'[A-Z]').hasMatch(v)) return false;
    if (!RegExp(r'[a-z]').hasMatch(v)) return false;
    if (!RegExp(r'\d').hasMatch(v)) return false;
    return true;
  }

  Future<void> _changePassword() async {
    final newPw = _newCtrl.text;
    final confPw = _confCtrl.text;

    if (!_strongEnough) {
      setState(() => _error = _pwRules());
      return;
    }
    if (newPw != confPw) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await AccountService.changePassword(newPw);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => ClinicDashboard(
            userRole: widget.userRole,
            userEmail: widget.userEmail,
            userName: widget.userName,
            userUsername: widget.userUsername,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Unable to set your password. Please try again. ($e)';
      });
    }
  }

  String _pwRules() {
    return 'Password must be at least 10 characters with an uppercase letter, '
        'a lowercase letter, and a number.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 48,
                    offset: Offset(0, 24)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: AppColors.primary, size: 26),
                ),
                const SizedBox(height: 18),
                Text(
                  'Set your own password',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your account needs a private password before you can use the '
                  'clinic system. The one-time password you were given will work '
                  'only until you change it here.',
                  style: TextStyle(
                      color: AppColors.textSub, fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 24),
                _label('New Password'),
                TextField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: _deco(
                    hint: 'At least 10 characters',
                    suffix: IconButton(
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF94A3B8),
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _strengthRow(),
                const SizedBox(height: 16),
                _label('Confirm New Password'),
                TextField(
                  controller: _confCtrl,
                  obscureText: _obscureConf,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _changePassword(),
                  decoration: _deco(
                    hint: 'Re-enter your new password',
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConf
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF94A3B8),
                      ),
                      onPressed: () =>
                          setState(() => _obscureConf = !_obscureConf),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFDC2626), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFDC2626), fontSize: 13))),
                    ]),
                  ),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Continue to Clinic',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _strengthRow() {
    final v = _newCtrl.text;

    final active = [
      _lengthOk(v),
      _caseOk(v),
      _digitOk(v),
    ];

    return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: List.generate(3, (i) {
          final ok = active[i];
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_circle : Icons.circle_outlined,
                size: 13,
                color: ok ? AppColors.primary : AppColors.borderStrong),
            const SizedBox(width: 4),
            Text(
              i == 0
                  ? '10+ chars'
                  : i == 1
                      ? 'A–z'
                      : '0–9',
              style: TextStyle(
                  fontSize: 11,
                  color: ok ? AppColors.primaryDark : AppColors.textSub),
            ),
          ]);
        }));
  }

  bool _lengthOk(String v) => v.length >= 10;
  bool _caseOk(String v) =>
      RegExp(r'[A-Z]').hasMatch(v) && RegExp(r'[a-z]').hasMatch(v);
  bool _digitOk(String v) => RegExp(r'\d').hasMatch(v);

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569))),
      );

  InputDecoration _deco({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSub, fontSize: 14),
      prefixIcon: const Icon(Icons.lock_outline_rounded,
          color: AppColors.primary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}
