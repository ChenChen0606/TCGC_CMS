// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'userstore.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AccountScreen
//  • Clinic Head  → sees full user management: register, toggle active, delete
//  • Clinic Staff → sees only their own profile + change-password
// ─────────────────────────────────────────────────────────────────────────────
class AccountScreen extends StatefulWidget {
  final String userRole;
  final String userEmail;
  final String userName;

  const AccountScreen({
    super.key,
    this.userRole  = 'Clinic Staff',
    this.userEmail = '',
    this.userName  = '',
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // Palette
  static const kTeal      = Color(0xFF008080);
  static const kTealLight = Color(0xFFE6F2F2);
  static const kBg        = Color(0xFFF8FAFC);
  static const kBorder    = Color(0xFFE2E8F0);
  static const kTextDark  = Color(0xFF1E293B);
  static const kTextMuted = Color(0xFF64748B);
  static const kRed       = Color(0xFFDC2626);
  static const kRedLight  = Color(0xFFFEF2F2);

  bool get _isHead => widget.userRole == 'Clinic Head';

  // Local copies so the profile card updates immediately after "Update Info"
  late String _displayName;
  late String _displayEmail;

  @override
  void initState() {
    super.initState();
    _displayName  = widget.userName;
    _displayEmail = widget.userEmail;
  }

  // Refresh the list after any mutation
  void _refresh() => setState(() {});

  // ── Register dialog (Head only) ───────────────────────────────────────────
  void _showRegisterDialog() {
    final fnCtrl   = TextEditingController();
    final lnCtrl   = TextEditingController();
    final emCtrl   = TextEditingController();
    final pwCtrl   = TextEditingController();
    final cpwCtrl  = TextEditingController();
    String role    = 'Clinic Staff';
    String? errMsg;
    bool obscurePw = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Register New Account',
            style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errMsg != null)
                  _errorBanner(errMsg!),
                const SizedBox(height: 8),

                Row(children: [
                  Expanded(child: _dlgField(fnCtrl,  'First Name',    Icons.person_outline)),
                  const SizedBox(width: 10),
                  Expanded(child: _dlgField(lnCtrl,  'Last Name',     Icons.person_outline)),
                ]),
                const SizedBox(height: 12),
                _dlgField(emCtrl, 'Email', Icons.email_outlined),
                const SizedBox(height: 12),
                _dlgField(pwCtrl,  'Password', Icons.lock_outline,
                  obscure: obscurePw,
                  suffix: IconButton(
                    icon: Icon(obscurePw
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                      size: 18, color: kTextMuted),
                    onPressed: () => setDlg(() => obscurePw = !obscurePw),
                  ),
                ),
                const SizedBox(height: 12),
                _dlgField(cpwCtrl, 'Confirm Password', Icons.lock_reset, obscure: true),
                const SizedBox(height: 16),

                // Role selector
                Container(
                  decoration: BoxDecoration(
                    color: kBg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(children: [
                    _roleOption('Clinic Staff', Icons.badge_outlined, role, (v) => setDlg(() => role = v)),
                    Divider(height: 1, color: kBorder),
                    _roleOption('Clinic Head',  Icons.admin_panel_settings_outlined, role, (v) => setDlg(() => role = v)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (pwCtrl.text != cpwCtrl.text) {
                  setDlg(() => errMsg = 'Passwords do not match.');
                  return;
                }
                final err = UserStore.register(
                  firstName: fnCtrl.text,
                  lastName:  lnCtrl.text,
                  email:     emCtrl.text,
                  password:  pwCtrl.text,
                  role:      role,
                );
                if (err != null) {
                  setDlg(() => errMsg = err);
                  return;
                }
                Navigator.pop(ctx);
                _refresh();
                _toast('Account registered successfully.');
              },
              child: const Text('Register', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ── Delete confirmation ───────────────────────────────────────────────────
  void _confirmDelete(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account', style: TextStyle(color: kRed, fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(style: const TextStyle(color: kTextDark, fontSize: 14, height: 1.5), children: [
            const TextSpan(text: 'Are you sure you want to permanently delete '),
            TextSpan(text: user.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: "'s account? This cannot be undone."),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: kTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              UserStore.delete(user.id);
              Navigator.pop(ctx);
              _refresh();
              _toast('${user.fullName}\'s account has been deleted.');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Update Personal Info dialog (all users) ─────────────────────────────
  void _showUpdatePersonalInfoDialog() {
    final me = UserStore.findByEmail(_displayEmail);
    if (me == null) return;

    final fnCtrl  = TextEditingController(text: me.firstName);
    final lnCtrl  = TextEditingController(text: me.lastName);
    final emCtrl  = TextEditingController(text: me.email);
    String? errMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Update Personal Info',
            style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Avatar preview
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: kTealLight,
                    child: Text(
                      me.firstName.isNotEmpty ? me.firstName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kTeal),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (errMsg != null) ...[_errorBanner(errMsg!), const SizedBox(height: 12)],

                Row(children: [
                  Expanded(child: _dlgField(fnCtrl, 'First Name', Icons.person_outline)),
                  const SizedBox(width: 10),
                  Expanded(child: _dlgField(lnCtrl, 'Last Name',  Icons.person_outline)),
                ]),
                const SizedBox(height: 12),
                _dlgField(emCtrl, 'Email', Icons.email_outlined),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final newFirst = fnCtrl.text.trim();
                final newLast  = lnCtrl.text.trim();
                final newEmail = emCtrl.text.trim();

                if (newFirst.isEmpty || newLast.isEmpty) {
                  setDlg(() => errMsg = 'First and last name cannot be empty.');
                  return;
                }
                if (!newEmail.contains('@')) {
                  setDlg(() => errMsg = 'Please enter a valid email address.');
                  return;
                }
                // If email changed, make sure it's not taken by another account
                if (newEmail != me.email && UserStore.findByEmail(newEmail) != null) {
                  setDlg(() => errMsg = 'That email is already used by another account.');
                  return;
                }

                // Apply changes directly to the AppUser object
                me.firstName = newFirst;
                me.lastName  = newLast;
                me.email     = newEmail;

                // Update local display state so profile card refreshes immediately
                setState(() {
                  _displayName  = me.fullName;
                  _displayEmail = me.email;
                });

                Navigator.pop(ctx);
                _toast('Personal info updated successfully.');
              },
              child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // ── Change-password dialog ────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final curCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();
    String? errMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Change Password',
            style: TextStyle(color: kTextDark, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errMsg != null) _errorBanner(errMsg!),
                const SizedBox(height: 8),
                _dlgField(curCtrl,  'Current Password',     Icons.lock_open_outlined, obscure: true),
                const SizedBox(height: 12),
                _dlgField(newCtrl,  'New Password',         Icons.vpn_key_outlined,   obscure: true),
                const SizedBox(height: 12),
                _dlgField(confCtrl, 'Confirm New Password', Icons.lock_reset,          obscure: true),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                final me = UserStore.findByEmail(widget.userEmail);
                if (me == null || me.password != curCtrl.text) {
                  setDlg(() => errMsg = 'Current password is incorrect.');
                  return;
                }
                if (newCtrl.text.length < 6) {
                  setDlg(() => errMsg = 'New password must be at least 6 characters.');
                  return;
                }
                if (newCtrl.text != confCtrl.text) {
                  setDlg(() => errMsg = 'Passwords do not match.');
                  return;
                }
                me.password = newCtrl.text;
                Navigator.pop(ctx);
                _toast('Password changed successfully.');
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
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
        final isDesktop     = constraints.maxWidth > 900;
        final sidePadding   = isDesktop ? constraints.maxWidth * 0.03 : 10.0;

        return Column(children: [
          _header(isDesktop),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: sidePadding, vertical: 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── My profile card ──
                _sectionLabel('MY ACCOUNT'),
                const SizedBox(height: 12),
                _myProfileCard(),
                const SizedBox(height: 12),
                _settingsGroup([
                  _actionTile('Update Personal Info', 'Edit your name and email address',
                    Icons.badge_outlined, _showUpdatePersonalInfoDialog),
                  Divider(height: 1, color: kBorder, indent: 60),
                  _actionTile('Change Password', 'Update your current login credentials',
                    Icons.lock_outline_rounded, _showChangePasswordDialog),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _userListCard(),
                ],

                const SizedBox(height: 48),
                Center(child: Text('TCGC Clinic Management System • v2.1.0',
                  style: TextStyle(color: kTextMuted.withOpacity(0.6), fontSize: 11))),
              ]),
            ),
          ),
        ]);
      }),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(bool isDesktop) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(children: [
        const Icon(Icons.manage_accounts_outlined, color: kTeal),
        const SizedBox(width: 12),
        const Text('Account & User Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark)),
        const Spacer(),
        if (_isHead)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kTealLight, borderRadius: BorderRadius.circular(8)),
            child: const Text('Clinic Head',
              style: TextStyle(color: kTeal, fontSize: 12, fontWeight: FontWeight.bold)),
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
        CircleAvatar(
          radius: 30,
          backgroundColor: kTealLight,
          child: Text(
            _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kTeal),
          ),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.userName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark)),
          Text(widget.userRole,
            style: const TextStyle(color: kTeal, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(widget.userEmail,
            style: const TextStyle(color: kTextMuted, fontSize: 13)),
        ]),
      ]),
    );
  }

  // ── User list (Head only) ─────────────────────────────────────────────────
  Widget _userListCard() {
    final users = UserStore.all;

    if (users.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
        child: const Center(
          child: Text('No accounts yet. Register the first one!',
            style: TextStyle(color: kTextMuted))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
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
            const Expanded(flex: 3, child: Text('NAME',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: kTextMuted, letterSpacing: 1))),
            const Expanded(flex: 3, child: Text('EMAIL',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: kTextMuted, letterSpacing: 1))),
            const Expanded(flex: 2, child: Text('ROLE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: kTextMuted, letterSpacing: 1))),
            const SizedBox(width: 100,
              child: Text('STATUS',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: kTextMuted, letterSpacing: 1))),
            const SizedBox(width: 60,
              child: Text('',  // actions col
                textAlign: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, color: kBorder),

        // Rows
        ...users.asMap().entries.map((e) {
          final i    = e.key;
          final user = e.value;
          final isMe = user.email == widget.userEmail;
          return Column(children: [
            _userRow(user, isMe),
            if (i < users.length - 1)
              const Divider(height: 1, color: kBorder, indent: 20, endIndent: 20),
          ]);
        }),
      ]),
    );
  }

  Widget _userRow(AppUser user, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        // Name
        Expanded(flex: 3, child: Row(children: [
          CircleAvatar(
            radius: 16, backgroundColor: kTealLight,
            child: Text(user.firstName[0].toUpperCase(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kTeal)),
          ),
          const SizedBox(width: 10),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextDark),
              overflow: TextOverflow.ellipsis),
            if (isMe)
              const Text('(you)', style: TextStyle(fontSize: 11, color: kTeal)),
          ])),
        ])),

        // Email
        Expanded(flex: 3, child: Text(user.email,
          style: const TextStyle(fontSize: 13, color: kTextMuted),
          overflow: TextOverflow.ellipsis)),

        // Role chip
        Expanded(flex: 2, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: user.role == 'Clinic Head' ? const Color(0xFFEFF6FF) : kTealLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(user.role,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              color: user.role == 'Clinic Head' ? const Color(0xFF2563EB) : kTeal)),
        )),

        // Active toggle
        SizedBox(width: 100, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Switch.adaptive(
            value: user.isActive,
            activeColor: kTeal,
            onChanged: isMe ? null : (_) {  // can't deactivate yourself
              UserStore.toggleActive(user.id);
              _refresh();
              _toast(user.isActive
                ? '${user.fullName} has been deactivated.'
                : '${user.fullName} has been activated.');
            },
          ),
          const SizedBox(width: 4),
          Text(user.isActive ? 'Active' : 'Off',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: user.isActive ? kTeal : kTextMuted)),
        ])),

        // Delete
        SizedBox(width: 60, child: isMe
          ? const SizedBox()  // can't delete yourself
          : IconButton(
              tooltip: 'Delete account',
              icon: const Icon(Icons.delete_outline_rounded, color: kRed, size: 20),
              onPressed: () => _confirmDelete(user),
            )),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String t) => Text(t,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
        color: kTextMuted, letterSpacing: 1.2));

  Widget _settingsGroup(List<Widget> children) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorder)),
    child: Column(children: children),
  );

  Widget _actionTile(String title, String sub, IconData icon, VoidCallback onTap) =>
    ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: kTeal, size: 22)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700,
          fontSize: 15, color: kTextDark)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12, color: kTextMuted)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: kBorder),
    );

  Widget _dlgField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool   obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: kTeal, size: 20),
        hintText: hint,
        suffixIcon: suffix,
        filled: true, fillColor: kBg,
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

  Widget _roleOption(String role, IconData icon, String selected, ValueChanged<String> onTap) {
    final isSelected = selected == role;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: isSelected ? kTeal : kTextMuted, size: 20),
      title: Text(role, style: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? kTeal : kTextDark, fontSize: 14)),
      trailing: isSelected
        ? const Icon(Icons.check_circle, color: kTeal, size: 20)
        : const Icon(Icons.circle_outlined, color: kBorder, size: 20),
      onTap: () => onTap(role),
    );
  }

  Widget _errorBanner(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: kRedLight, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFECACA))),
    child: Row(children: [
      const Icon(Icons.error_outline, color: kRed, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(color: kRed, fontSize: 13))),
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
}