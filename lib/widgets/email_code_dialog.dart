import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remembers when a code was last emailed to an address, so every screen
/// enforces the same wait before another code can be requested.
class EmailCodeCooldown {
  static const int seconds = 30;
  static final Map<String, DateTime> _last = {};

  static int remaining(String email) {
    final t = _last[email.trim().toLowerCase()];
    if (t == null) return 0;
    final left = seconds - DateTime.now().difference(t).inSeconds;
    return left > 0 ? left : 0;
  }

  static void mark(String email) => _last[email.trim().toLowerCase()] = DateTime.now();
}

/// Asks for the 6-digit code that Supabase emails (no link, no website or
/// deep link needed) and verifies it. Returns true once the code is accepted.
///
/// [type] is the kind of email that was sent:
///  * OtpType.signup      -> confirm a new account
///  * OtpType.recovery    -> forgot password
///  * OtpType.emailChange -> confirm a new email address
Future<bool> showEmailCodeDialog(
  BuildContext context, {
  required String email,
  required OtpType type,
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmailCodeDialog(email: email, type: type, title: title, message: message),
  );
  return result == true;
}

class _EmailCodeDialog extends StatefulWidget {
  final String email;
  final OtpType type;
  final String title;
  final String message;
  const _EmailCodeDialog({required this.email, required this.type, required this.title, required this.message});

  @override
  State<_EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<_EmailCodeDialog> {
  final _supabase = Supabase.instance.client;
  final _code = TextEditingController();
  String? _error;
  String? _info;
  bool _busy = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A code was just emailed. If the caller didn't record it, record it now.
    if (EmailCodeCooldown.remaining(widget.email) == 0) EmailCodeCooldown.mark(widget.email);
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = EmailCodeCooldown.remaining(widget.email));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the full code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await _supabase.auth.verifyOTP(type: widget.type, email: widget.email, token: code);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() => _error = (m.contains('expired') || m.contains('invalid')) ? 'That code is wrong or has expired. Check it or tap Resend.' : e.message);
    } catch (_) {
      setState(() => _error = "Couldn't verify. Check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.type == OtpType.recovery) {
        await _supabase.auth.resetPasswordForEmail(widget.email);
      } else {
        await _supabase.auth.resend(type: widget.type == OtpType.emailChange ? OtpType.emailChange : OtpType.signup, email: widget.email);
      }
      EmailCodeCooldown.mark(widget.email);
      _startCooldown();
      setState(() => _info = 'A new code was sent.');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't resend. Try again shortly.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff111111),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(widget.message, style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.4)),
            const SizedBox(height: 18),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Enter code',
                hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 16, letterSpacing: 1),
                filled: true,
                fillColor: const Color(0xff070b14),
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _verify(),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.3))),
            if (_info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_info!, style: const TextStyle(color: Colors.greenAccent, fontSize: 13))),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _busy ? null : _verify,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff0a77ff), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Verify', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: (_cooldown > 0 || _busy) ? null : _resend,
                  child: Text(_cooldown > 0 ? 'Resend (${_cooldown}s)' : 'Resend'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
