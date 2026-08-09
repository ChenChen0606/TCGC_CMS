import 'package:flutter/material.dart';
import 'clinic_dashboard_screen.dart';
import 'userstore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool    _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _login() {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    final user = UserStore.login(email, password);

    if (user == null) {
      // Distinguish between wrong creds and blocked account
      final exists = UserStore.findByEmail(email);
      setState(() => _error = (exists != null && !exists.isActive)
          ? 'Your account has been deactivated. Please contact the Clinic Head.'
          : 'Incorrect email or password.'); 
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicDashboard(
          userRole:  user.role,
          userEmail: user.email,
          userName:  user.fullName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(children: [
                      const Spacer(),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _logo('asset/tcgc.png',       Icons.school_rounded),
                        const SizedBox(width: 20),
                        Container(width: 2, height: 40, color: const Color(0xFFCBD5E1)),
                        const SizedBox(width: 20),
                        _logo('asset/cliniclogo.png', Icons.health_and_safety_rounded),
                      ]),
                      const SizedBox(height: 40),
                      _card(),
                      const Spacer(),
                      const Text('© 2026 Tangub City Global College • School Clinic System',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 40, offset: Offset(0, 20))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Welcome',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
              color: Color(0xFF1E293B), letterSpacing: -1)),
        const Text('Sign in to your account',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
        const SizedBox(height: 35),

        _label('Email'),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _inputDeco(icon: Icons.email_outlined, hint: 'you@tcgcclinic.com'),
        ),
        const SizedBox(height: 20),

        _label('Password'),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          decoration: _inputDeco(
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF94A3B8)),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
            ]),
          ),
        ],

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity, height: 55,
          child: ElevatedButton(
            onPressed: _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF008080),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text('Sign In',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _logo(String path, IconData fallback) {
    return Container(
      height: 65, width: 65,
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(path, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                Icon(fallback, color: const Color(0xFF008080), size: 30)),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(text, style: const TextStyle(fontSize: 13,
        fontWeight: FontWeight.w600, color: Color(0xFF475569))),
  );

  InputDecoration _inputDeco({required IconData icon, String? hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF008080), size: 20),
      suffixIcon: suffix,
      filled: true, fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF008080), width: 2)),
    );
  }
}