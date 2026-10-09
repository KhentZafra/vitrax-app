import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/avatar_service.dart';
import '../widgets/user_avatar.dart';

/// Everything about the signed-in user's own profile lives here, reached
/// from the settings icon on the Profile screen: profile photo (the only
/// place a photo can be uploaded or removed), name, primary activity,
/// email and password.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _firstController = TextEditingController();
  final _lastController = TextEditingController();

  String _email = '';
  String? _avatarUrl;
  String _primaryActivity = 'Cyclist';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _changed = false; // tells ProfileScreen to reload when we pop

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final p = await _supabase
          .from('profiles')
          .select('first_name, last_name, avatar_url, primary_activity')
          .eq('id', user.id)
          .maybeSingle();
      _firstController.text = (p?['first_name'] as String?) ?? '';
      _lastController.text = (p?['last_name'] as String?) ?? '';
      _avatarUrl = p?['avatar_url'] as String?;
      final activity = p?['primary_activity'] as String?;
      if (activity == 'Cyclist' || activity == 'Runner') _primaryActivity = activity!;
    } catch (_) {}
    _email = user.email ?? '';
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------- photo

  void _changeAvatar() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff1a1a1a),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Colors.white),
              title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndUploadAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndUploadAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final file = await AvatarService.pickAvatar(source: source);
    if (file == null || !mounted) return;

    setState(() => _isUploadingAvatar = true);
    final url = await AvatarService.uploadAvatar(file);
    if (!mounted) return;
    setState(() {
      _isUploadingAvatar = false;
      if (url != null) {
        _avatarUrl = url;
        _changed = true;
      }
    });
    _snack(url != null ? 'Profile photo updated.' : "Couldn't upload your photo. Try again.");
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploadingAvatar = true);
    final ok = await AvatarService.removeAvatar();
    if (!mounted) return;
    setState(() {
      _isUploadingAvatar = false;
      if (ok) {
        _avatarUrl = null;
        _changed = true;
      }
    });
    _snack(ok ? 'Profile photo removed.' : "Couldn't remove your photo. Try again.");
  }

  // ---------------------------------------------------------- name / info

  Future<void> _saveProfile() async {
    final first = _firstController.text.trim();
    final last = _lastController.text.trim();
    if (first.isEmpty || last.isEmpty) {
      _snack('First and last name are required.');
      return;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('profiles').update({
        'first_name': first,
        'last_name': last,
        'primary_activity': _primaryActivity,
      }).eq('id', user.id);
      // Keep auth metadata in step with the profiles row.
      await _supabase.auth.updateUser(UserAttributes(data: {
        'first_name': first,
        'last_name': last,
        'primary_activity': _primaryActivity,
      }));
      _changed = true;
      if (!mounted) return;
      _snack('Profile saved.');
    } catch (_) {
      _snack("Couldn't save your profile. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------- email

  Future<void> _changeEmail() async {
    final controller = TextEditingController();
    final newEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff141414),
        title: const Text('Change email', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: $_email', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'New email address'),
            ),
            const SizedBox(height: 10),
            const Text(
              "We'll send a confirmation link to the new address. Your email only changes after you open it.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Send link')),
        ],
      ),
    );
    controller.dispose();
    if (newEmail == null || newEmail.isEmpty) return;

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(newEmail)) {
      _snack('Please enter a valid email address.');
      return;
    }
    if (newEmail.toLowerCase() == _email.toLowerCase()) {
      _snack("That's already your email.");
      return;
    }

    try {
      await _supabase.auth.updateUser(UserAttributes(email: newEmail));
      _snack('Confirmation link sent to $newEmail. Open it to finish the change.');
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't change your email. Try again later.");
    }
  }

  // ------------------------------------------------------------- password

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff141414),
          title: const Text('Change password', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: current,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Current password'),
                ),
                TextField(
                  controller: next,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'New password (min. 6 characters)'),
                ),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (current.text.isEmpty) {
                  setDialogState(() => error = 'Enter your current password.');
                  return;
                }
                if (next.text.length < 6) {
                  setDialogState(() => error = 'New password must be at least 6 characters.');
                  return;
                }
                if (next.text != confirm.text) {
                  setDialogState(() => error = "New passwords don't match.");
                  return;
                }
                try {
                  // Re-verify who is asking before changing the password.
                  await _supabase.auth.signInWithPassword(email: _email, password: current.text);
                  await _supabase.auth.updateUser(UserAttributes(password: next.text));
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } on AuthException catch (e) {
                  final wrong = e.message.toLowerCase().contains('invalid');
                  setDialogState(() => error = wrong ? 'Current password is incorrect.' : e.message);
                } catch (_) {
                  setDialogState(() => error = "Couldn't change your password. Try again.");
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (ok == true) _snack('Password updated.');
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xff050505),
        appBar: AppBar(
          backgroundColor: const Color(0xff050505),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.blue))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Center(
                    child: Stack(
                      children: [
                        UserAvatar(
                          avatarUrl: _avatarUrl,
                          radius: 52,
                          backgroundColor: Colors.blue.withValues(alpha: .15),
                          iconColor: Colors.blue,
                        ),
                        if (_isUploadingAvatar)
                          Positioned.fill(
                            child: Container(
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                              child: const Center(
                                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _isUploadingAvatar ? null : _changeAvatar,
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(_avatarUrl == null ? 'Upload photo' : 'Change photo'),
                      ),
                      if (_avatarUrl != null)
                        TextButton.icon(
                          onPressed: _isUploadingAvatar ? null : _removeAvatar,
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          label: const Text('Remove', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('Personal info'),
                  TextField(
                    controller: _firstController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lastController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                  const SizedBox(height: 16),
                  const Text('I am a', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final option in const ['Cyclist', 'Runner'])
                        ChoiceChip(
                          label: Text(option),
                          selected: _primaryActivity == option,
                          onSelected: (_) => setState(() => _primaryActivity = option),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save changes'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel('Account'),
                  _AccountTile(icon: Icons.email_outlined, title: 'Email', subtitle: _email, onTap: _changeEmail),
                  _AccountTile(icon: Icons.lock_outline, title: 'Password', subtitle: 'Change your password', onTap: _changePassword),
                ],
              ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      );
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xff141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade600),
        onTap: onTap,
      ),
    );
  }
}
