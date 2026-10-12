// ignore_for_file: use_build_context_synchronously
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_service.dart';
import 'app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AccountScreen
//  • Clinic Head  → sees full user management: register, toggle active, delete
//  • Clinic Staff → sees only their own profile + change-password
// ─────────────────────────────────────────────────────────────────────────────
class AccountScreen extends StatefulWidget {
  final String userRole;
  final String userEmail;
  final String userName;
  final String userUsername;

  const AccountScreen({
    super.key,
    this.userRole = 'Clinic Staff',
    this.userEmail = '',
    this.userName = '',
    this.userUsername = '',
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // Palette (single source of truth: app_colors.dart)
  static const kTeal = AppColors.primary;
  static const kTealLight = AppColors.primaryContainer;
  static const kBg = AppColors.bgAlt;
  static const kBorder = AppColors.border;
  static const kTextDark = AppColors.textDark;
  static const kTextMuted = AppColors.textSub;
  static const kRed = AppColors.danger;
  static const kRedLight = AppColors.dangerContainer;

  bool get _isHead => widget.userRole == 'Clinic Head';

  // Local copies so the profile card updates immediately after "Update Info"
  late String _displayName;
  late String _displayUsername;
  late String _displayAvatarUrl;

  // Account list (fetched from Supabase)
  List<AppProfile> _users = [];
  bool _loadingUsers = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _displayName = widget.userName;
    _displayUsername = widget.userUsername;
    _displayAvatarUrl = '';
    _loadUsers();
    _loadOwnProfile();
  }

  // Keeps the profile card in sync with the DB (name, username, avatar).
  Future<void> _loadOwnProfile() async {
    final me = await AccountService.fetchOwn();
    if (!mounted || me == null) return;
    setState(() {
      _displayName = me.fullName.isNotEmpty ? me.fullName : me.username;
      _displayUsername = me.username;
      _displayAvatarUrl = me.avatarUrl;
    });
  }

  // Refresh the list after any mutation
  void _refresh() => _loadUsers();

  Future<void> _loadUsers() async {
    try {
      final list = await AccountService.fetchAll();
      if (!mounted) return;
      setState(() {
        _users = list;
        _loadingUsers = false;
        _loadError = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _loadError = _friendly('Unable to load accounts.', err);
      });
    }
  }

  // ── Register dialog (Head only) ───────────────────────────────────────────
  // The Head picks a username and the system AUTO-GENERATES a strong one-time
  // password. That password is shown in the dialog BEFORE the account exists,
  // and again in a one-time dialog afterwards — then it never appears again.
  // The new user is forced to set their own password on first login.
  void _showRegisterDialog() {
    final fnCtrl = TextEditingController();
    final lnCtrl = TextEditingController();
    final usCtrl = TextEditingController();
    final emCtrl = TextEditingController();
    String generatedPassword = AccountService.generatePassword();
    String role = 'Clinic Staff';
    String? errMsg;
    bool submitting = false;

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    void refreshSuggestion() {
      final suggested = AccountService.suggestUsername(
          '${fnCtrl.text.trim()} ${lnCtrl.text.trim()}');
      if (suggested.isNotEmpty &&
          !usCtrl.text.trim().toLowerCase().contains(suggested)) {
        usCtrl.text = suggested;
      }
    }

    Future<void> submit(
      void Function(void Function()) setDlg,
      BuildContext ctx,
    ) async {
      final first = fnCtrl.text.trim();
      final last = lnCtrl.text.trim();
      final newUsername = usCtrl.text.trim();
      final newEmail = emCtrl.text.trim().toLowerCase();

      if (first.isEmpty || last.isEmpty) {
        setDlg(() => errMsg = 'First and last name are required.');
        return;
      }
      if (!emailPattern.hasMatch(newEmail)) {
        setDlg(() => errMsg =
            'Enter a valid email address (e.g. jessa.robles@example.com). '
                'It is used to reset the password if it is ever forgotten.');
        return;
      }
      if (!AccountService.usernamePattern.hasMatch(newUsername)) {
        setDlg(() => errMsg =
            'Username must be 3-20 characters, start with a letter, and only '
                'use letters, numbers, dots, dashes and underscores.');
        return;
      }
      if (_users.any((u) =>
          u.username.isNotEmpty &&
          u.username.toLowerCase() == newUsername.toLowerCase())) {
        setDlg(() => errMsg = 'That username is already taken.');
        return;
      }
      // Server check too (fast, index-backed) — closes a race.
      if (!await AccountService.isUsernameAvailable(newUsername)) {
        setDlg(() => errMsg = 'That username is already taken.');
        return;
      }

      final confirm = await showDialog<bool>(
            context: ctx,
            builder: (_) => _CredentialReviewDialog(
              fullName: '$first $last',
              username: newUsername,
              email: newEmail,
              role: role,
              password: generatedPassword,
              requiresHeadVerification: role == 'Clinic Head',
            ),
          ) ??
          false;
      if (!confirm) return;

      setDlg(() {
        errMsg = null;
        submitting = true;
      });
      try {
        final created = await AccountService.register(
          firstName: first,
          lastName: last,
          username: newUsername,
          password: generatedPassword,
          role: role,
          email: newEmail,
        );
        Navigator.pop(ctx);
        _refresh();
        _showOneTimePasswordDialog(
          created,
          generatedPassword,
          reason: 'This account is now registered and active.',
        );
      } on AuthException catch (e) {
        setDlg(() {
          errMsg = _friendly('Account registration failed.', e);
          submitting = false;
        });
      } catch (e) {
        setDlg(() {
          errMsg = _friendly('Account registration failed.', e);
          submitting = false;
        });
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        final usernameOk =
            AccountService.usernamePattern.hasMatch(usCtrl.text.trim());
        final emailOk = emailPattern.hasMatch(emCtrl.text.trim());
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: kTealLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: kTeal, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Register New Account',
                      style: TextStyle(
                          color: kTextDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Create a Clinic Head or Staff login',
                      style: TextStyle(fontSize: 12, color: kTextMuted)),
                ],
              ),
            ),
          ]),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errMsg != null) ...[
                    _errorBanner(errMsg!),
                    const SizedBox(height: 16),
                  ],
                  _regSectionLabel('PERSONAL INFORMATION'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _regLabeled(
                        label: 'First name',
                        child: _dlgField(
                            fnCtrl, 'e.g. Jessa', Icons.person_outline,
                            onChanged: (_) => refreshSuggestion()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _regLabeled(
                        label: 'Last name',
                        child: _dlgField(
                            lnCtrl, 'e.g. Robles', Icons.person_outline,
                            onChanged: (_) => refreshSuggestion()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _regSectionLabel('LOGIN CREDENTIALS'),
                  const SizedBox(height: 10),
                  _regLabeled(
                    label: 'Username',
                    child: _dlgField(
                      usCtrl,
                      'e.g. jessa.robles',
                      Icons.alternate_email_outlined,
                      onChanged: (_) => setDlg(() => errMsg = null),
                      suffix: usCtrl.text.trim().isEmpty
                          ? null
                          : Icon(
                              usernameOk
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              color: usernameOk ? kTeal : kRed,
                              size: 20),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    usernameOk
                        ? 'Username is correctly formatted and available.'
                        : '3-20 characters, starts with a letter. Letters, '
                            'numbers, dots, dashes and underscores only.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: usernameOk ? kTeal : kTextMuted,
                        height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  _regLabeled(
                    label: 'Email address',
                    child: _dlgField(
                      emCtrl,
                      'e.g. jessa.robles@example.com',
                      Icons.mail_outline_rounded,
                      onChanged: (_) => setDlg(() => errMsg = null),
                      suffix: emCtrl.text.trim().isEmpty
                          ? null
                          : Icon(
                              emailOk
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              color: emailOk ? kTeal : kRed,
                              size: 20),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Used to sign in and to reset the password if it is '
                    'forgotten. Must be a real address.',
                    style: TextStyle(
                        fontSize: 11.5, color: kTextMuted, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  _regLabeled(
                    label: 'One-time password',
                    child: _regPasswordCard(
                      password: generatedPassword,
                      onRegenerate: () => setDlg(() {
                        generatedPassword = AccountService.generatePassword();
                        errMsg = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Save this password now — it is shown only once. The new '
                    'user must change it at first login.',
                    style: TextStyle(
                        fontSize: 11.5, color: kTextMuted, height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  _regSectionLabel('ACCOUNT ROLE'),
                  const SizedBox(height: 10),
                  _regRoleCard(
                    title: 'Clinic Staff',
                    subtitle: 'Day-to-day clinic tasks',
                    icon: Icons.badge_outlined,
                    selected: role == 'Clinic Staff',
                    onTap: () => setDlg(() => role = 'Clinic Staff'),
                  ),
                  const SizedBox(height: 10),
                  _regRoleCard(
                    title: 'Clinic Head',
                    subtitle: 'Full access, including user management',
                    icon: Icons.workspace_premium_outlined,
                    selected: role == 'Clinic Head',
                    onTap: () => setDlg(() => role = 'Clinic Head'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: kTextMuted),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: submitting ? null : () => submit(setDlg, ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              icon: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(
                submitting ? 'Registering…' : 'Register Account',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ── Register-dialog helpers ───────────────────────────────────────────────
  Widget _regSectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: kTextMuted,
              letterSpacing: 1.1),
        ),
      );

  Widget _regLabeled({required String label, required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kTextDark)),
          ),
          child,
        ],
      );

  Widget _regPasswordCard({
    required String password,
    required VoidCallback onRegenerate,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: kTealLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kTeal.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.shield_outlined, color: kTeal, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(password,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                  letterSpacing: 1.1)),
        ),
        IconButton(
          tooltip: 'Copy password',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: password));
            _toast('Password copied. Paste it somewhere safe.');
          },
          icon: const Icon(Icons.copy_rounded, color: kTeal, size: 18),
        ),
        IconButton(
          tooltip: 'Generate new password',
          visualDensity: VisualDensity.compact,
          onPressed: onRegenerate,
          icon: const Icon(Icons.refresh_rounded, color: kTeal, size: 20),
        ),
      ]),
    );
  }

  Widget _regRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kTealLight : kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? kTeal : kBorder, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? kTeal : kTextMuted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? kTeal : kTextDark)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11.5, color: kTextMuted)),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? kTeal : kBorder,
            size: 20,
          ),
        ]),
      ),
    );
  }

  // Shows a generated password EXACTLY once, with a copy button. Used after
  // registering an account and after a Head-initiated password reset. The
  // password is not stored anywhere client-side, so this dialog is the only
  // chance to hand it over.
  void _showOneTimePasswordDialog(AppProfile user, String password,
      {required String reason}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('One-time Password',
            style: TextStyle(color: kTeal, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: kTextDark)),
                const SizedBox(height: 4),
                Text(reason,
                    style: const TextStyle(fontSize: 12.5, color: kTextMuted)),
                const SizedBox(height: 16),
                _copyTile(label: 'Username', value: user.username),
                if (user.email.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _copyTile(label: 'Email', value: user.email),
                ],
                const SizedBox(height: 10),
                _copyTile(label: 'Password', value: password, sensitive: true),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorder)),
                  child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFF59E0B), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                          'This password is shown only once and cannot be recovered later. '
                          'The user will be required to set their own password at first login.',
                          style: TextStyle(
                              fontSize: 12, color: kTextMuted, height: 1.4),
                        )),
                      ]),
                ),
              ]),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("I've saved it",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Tappable credential row used by the one-time credential dialogs so the
  // Head can copy BOTH the username and the password with one tap.
  Widget _copyTile({
    required String label,
    required String value,
    bool sensitive = false,
  }) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        _toast('$label copied. Paste it somewhere safe.');
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kTealLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kTeal.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.copy_rounded, color: kTeal, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: kTeal,
                        letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kTextDark,
                        letterSpacing: sensitive ? 1.1 : 0.4)),
              ])),
        ]),
      ),
    );
  }

  // ── Delete confirmation ───────────────────────────────────────────────────
  void _confirmDelete(AppProfile user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account',
            style: TextStyle(color: kRed, fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
              style:
                  const TextStyle(color: kTextDark, fontSize: 14, height: 1.5),
              children: [
                const TextSpan(
                    text: 'Are you sure you want to permanently delete '),
                TextSpan(
                    text: user.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(text: "'s account? This cannot be undone."),
              ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: kTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AccountService.delete(user.id);
                _refresh();
                _toast('${user.fullName}\'s account has been deleted.');
              } catch (e) {
                _toastError(_friendly('Unable to delete account.', e));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Update Personal Info dialog (all users) ─────────────────────────────
  // Personal details (name + contact) are editable by every user. The login
  // USERNAME is shown read-only here — changing it is a separate, verified
  // action (requires the current password) to keep it secure.
  Future<void> _showUpdatePersonalInfoDialog() async {
    final me = await AccountService.fetchOwn();
    if (!mounted) return;
    if (me == null) {
      _toastError('Unable to load your profile. Please sign in again.');
      return;
    }

    final fnCtrl = TextEditingController(text: me.firstName);
    final mnCtrl = TextEditingController(text: me.middleName);
    final lnCtrl = TextEditingController(text: me.lastName);
    String? errMsg;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Update Personal Info',
              style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Avatar preview
                Center(
                  child: _avatar(
                    radius: 36,
                    url: me.avatarUrl,
                    initials: me.firstName.isNotEmpty ? me.firstName[0] : '?',
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 20),

                if (errMsg != null) ...[
                  _errorBanner(errMsg!),
                  const SizedBox(height: 12)
                ],

                Row(children: [
                  Expanded(
                      child: _dlgField(
                          fnCtrl, 'First Name', Icons.person_outline)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _dlgField(mnCtrl, 'Middle Name (optional)',
                          Icons.badge_outlined)),
                ]),
                const SizedBox(height: 12),
                _dlgField(lnCtrl, 'Last Name', Icons.person_outline),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(children: [
                    const Icon(Icons.alternate_email_outlined,
                        color: kTeal, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('USERNAME',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: kTextMuted,
                                  letterSpacing: 1)),
                          Text(me.username.isEmpty ? '(none)' : me.username,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: kTextDark)),
                        ])),
                  ]),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: kTextMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final newFirst = fnCtrl.text.trim();
                      final newLast = lnCtrl.text.trim();

                      if (newFirst.isEmpty || newLast.isEmpty) {
                        setDlg(() =>
                            errMsg = 'First and last name cannot be empty.');
                        return;
                      }

                      setDlg(() {
                        errMsg = null;
                        submitting = true;
                      });
                      try {
                        await AccountService.updateOwnProfile(
                          firstName: newFirst,
                          middleName: mnCtrl.text,
                          lastName: newLast,
                        );
                        Navigator.pop(ctx);
                        // Update local display state so profile card refreshes immediately
                        setState(() {
                          _displayName = [newFirst, mnCtrl.text.trim(), newLast]
                              .where((s) => s.isNotEmpty)
                              .join(' ');
                        });
                        _refresh();
                        _toast('Personal info updated successfully.');
                      } on AuthException catch (e) {
                        setDlg(() {
                          errMsg = _friendly('Unable to update your info.', e);
                          submitting = false;
                        });
                      } catch (e) {
                        setDlg(() {
                          errMsg = _friendly('Unable to update your info.', e);
                          submitting = false;
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ── Profile picture dialog (optional, self-serve) ─────────────────────────
  // Lets ANY user pick an image from their device, preview it, and upload it
  // to the `avatars` bucket (stored under their own user id). They can also
  // remove it again. Fully optional — the initials fallback is always shown.
  Future<void> _showUpdateAvatarDialog() async {
    final me = await AccountService.fetchOwn();
    if (!mounted) return;
    if (me == null) {
      _toastError('Unable to load your profile. Please sign in again.');
      return;
    }

    Uint8List? pickedBytes;
    String pickedExt = 'png';
    String? errMsg;
    bool uploading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        Widget preview;
        if (pickedBytes != null) {
          preview = ClipOval(
            child: SizedBox(
              width: 110,
              height: 110,
              child: Image.memory(pickedBytes!, fit: BoxFit.cover),
            ),
          );
        } else if (me.avatarUrl.isNotEmpty) {
          preview = ClipOval(
            child: SizedBox(
              width: 110,
              height: 110,
              child: Image.network(me.avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _InitialPreview()),
            ),
          );
        } else {
          preview = _InitialPreview(name: me.firstName);
        }

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Profile Picture',
              style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Center(child: preview),
                const SizedBox(height: 16),
                if (errMsg != null) ...[
                  _errorBanner(errMsg!),
                  const SizedBox(height: 12)
                ],
                const Text(
                  'Optional — add a photo so your teammates recognize you. '
                  'You can change or remove it anytime.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12.5, color: kTextMuted, height: 1.4),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: uploading
                      ? null
                      : () async {
                          const typeGroup = XTypeGroup(
                            label: 'Images',
                            extensions: [
                              'png',
                              'jpg',
                              'jpeg',
                              'gif',
                              'webp',
                              'bmp'
                            ],
                            uniformTypeIdentifiers: [
                              'public.image',
                              'public.png',
                              'public.jpeg',
                              'com.compuserve.gif',
                            ],
                          );
                          final file =
                              await openFile(acceptedTypeGroups: [typeGroup]);
                          if (file == null) return;
                          final bytes = await file.readAsBytes();
                          if (bytes.length > 5 * 1024 * 1024) {
                            if (ctx.mounted) {
                              setDlg(() =>
                                  errMsg = 'Image is too large (max 5 MB).');
                            }
                            return;
                          }
                          final name = file.name.toLowerCase();
                          pickedExt = name.endsWith('.jpg')
                              ? 'jpg'
                              : name.endsWith('.jpeg')
                                  ? 'jpeg'
                                  : name.endsWith('.gif')
                                      ? 'gif'
                                      : name.endsWith('.webp')
                                          ? 'webp'
                                          : name.endsWith('.bmp')
                                              ? 'bmp'
                                              : 'png';
                          setDlg(() {
                            pickedBytes = bytes;
                            errMsg = null;
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTeal,
                    side: const BorderSide(color: kTeal),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(
                      pickedBytes == null ? 'Choose Image' : 'Change Image'),
                ),
              ]),
            ),
          ),
          actions: [
            if (me.avatarUrl.isNotEmpty || pickedBytes != null)
              TextButton(
                onPressed: uploading
                    ? null
                    : () async {
                        setDlg(() {
                          errMsg = null;
                          uploading = true;
                        });
                        try {
                          await AccountService.removeOwnAvatar();
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (mounted) {
                            setState(() => _displayAvatarUrl = '');
                            _toast('Profile picture removed.');
                          }
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDlg(() {
                            errMsg = _friendly('Unable to remove picture.', e);
                            uploading = false;
                          });
                        }
                      },
                style: TextButton.styleFrom(foregroundColor: kRed),
                child: const Text('Remove Picture'),
              ),
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: kTextMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: uploading
                  ? null
                  : () async {
                      if (pickedBytes == null) {
                        setDlg(() => errMsg = 'Choose an image first.');
                        return;
                      }
                      setDlg(() {
                        errMsg = null;
                        uploading = true;
                      });
                      try {
                        final url = await AccountService.uploadOwnAvatar(
                          pickedBytes!,
                          extension: pickedExt,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (mounted) {
                          setState(() => _displayAvatarUrl = url);
                          _toast('Profile picture updated.');
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDlg(() {
                          errMsg = _friendly('Unable to upload picture.', e);
                          uploading = false;
                        });
                      }
                    },
              child: uploading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Picture',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ── Change Username dialog ────────────────────────────────────────────────
  // Username is the login key, so changing it is gated behind the current
  // password (verification) + a unique server-side check.
  void _showChangeUsernameDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final curCtrl = TextEditingController();
        final usCtrl = TextEditingController();
        String? errMsg;
        bool obscure = true;
        bool submitting = false;

        return StatefulBuilder(builder: (ctx, setDlg) {
          Future<void> save() async {
            final newUsername = usCtrl.text.trim();
            if (!AccountService.usernamePattern.hasMatch(newUsername)) {
              setDlg(() => errMsg =
                  'Username must be 3-20 characters, start with a letter, '
                      'and only use letters, numbers, dots, dashes, underscores.');
              return;
            }
            if (!await AccountService.isUsernameAvailable(newUsername)) {
              setDlg(() => errMsg = 'That username is already taken.');
              return;
            }
            if (!await AccountService.verifyPassword(curCtrl.text)) {
              setDlg(() => errMsg = 'Current password is incorrect.');
              return;
            }
            setDlg(() {
              errMsg = null;
              submitting = true;
            });
            try {
              await AccountService.updateOwnUsername(newUsername);
              Navigator.pop(ctx);
              setState(() => _displayUsername = newUsername.toLowerCase());
              _refresh();
              _toast(
                  'Username updated. Use "$newUsername" to sign in from now on.');
            } on AuthException catch (e) {
              setDlg(() {
                errMsg = _friendly('Unable to change username.', e);
                submitting = false;
              });
            } catch (e) {
              setDlg(() {
                errMsg = _friendly('Unable to change username.', e);
                submitting = false;
              });
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Change Username',
                style:
                    TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (errMsg != null) _errorBanner(errMsg!),
                  const SizedBox(height: 8),
                  _dlgField(
                    curCtrl,
                    'Current Password',
                    Icons.lock_open_outlined,
                    obscure: obscure,
                    suffix: IconButton(
                      icon: Icon(
                          obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: kTextMuted),
                      onPressed: () => setDlg(() => obscure = !obscure),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dlgField(
                      usCtrl, 'New Username', Icons.alternate_email_outlined,
                      onChanged: (_) => setDlg(() => errMsg = null)),
                ]),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(color: kTextMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kTeal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: submitting ? null : save,
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // ── Change-email dialog ────────────────────────────────────────────────────
  // Email is the login + password-recovery address, so it is gated behind the
  // current password and written to Auth + `useraccount` together.
  void _showChangeEmailDialog() {
    final curCtrl = TextEditingController();
    final emCtrl = TextEditingController();
    String? errMsg;
    bool obscure = true;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        Future<void> save() async {
          final newEmail = emCtrl.text.trim();
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(newEmail)) {
            setDlg(() => errMsg = 'Enter a valid email address.');
            return;
          }
          setDlg(() {
            errMsg = null;
            submitting = true;
          });
          try {
            await AccountService.updateOwnEmail(newEmail,
                verifier: curCtrl.text);
            Navigator.pop(ctx);
            _refresh();
            _toast('Email updated to "$newEmail".');
          } on AuthException catch (e) {
            setDlg(() {
              errMsg = _friendly('Unable to change email.', e);
              submitting = false;
            });
          } catch (e) {
            setDlg(() {
              errMsg = _friendly('Unable to change email.', e);
              submitting = false;
            });
          }
        }

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Change Email',
              style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errMsg != null) _errorBanner(errMsg!),
                const SizedBox(height: 8),
                _dlgField(
                  curCtrl,
                  'Current Password',
                  Icons.lock_open_outlined,
                  obscure: obscure,
                  onChanged: (_) => setDlg(() => errMsg = null),
                  suffix: IconButton(
                    icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: kTextMuted),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
                const SizedBox(height: 12),
                _dlgField(emCtrl, 'New Email', Icons.mail_outline_rounded,
                    onChanged: (_) => setDlg(() => errMsg = null)),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Used to sign in and to reset the password if it is '
                    'forgotten.',
                    style: TextStyle(
                        fontSize: 11.5, color: kTextMuted, height: 1.4),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child:
                    const Text('Cancel', style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: submitting ? null : save,
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ── Change-password dialog ────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool obscureCur = true;
    bool obscureNew = true;
    bool obscureConf = true;
    String? errMsg;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Change Password',
              style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errMsg != null) _errorBanner(errMsg!),
                const SizedBox(height: 8),
                _dlgField(
                  curCtrl,
                  'Current Password',
                  Icons.lock_open_outlined,
                  obscure: obscureCur,
                  suffix: IconButton(
                    icon: Icon(
                        obscureCur
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: kTextMuted),
                    onPressed: () => setDlg(() => obscureCur = !obscureCur),
                  ),
                ),
                const SizedBox(height: 12),
                _dlgField(
                  newCtrl,
                  'New Password',
                  Icons.vpn_key_outlined,
                  obscure: obscureNew,
                  suffix: IconButton(
                    icon: Icon(
                        obscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: kTextMuted),
                    onPressed: () => setDlg(() => obscureNew = !obscureNew),
                  ),
                ),
                const SizedBox(height: 12),
                _dlgField(
                  confCtrl,
                  'Confirm New Password',
                  Icons.lock_reset,
                  obscure: obscureConf,
                  suffix: IconButton(
                    icon: Icon(
                        obscureConf
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: kTextMuted),
                    onPressed: () => setDlg(() => obscureConf = !obscureConf),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child:
                    const Text('Cancel', style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: submitting
                  ? null
                  : () async {
                      setDlg(() {
                        errMsg = null;
                        submitting = true;
                      });
                      try {
                        final ok =
                            await AccountService.verifyPassword(curCtrl.text);
                        if (!ok) {
                          setDlg(() {
                            errMsg = 'Current password is incorrect.';
                            submitting = false;
                          });
                          return;
                        }
                        if (newCtrl.text.length < 10 ||
                            !RegExp(r'[A-Z]').hasMatch(newCtrl.text) ||
                            !RegExp(r'[a-z]').hasMatch(newCtrl.text) ||
                            !RegExp(r'\d').hasMatch(newCtrl.text)) {
                          setDlg(() {
                            errMsg =
                                'New password must be at least 10 characters with '
                                'an uppercase letter, a lowercase letter, and a number.';
                            submitting = false;
                          });
                          return;
                        }
                        if (newCtrl.text != confCtrl.text) {
                          setDlg(() {
                            errMsg = 'Passwords do not match.';
                            submitting = false;
                          });
                          return;
                        }
                        await AccountService.changePassword(newCtrl.text);
                        Navigator.pop(ctx);
                        _toast('Password changed successfully.');
                      } on AuthException catch (e) {
                        setDlg(() {
                          errMsg = _friendly('Unable to change password.', e);
                          submitting = false;
                        });
                      } catch (e) {
                        setDlg(() {
                          errMsg = _friendly('Unable to change password.', e);
                          submitting = false;
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: LayoutBuilder(builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        final sidePadding = isDesktop ? constraints.maxWidth * 0.03 : 10.0;

        return Column(children: [
          _header(isDesktop),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.symmetric(horizontal: sidePadding, vertical: 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── My profile card ──
                    _sectionLabel('MY ACCOUNT'),
                    const SizedBox(height: 12),
                    _myProfileCard(),
                    const SizedBox(height: 12),
                    _settingsGroup([
                      _actionTile(
                          'Update Personal Info',
                          'Edit your name and contact',
                          Icons.badge_outlined,
                          _showUpdatePersonalInfoDialog),
                      Divider(height: 1, color: kBorder, indent: 60),
                      _actionTile(
                          'Change Username',
                          'Secured with your current password. It is your login key',
                          Icons.alternate_email_outlined,
                          _showChangeUsernameDialog),
                      Divider(height: 1, color: kBorder, indent: 60),
                      _actionTile(
                          'Change Email',
                          'Used to sign in and to reset your password',
                          Icons.mail_outline_rounded,
                          _showChangeEmailDialog),
                      Divider(height: 1, color: kBorder, indent: 60),
                      _actionTile(
                          'Change Password',
                          'Update your current login credentials',
                          Icons.lock_outline_rounded,
                          _showChangePasswordDialog),
                    ]),

                    // ── User management (Head only) ──
                    if (_isHead) ...[
                      const SizedBox(height: 32),
                      Row(children: [
                        Expanded(child: _sectionLabel('USER ACCOUNTS')),
                        ElevatedButton.icon(
                          onPressed: _showRegisterDialog,
                          icon: const Icon(Icons.person_add_alt_1, size: 16),
                          label: const Text('Register Account'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _userListCard(),
                    ],

                    const SizedBox(height: 48),
                    Center(
                        child: Text('TCGC Clinic Management System • v2.1.0',
                            style: TextStyle(
                                color: kTextMuted.withValues(alpha: 0.6),
                                fontSize: 11))),
                  ]),
            ),
          ),
        ]);
      }),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(bool isDesktop) {
    final title = _isHead ? 'Account & User Management' : 'My Account';
    final icon =
        _isHead ? Icons.manage_accounts_outlined : Icons.person_outline;
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(children: [
        Icon(icon, color: kTeal),
        const SizedBox(width: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark)),
        const Spacer(),
        if (_isHead)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: kTealLight, borderRadius: BorderRadius.circular(8)),
            child: const Text('Clinic Head',
                style: TextStyle(
                    color: kTeal, fontSize: 12, fontWeight: FontWeight.bold)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBorder)),
            child: Text(widget.userRole,
                style: const TextStyle(
                    color: kTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }

  // ── My profile ────────────────────────────────────────────────────────────
  Widget _myProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        InkWell(
          key: const ValueKey('edit-avatar'),
          borderRadius: BorderRadius.circular(30),
          onTap: _showUpdateAvatarDialog,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _avatar(
                radius: 30,
                url: _displayAvatarUrl,
                initials: _displayName.isNotEmpty
                    ? _displayName[0].toUpperCase()
                    : '?',
                fontSize: 24,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: kTeal,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 2)),
                  ),
                  child: const Icon(Icons.photo_camera_outlined,
                      color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_displayName,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark)),
          Text(widget.userRole,
              style: const TextStyle(
                  color: kTeal, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_displayUsername.isEmpty ? '(no username)' : _displayUsername,
              style: const TextStyle(color: kTextMuted, fontSize: 13)),
        ]),
      ]),
    );
  }

  // Renders either the person's uploaded profile picture or their initial.
  // Falls back gracefully if the stored image URL can't be loaded.
  Widget _avatar({
    required double radius,
    required String initials,
    String url = '',
    double fontSize = 20,
  }) {
    final letter = initials.isNotEmpty ? initials[0].toUpperCase() : '?';
    Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: kTealLight,
      child: Text(letter,
          style: TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.bold, color: kTeal)),
    );

    if (url.trim().isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          url.trim(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }

  // ── User list (Head only) ─────────────────────────────────────────────────
  Widget _userListCard() {
    if (_loadingUsers) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder)),
        child: const Center(child: CircularProgressIndicator(color: kTeal)),
      );
    }

    if (_loadError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder)),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.error_outline, color: kRed, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_loadError!,
                    style: const TextStyle(color: kRed, fontSize: 13))),
          ]),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
        ]),
      );
    }

    final users = _users;

    if (users.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder)),
        child: const Center(
            child: Text('No accounts yet. Register the first one!',
                style: TextStyle(color: kTextMuted))),
      );
    }

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
      child: Column(children: [
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Expanded(
                flex: 3,
                child: Text('NAME',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kTextMuted,
                        letterSpacing: 1))),
            const Expanded(
                flex: 3,
                child: Text('USERNAME',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kTextMuted,
                        letterSpacing: 1))),
            const Expanded(
                flex: 2,
                child: Text('ROLE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kTextMuted,
                        letterSpacing: 1))),
            const SizedBox(
                width: 100,
                child: Text('STATUS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kTextMuted,
                        letterSpacing: 1))),
            const SizedBox(
                width: 60,
                child: Text('', // actions col
                    textAlign: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, color: kBorder),

        // Rows
        ...users.asMap().entries.map((e) {
          final i = e.key;
          final user = e.value;
          final isMe = user.id == AccountService.currentUserId;
          return Column(children: [
            _userRow(user, isMe),
            if (i < users.length - 1)
              const Divider(
                  height: 1, color: kBorder, indent: 20, endIndent: 20),
          ]);
        }),
      ]),
    );
  }

  Widget _userRow(AppProfile user, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        // Name
        Expanded(
            flex: 3,
            child: Row(children: [
              _avatar(
                radius: 16,
                url: user.avatarUrl,
                initials: user.firstName.isNotEmpty ? user.firstName[0] : '?',
                fontSize: 13,
              ),
              const SizedBox(width: 10),
              Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(user.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: kTextDark),
                        overflow: TextOverflow.ellipsis),
                    if (isMe)
                      const Text('(you)',
                          style: TextStyle(fontSize: 11, color: kTeal)),
                  ])),
            ])),

        // Username
        Expanded(
            flex: 3,
            child: Text(user.username.isEmpty ? '(none)' : user.username,
                style: const TextStyle(
                    fontSize: 13,
                    color: kTextMuted,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis)),

        // Role chip
        Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: user.role == 'Clinic Head'
                    ? const Color(0xFFEFF6FF)
                    : kTealLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(user.role,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: user.role == 'Clinic Head'
                          ? const Color(0xFF2563EB)
                          : kTeal)),
            )),

        // Active toggle
        SizedBox(
            width: 100,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Switch.adaptive(
                value: user.isActive,
                activeTrackColor: kTeal,
                onChanged: isMe
                    ? null
                    : (next) async {
                        // can't deactivate yourself
                        try {
                          await AccountService.setActive(user.id, next);
                          if (!mounted) return;
                          setState(() => user.isActive = next);
                          _toast(next
                              ? '${user.fullName} has been activated.'
                              : '${user.fullName} has been deactivated.');
                        } catch (e) {
                          if (!mounted) return;
                          _toastError(
                              _friendly('Unable to update account status.', e));
                        }
                      },
              ),
              const SizedBox(width: 4),
              Text(user.isActive ? 'Active' : 'Off',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: user.isActive ? kTeal : kTextMuted)),
            ])),

        // Reset password + Delete
        SizedBox(
            width: 96,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (!isMe) ...[
                IconButton(
                  tooltip: 'Reset password',
                  icon: const Icon(Icons.lock_reset_rounded,
                      color: kTeal, size: 20),
                  onPressed: () => _confirmResetPassword(user),
                ),
                IconButton(
                  tooltip: 'Delete account',
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: kRed, size: 20),
                  onPressed: () => _confirmDelete(user),
                ),
              ],
            ])),
      ]),
    );
  }

  // ── Head: confirm + reset another user's password (secure, verified) ─────
  // The Clinic Head must re-enter their OWN current password before a reset is
  // allowed. That password is verified client-side AND again server-side by the
  // 3-arg `admin_reset_password` RPC (the migration deploys the overload), so a
  // stolen session alone is never enough to reset a staff account.
  void _confirmResetPassword(AppProfile user) {
    final verifierCtrl = TextEditingController();
    bool obscure = true;
    String? errMsg;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Reset Password',
              style: TextStyle(color: kTeal, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errMsg != null) ...[
                  _errorBanner(errMsg!),
                  const SizedBox(height: 12),
                ],
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        color: kTextDark, fontSize: 14, height: 1.5),
                    children: [
                      const TextSpan(text: 'Reset the password for '),
                      TextSpan(
                          text: user.fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(
                          text: '? A new one-time password will be '
                              'generated and shown to you once. Their current session '
                              'will be signed out and they must set their own password '
                              'at next login.'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _dlgField(
                  verifierCtrl,
                  'Enter your password to verify',
                  Icons.lock_open_outlined,
                  obscure: obscure,
                  suffix: IconButton(
                    icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: kTextMuted),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Secure verification: confirm with the Clinic Head password '
                    'before a password is changed.',
                    style: TextStyle(
                        fontSize: 11.5, color: kTextMuted, height: 1.4),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: kTextMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: submitting
                  ? null
                  : () async {
                      final verifier = verifierCtrl.text;
                      if (verifier.isEmpty) {
                        setDlg(() => errMsg =
                            'Enter your password to verify this reset.');
                        return;
                      }
                      setDlg(() {
                        errMsg = null;
                        submitting = true;
                      });
                      // Client-side verification of the Head's own password.
                      final verified =
                          await AccountService.verifyPassword(verifier);
                      if (!mounted) return;
                      if (!verified) {
                        setDlg(() {
                          errMsg =
                              'Verification failed. Your password is incorrect.';
                          submitting = false;
                        });
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        final temp = await AccountService.resetPasswordFor(
                          user.id,
                          verifier: verifier,
                        );
                        if (!mounted) return;
                        _showOneTimePasswordDialog(
                          user,
                          temp,
                          reason:
                              'Password reset after verification. They must change it at next login.',
                        );
                      } catch (e) {
                        if (!mounted) return;
                        _toastError(_friendly('Unable to reset password.', e));
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Verify & Reset',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMuted,
          letterSpacing: 1.2));

  Widget _settingsGroup(List<Widget> children) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder)),
        child: Column(children: children),
      );

  Widget _actionTile(
          String title, String sub, IconData icon, VoidCallback onTap) =>
      ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: kTeal, size: 22)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: kTextDark)),
        subtitle:
            Text(sub, style: const TextStyle(fontSize: 12, color: kTextMuted)),
        trailing:
            const Icon(Icons.chevron_right_rounded, size: 20, color: kBorder),
      );

  Widget _dlgField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: kTeal, size: 20),
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: kBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kTeal, width: 2)),
      ),
    );
  }

  Widget _errorBanner(String msg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: kRedLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFECACA))),
        child: Row(children: [
          const Icon(Icons.error_outline, color: kRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(msg, style: const TextStyle(color: kRed, fontSize: 13))),
        ]),
      );

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: kTeal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  void _toastError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: kRed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  /// Maps Supabase exceptions to a clear, human-friendly message.
  String _friendly(String fallback, Object err) {
    final s = err is AuthException ? err.message : '$err';
    final lower = s.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('already exists') ||
        lower.contains('already taken') ||
        lower.contains('duplicate')) {
      return 'That username is already taken by another account.';
    }
    if (lower.contains('null value in column "id"') ||
        lower.contains('23502')) {
      return 'The account database needs a one-time fix before new '
          'accounts can be saved. Please run the account-registration '
          'migration in Supabase, then try again.';
    }
    if (lower.contains('relation "public.profiles" does not exist') ||
        lower.contains('42p01')) {
      return 'The account database is out of date (a helper table is '
          'missing). Please run the account-registration migration in '
          'Supabase, then try again.';
    }
    if (lower.contains('verification failed') ||
        lower.contains('your password is incorrect')) {
      return 'Current password is incorrect.';
    }
    if (lower.contains('already used by another account')) {
      return 'That email is already used by another account.';
    }
    if (lower.contains('re-authentication') ||
        lower.contains('reauthentication')) {
      return 'Please sign in again before making this change.';
    }
    if (lower.contains('row level security') ||
        lower.contains('permission denied') ||
        lower.contains('new row violates')) {
      return 'You are not allowed to do that. Only the Clinic Head can manage accounts.';
    }
    final trimmed = s.trim();
    return trimmed.isNotEmpty ? trimmed : fallback;
  }
}

