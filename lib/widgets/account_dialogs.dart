import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg = Color(0xff111111);
const _field = Color(0xff070b14);
const _blue = Color(0xff0a77ff);

InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _field,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _blue, width: 1.5)),
    );

class _DialogShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? error;
  final bool busy;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onCancel;

  const _DialogShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.error,
    required this.busy,
    required this.actionLabel,
    required this.onAction,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: _blue, size: 28),
              ),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 20),
            ...children,
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.3))),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: busy ? null : onAction,
                style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(actionLabel, style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: busy ? null : onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- email

/// Asks for the new email address. Returns it (validated) or null if cancelled.
Future<String?> showChangeEmailDialog(BuildContext context, {required String currentEmail}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ChangeEmailDialog(currentEmail: currentEmail),
  );
}

class _ChangeEmailDialog extends StatefulWidget {
  final String currentEmail;
  const _ChangeEmailDialog({required this.currentEmail});

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _controller.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (email.toLowerCase() == widget.currentEmail.toLowerCase()) {
      setState(() => _error = "That's already your email.");
      return;
    }
    Navigator.pop(context, email);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.mark_email_unread_outlined,
      title: 'Change email',
      subtitle: "We'll send a code to the new address. Your email only changes after you enter it.",
      error: _error,
      busy: false,
      actionLabel: 'Send code',
      onAction: _submit,
      onCancel: () => Navigator.pop(context),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: _field, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const Icon(Icons.alternate_email, color: Colors.grey, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current email', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(widget.currentEmail, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('New email address', Icons.mail_outline),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- password

/// Changes the signed-in user's password after re-checking the current one.
/// Returns true when the password was updated.
Future<bool> showChangePasswordDialog(BuildContext context, {required String email}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ChangePasswordDialog(email: email),
  );
  return ok == true;
}

class _ChangePasswordDialog extends StatefulWidget {
  final String email;
  const _ChangePasswordDialog({required this.email});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _supabase = Supabase.instance.client;
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false;
  bool _showNext = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _eye(bool shown, VoidCallback toggle) => IconButton(
        icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey, size: 20),
        onPressed: toggle,
      );

  Future<void> _submit() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_next.text.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (_next.text == _current.text) {
      setState(() => _error = 'New password must be different from the current one.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = "New passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Re-verify who is asking before changing the password.
      await _supabase.auth.signInWithPassword(email: widget.email, password: _current.text);
      await _supabase.auth.updateUser(UserAttributes(password: _next.text));
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      final wrong = e.message.toLowerCase().contains('invalid');
      if (mounted) setState(() => _error = wrong ? 'Current password is incorrect.' : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't change your password. Check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.lock_reset_outlined,
      title: 'Change password',
      subtitle: 'Enter your current password, then choose a new one.',
      error: _error,
      busy: _busy,
      actionLabel: 'Update password',
      onAction: _submit,
      onCancel: () => Navigator.pop(context, false),
      children: [
        TextField(
          controller: _current,
          obscureText: !_showCurrent,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('Current password', Icons.lock_outline, suffix: _eye(_showCurrent, () => setState(() => _showCurrent = !_showCurrent))),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _next,
          obscureText: !_showNext,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('New password (min. 6 characters)', Icons.key_outlined, suffix: _eye(_showNext, () => setState(() => _showNext = !_showNext))),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: !_showNext,
          style: const TextStyle(color: Colors.white),
          decoration: _dec('Confirm new password', Icons.key_outlined),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}
