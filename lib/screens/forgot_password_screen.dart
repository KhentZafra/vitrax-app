import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/auth_decor.dart';
import '../widgets/email_code_dialog.dart';

/// Forgot password, done with an emailed 6-digit code (no link):
/// 1) enter your email, 2) enter the code, 3) choose a new password.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _supabase = Supabase.instance.client;
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeVerified = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xff8e9099), fontSize: 16),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xff070b14),
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      enabledBorder: border(const Color(0xff1c5fe0)),
      focusedBorder: border(const Color(0xff0a77ff), 1.6),
    );
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final wait = EmailCodeCooldown.remaining(email);
    if (wait > 0) {
      setState(() => _error = 'Please wait ${wait}s before requesting another code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      EmailCodeCooldown.mark(email);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message.toLowerCase().contains('rate') ? 'Too many requests. Please wait a minute and try again.' : e.message;
          _busy = false;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = "Couldn't send the code. Check your internet.";
          _busy = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = await showEmailCodeDialog(
      context,
      email: email,
      type: OtpType.recovery,
      title: 'Enter the code',
      message: 'If an account exists for $email, we sent a code to it. It expires in an hour.',
    );
    if (ok && mounted) setState(() => _codeVerified = true);
  }

  Future<void> _savePassword() async {
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = "Passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _supabase.auth.updateUser(UserAttributes(password: _password.text));
      await _supabase.auth.signOut(); // make them sign in with the new password
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated. Please sign in.')));
      Navigator.pop(context);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't update your password. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff020304),
      body: AuthImageDecor(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white), padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                const SizedBox(height: 24),
                Text(_codeVerified ? 'NEW PASSWORD' : 'FORGOT PASSWORD', style: techText(24, letterSpacing: 3)),
                const SizedBox(height: 12),
                Text(
                  _codeVerified ? 'Choose a new password for your account.' : "Enter your account email. We'll send you a code to reset your password.",
                  style: authBodyStyle,
                ),
                const SizedBox(height: 28),
                if (!_codeVerified)
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: _decoration('Email address', Icons.mail_outline),
                  )
                else ...[
                  TextField(
                    controller: _password,
                    obscureText: _hide,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: _decoration('New password', Icons.lock_outline, suffix: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.white70), onPressed: () => setState(() => _hide = !_hide))),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirm,
                    obscureText: _hide,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: _decoration('Confirm new password', Icons.lock_outline),
                  ),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                const SizedBox(height: 24),
                GlowButton(
                  label: _codeVerified ? 'SAVE PASSWORD' : 'SEND CODE',
                  spaced: true,
                  loading: _busy,
                  height: 58,
                  onPressed: _busy ? null : (_codeVerified ? _savePassword : _sendCode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
