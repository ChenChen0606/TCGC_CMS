import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key, this.initial = ''});

  final String initial;

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Enter your username or email.');
      return;
    }
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      String? email;
      if (input.contains('@')) {
        email = input.toLowerCase();
      } else {
        email = await AccountService.resolveAuthEmailForIdentifier(input);

        if (email != null && email.endsWith('@clinic.local')) email = null;
      }

      if (email == null || email.isEmpty) {
        if (!mounted) return;
        setState(() => _error =
            'We could not find an email for that username. Try typing your '
                'email address instead.');
        return;
      }

      await supabaseClient.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );

      if (!mounted) return;
      setState(() {
        _sent = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() => _error = m.contains('rate') || m.contains('seconds')
          ? 'Too many requests. Please wait a minute and try again.'
          : 'Could not send the reset email: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not send the reset email: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_sent ? 'Check your email' : 'Forgot password'),
      content: SizedBox(
        width: 380,
        child: _sent
            ? const Text(
                'A password reset link was sent\n\n'
                'Open the email and click the link to choose a new password. '
                'Can\'t find it? Check your spam folder.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your username or email. We will send a link to '
                    'reset your password.',
                    style: TextStyle(fontSize: 13.5, color: AppColors.textSub),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Username or email',
                      prefixIcon: const Icon(Icons.mail_outline, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12.5)),
                  ],
                ],
              ),
      ),
      actions: _sent
          ? [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ]
          : [
              TextButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _sending ? null : _send,
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Send reset link'),
              ),
            ],
    );
  }
}
