// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // Professional Palette
  final Color primaryTeal = const Color(0xFF008080);
  final Color lightTealBg = const Color(0xFFE6F2F2);
  final Color bgSlate = const Color(0xFFF8FAFC);
  final Color borderLight = const Color(0xFFE2E8F0);
  final Color textDark = const Color(0xFF1E293B);
  final Color textMuted = const Color(0xFF64748B);

  // --- DIALOGS ---

  // 1. REGISTER ACCOUNT (Clinic Head)
  void _showRegisterAccountDialog() {
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final confirmPassword = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => _buildScrollableDialog(
        title: "Register Clinic Head",
        children: [
          _buildDialogTextField(firstName, "First Name", Icons.person_outline),
          const SizedBox(height: 12),
          _buildDialogTextField(lastName, "Last Name", Icons.person_outline),
          const SizedBox(height: 12),
          _buildDialogTextField(email, "Email", Icons.email_outlined),
          const SizedBox(height: 12),
          _buildDialogTextField(password, "Password", Icons.lock_outline, obscure: true),
          const SizedBox(height: 12),
          _buildDialogTextField(confirmPassword, "Confirm Password", Icons.lock_reset, obscure: true),
        ],
        onConfirm: () => print("Registered: ${firstName.text}"),
      ),
    );
  }

  // 2. CHANGE PASSWORD
  void _showChangePasswordDialog() {
    final currentPass = TextEditingController();
    final newPass = TextEditingController();
    final confirmNewPass = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => _buildScrollableDialog(
        title: "Change Password",
        children: [
          _buildDialogTextField(currentPass, "Current Password", Icons.lock_open, obscure: true),
          const SizedBox(height: 12),
          _buildDialogTextField(newPass, "New Password", Icons.vpn_key_outlined, obscure: true),
          const SizedBox(height: 12),
          _buildDialogTextField(confirmNewPass, "Confirm New Password", Icons.lock_reset, obscure: true),
        ],
        onConfirm: () => print("Password Changed"),
      ),
    );
  }

  // 3. UPDATE USER INFO
  void _showUpdateUserInfoDialog() {
    final firstName = TextEditingController(text: "Cresa"); // Pre-filled example
    final lastName = TextEditingController(text: "Delacruz");
    final email = TextEditingController(text: "cresa.admin@tcgc.edu.ph");
    final password = TextEditingController();
    final confirmPassword = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => _buildScrollableDialog(
        title: "Update User Info",
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(radius: 40, backgroundColor: lightTealBg, child: Icon(Icons.person, size: 40, color: primaryTeal)),
                Positioned(bottom: 0, right: 0, child: CircleAvatar(radius: 15, backgroundColor: primaryTeal, child: Icon(Icons.camera_alt, size: 15, color: Colors.white))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildDialogTextField(firstName, "First Name", Icons.person_outline),
          const SizedBox(height: 12),
          _buildDialogTextField(lastName, "Last Name", Icons.person_outline),
          const SizedBox(height: 12),
          _buildDialogTextField(email, "Email", Icons.email_outlined),
          const SizedBox(height: 12),
          _buildDialogTextField(password, "New Password (Leave blank to keep current)", Icons.lock_outline, obscure: true),
          const SizedBox(height: 12),
          _buildDialogTextField(confirmPassword, "Confirm Password", Icons.lock_reset, obscure: true),
        ],
        onConfirm: () => print("Info Updated"),
      ),
    );
  }

  // --- REUSABLE COMPONENTS ---

  Widget _buildScrollableDialog({required String title, required List<Widget> children, required VoidCallback onConfirm}) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: textMuted))),
        ElevatedButton(
          onPressed: () {
            onConfirm();
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Text("Save Changes", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildDialogTextField(TextEditingController controller, String hint, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: primaryTeal, size: 20),
        hintText: hint,
        filled: true,
        fillColor: bgSlate,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderLight)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderLight)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgSlate,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth > 900;
          final double sidePadding = isDesktop ? constraints.maxWidth * 0.20 : 20.0;

          return Column(
            children: [
              _buildHeader(isDesktop),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: sidePadding, vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle("ADMINISTRATOR"),
                      const SizedBox(height: 12),
                      _buildAdminCard(),
                      const SizedBox(height: 32),
                      
                      _buildSectionTitle("USER MANAGEMENT"),
                      const SizedBox(height: 12),
                      _buildSettingsGroup([
                        _settingsActionTile("Update Personal Info", "Edit names, email, and profile photo", Icons.badge_outlined, _showUpdateUserInfoDialog),
                        Divider(height: 1, color: borderLight, indent: 60),
                        _settingsActionTile("Register Account", "Create a new Clinic Head or Staff member", Icons.person_add_alt_1_outlined, _showRegisterAccountDialog),
                      ]),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle("SECURITY"),
                      const SizedBox(height: 12),
                      _buildSettingsGroup([
                        _settingsActionTile("Change Password", "Update your current login credentials", Icons.lock_outline_rounded, _showChangePasswordDialog),
                        Divider(height: 1, color: borderLight, indent: 60),
                        _settingsActionTile("Two-Factor Authentication", "Add an extra layer of security", Icons.verified_user_outlined, () {}),
                      ]),
                      
                      const SizedBox(height: 48),
                      Center(child: Text("TCGC Clinic Management System • v2.1.0", style: TextStyle(color: textMuted, fontSize: 11))),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- HEADER & CARDS ---

  Widget _buildHeader(bool isDesktop) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: borderLight))),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: primaryTeal),
          const SizedBox(width: 12),
          Text("Account Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
        ],
      ),
    );
  }

  Widget _buildAdminCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderLight)),
      child: Row(
        children: [
          CircleAvatar(radius: 35, backgroundColor: lightTealBg, child: Icon(Icons.admin_panel_settings, color: primaryTeal, size: 35)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Cresa Delacruz", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                Text("Super Administrator", style: TextStyle(color: primaryTeal, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text("cresa.admin@tcgc.edu.ph", style: TextStyle(color: textMuted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 1.2));
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderLight)),
      child: Column(children: children),
    );
  }

  Widget _settingsActionTile(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bgSlate, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: primaryTeal, size: 22),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textDark)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: textMuted)),
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: borderLight),
    );
  }
}