// ── CREDENTIAL REVIEW DIALOG (for Register) ──────────────────────────────
// Shows the new account's USERNAME + generated PASSWORD prominently BEFORE the
// account is created, so the Clinic Head can write them down and Exit whenever
// they want (exiting does NOT create the account). When registering a NEW
// Clinic Head, the current Head must first verify with their OWN password —
// secure verification for a privileged account.
class _CredentialReviewDialog extends StatefulWidget {
  final String fullName;
  final String username;
  final String email;
  final String role;
  final String password;
  final bool requiresHeadVerification;

  const _CredentialReviewDialog({
    required this.fullName,
    required this.username,
    required this.email,
    required this.role,
    required this.password,
    required this.requiresHeadVerification,
  });

  @override
  State<_CredentialReviewDialog> createState() =>
      _CredentialReviewDialogState();
}

class _CredentialReviewDialogState extends State<_CredentialReviewDialog> {
  static const _teal = Color(0xFF0D9488);
  static const _tealLight = Color(0xFFCCFBF1);
  static const _textDark = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _red = Color(0xFFDC2626);
  static const _redLight = Color(0xFFFEF2F2);

  final _verifierCtrl = TextEditingController();
  bool _obscure = true;
  bool _verifying = false;
  String? _error;

  bool get _needsVerify => widget.requiresHeadVerification;

  @override
  void dispose() {
    _verifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_needsVerify) {
      if (_verifierCtrl.text.trim().isEmpty) {
        setState(() => _error =
            'Enter your password to authorize this new Clinic Head account.');
        return;
      }
      setState(() {
        _verifying = true;
        _error = null;
      });
      final ok = await AccountService.verifyPassword(_verifierCtrl.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _verifying = false;
          _error = 'Verification failed. Your password is incorrect.';
        });
        return;
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied. Paste it somewhere safe.'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _teal,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration:
                  BoxDecoration(color: _tealLight, shape: BoxShape.circle),
              child: const Icon(Icons.vpn_key_rounded, color: _teal, size: 26),
            ),
            const SizedBox(height: 16),
            const Text('New Account Credentials',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textDark)),
            const SizedBox(height: 6),
            Text('${widget.fullName} • ${widget.role}',
                style: const TextStyle(fontSize: 13.5, color: _textMuted)),
            const SizedBox(height: 18),

            // Username
            _credField(
              label: 'USERNAME (login key)',
              value: widget.username,
              onTap: () => _copy(widget.username, 'Username'),
            ),
            const SizedBox(height: 10),
            // Email (login + password recovery)
            _credField(
              label: 'EMAIL',
              value: widget.email,
              onTap: () => _copy(widget.email, 'Email'),
            ),
            const SizedBox(height: 10),
            // Generated password
            _credField(
              label: 'ONE-TIME PASSWORD',
              value: widget.password,
              sensitive: true,
              onTap: () => _copy(widget.password, 'Password'),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFF59E0B), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      'Write these down now — they are shown only once and the '
                      'password disappears after the account is created. The new '
                      'user will set their own password at first login.',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                    )),
                  ]),
            ),

            if (_needsVerify) ...[
              const SizedBox(height: 18),
              if (_error != null) ...[
                _errorBanner(_error!),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _verifierCtrl,
                obscureText: _obscure,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.verified_user_outlined,
                      color: _teal, size: 20),
                  hintText: 'Enter your password to verify',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: _textMuted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _teal, width: 2)),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Secure verification: creating another Clinic Head requires '
                  'your current password.',
                  style:
                      TextStyle(fontSize: 11.5, color: _textMuted, height: 1.4),
                ),
              ),
            ] else if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBanner(_error!),
            ],

            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed:
                    _verifying ? null : () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _border),
                  foregroundColor: _textMuted,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Exit'),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton(
                onPressed: _verifying ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _verifying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Create Account',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _credField({
    required String label,
    required String value,
    bool sensitive = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _tealLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _teal.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.copy_rounded, color: _teal, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _teal,
                        letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                        letterSpacing: sensitive ? 1.1 : 0.4)),
              ])),
        ]),
      ),
    );
  }

  Widget _errorBanner(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: _redLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFECACA))),
        child: Row(children: [
          const Icon(Icons.error_outline, color: _red, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(msg, style: const TextStyle(color: _red, fontSize: 13))),
        ]),
      );
}

// ── PLAIN INITIALS PREVIEW (used when no profile picture exists yet) ──────
class _InitialPreview extends StatelessWidget {
  final String name;

  const _InitialPreview({this.name = ''});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0D9488);
    const tealLight = Color(0xFFCCFBF1);
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 55,
      backgroundColor: tealLight,
      child: Text(letter,
          style: const TextStyle(
              fontSize: 42, fontWeight: FontWeight.bold, color: teal)),
    );
  }
}
