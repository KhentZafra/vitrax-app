import '../widgets/account_dialogs.dart';
import '../widgets/email_code_dialog.dart';
import '../services/activity_preference.dart';
import 'package:flutter/material.dart';
import 'legal_screen.dart';
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
  int _privacyZone = 200;
  final _firstController = TextEditingController();
  final _lastController = TextEditingController();

  String _email = '';
  String? _avatarUrl;
  bool _cyclist = true;
  bool _runner = false;
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
          .select('first_name, last_name, avatar_url, primary_activity, privacy_zone_m')
          .eq('id', user.id)
          .maybeSingle();
      _firstController.text = (p?['first_name'] as String?) ?? '';
      _lastController.text = (p?['last_name'] as String?) ?? '';
      _avatarUrl = p?['avatar_url'] as String?;
      _privacyZone = (p?['privacy_zone_m'] as num?)?.toInt() ?? 200;
      final pref = ActivityPreference.parse(p?['primary_activity'] as String?);
      if (pref.hasAny) {
        _cyclist = pref.cyclist;
        _runner = pref.runner;
      }
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
    if (!_cyclist && !_runner) {
      _snack('Pick Cyclist, Runner, or both.');
      return;
    }
    final primaryActivity = ActivityPreference.encode(cyclist: _cyclist, runner: _runner);
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('profiles').update({
        'first_name': first,
        'last_name': last,
        'primary_activity': primaryActivity,
      }).eq('id', user.id);
      // Keep auth metadata in step with the profiles row.
      await _supabase.auth.updateUser(UserAttributes(data: {
        'first_name': first,
        'last_name': last,
        'primary_activity': primaryActivity,
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
    final newEmail = await showChangeEmailDialog(context, currentEmail: _email);
    if (newEmail == null || newEmail.isEmpty) return;

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(newEmail)) {
      _snack('Please enter a valid email address.');
      return;
    }
    if (newEmail.toLowerCase() == _email.toLowerCase()) {
      _snack("That's already your email.");
      return;
    }

    final wait = EmailCodeCooldown.remaining(newEmail);
    if (wait > 0) {
      _snack('Please wait ${wait}s before requesting another code.');
      return;
    }
    try {
      await _supabase.auth.updateUser(UserAttributes(email: newEmail));
      EmailCodeCooldown.mark(newEmail);
      if (!mounted) return;
      final ok = await showEmailCodeDialog(
        context,
        email: newEmail,
        type: OtpType.emailChange,
        title: 'Confirm new email',
        message: 'We sent a code to $newEmail. Enter it to finish changing your email.',
      );
      if (ok) {
        if (mounted) setState(() => _email = newEmail);
        _snack('Email changed to $newEmail.');
      } else {
        _snack('Email not changed. You can try again anytime.');
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't change your email. Try again later.");
    }
  }

  // ------------------------------------------------------------- password

  Future<void> _changePassword() async {
    final ok = await showChangePasswordDialog(context, email: _email);
    if (!mounted) return;
    if (ok) _snack('Password updated.');
  }

  // -------------------------------------------------------------- privacy

  Future<void> _choosePrivacy() async {
    const options = <int, String>{
      0: 'Off - share full routes',
      200: '200 m (recommended)',
      500: '500 m',
      1000: '1 km',
    };
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xff141414),
        title: const Text('Hide start & end of shared routes', style: TextStyle(color: Colors.white, fontSize: 17)),
        children: [
          for (final e in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, e.key),
              child: Row(
                children: [
                  Icon(e.key == _privacyZone ? Icons.radio_button_checked : Icons.radio_button_off, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Text(e.value, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == _privacyZone) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.from('profiles').update({'privacy_zone_m': picked}).eq('id', user.id);
      if (!mounted) return;
      setState(() => _privacyZone = picked);
      _snack('Route privacy updated.');
    } catch (_) {
      _snack("Couldn't update route privacy. Try again.");
    }
  }

  String get _privacyLabel => _privacyZone == 0 ? 'Off - full routes are shared' : 'Hiding first & last ${_privacyZone >= 1000 ? '1 km' : '$_privacyZone m'}';

  // ------------------------------------------------------- delete account

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    final typed = TextEditingController();
    String? error;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff141414),
          title: const Text('Delete my account', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your profile, activities, posts, comments, hazard reports and messages. It cannot be undone.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Your password'),
                ),
                TextField(
                  controller: typed,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
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
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (password.text.isEmpty) {
                        setDialogState(() => error = 'Enter your password.');
                        return;
                      }
                      if (typed.text.trim() != 'DELETE') {
                        setDialogState(() => error = 'Type DELETE exactly to confirm.');
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await _supabase.auth.signInWithPassword(email: _email, password: password.text);
                        await _supabase.rpc('delete_my_account');
                        if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                      } on AuthException catch (e) {
                        final wrong = e.message.toLowerCase().contains('invalid');
                        setDialogState(() {
                          busy = false;
                          error = wrong ? 'Password is incorrect.' : e.message;
                        });
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          error = "Couldn't delete your account. Check your connection and try again.";
                        });
                      }
                    },
              child: const Text('Delete forever', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    typed.dispose();
    if (ok != true || !mounted) return;
    try {
      await _supabase.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // ------------------------------------------------------------------ UI

  static const _blue = Color(0xff1E6BFF);

  InputDecoration _fieldDecoration(IconData icon) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
      filled: true,
      fillColor: const Color(0xff101015),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      enabledBorder: border(Colors.white12),
      border: border(Colors.white12),
      focusedBorder: border(_blue),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      );

  Widget _glow({required double size, required Alignment align, double alpha = .25}) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: align,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [_blue.withValues(alpha: alpha), Colors.transparent]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring({required double size, required Alignment align}) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: align,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _blue.withValues(alpha: .18))),
          ),
        ),
      ),
    );
  }

  Widget _avatarHeader() {
    return Column(
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff050505),
                  border: Border.all(color: _blue, width: 2.5),
                  boxShadow: [BoxShadow(color: _blue.withValues(alpha: .35), blurRadius: 24)],
                ),
                child: Stack(
                  children: [
                    UserAvatar(
                      avatarUrl: _avatarUrl,
                      radius: 48,
                      backgroundColor: _blue.withValues(alpha: .15),
                      iconColor: _blue,
                    ),
                    if (_isUploadingAvatar)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                          child: const Center(
                            child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 2,
                bottom: 4,
                child: GestureDetector(
                  onTap: _isUploadingAvatar ? null : _changeAvatar,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xff0A3D99),
                      shape: BoxShape.circle,
                      border: Border.all(color: _blue, width: 2),
                    ),
                    child: const Icon(Icons.photo_camera, color: Colors.white, size: 17),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PillButton(
              icon: Icons.photo_camera_outlined,
              label: _avatarUrl == null ? 'Upload photo' : 'Change photo',
              color: _blue,
              fill: const Color(0xff0B1B3A),
              onTap: _isUploadingAvatar ? null : _changeAvatar,
            ),
            if (_avatarUrl != null) ...[
              const SizedBox(width: 14),
              _PillButton(
                icon: Icons.delete_outline,
                label: 'Remove',
                color: const Color(0xffE5383B),
                fill: const Color(0xff2A0A0C),
                onTap: _isUploadingAvatar ? null : _removeAvatar,
              ),
            ],
          ],
        ),
      ],
    );
  }

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
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          centerTitle: false,
          titleSpacing: 8,
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            _glow(size: 320, align: const Alignment(-1.5, -0.95)),
            _ring(size: 260, align: const Alignment(-1.6, -0.75)),
            _glow(size: 380, align: const Alignment(1.7, -0.2), alpha: .22),
            _ring(size: 300, align: const Alignment(1.9, -0.45)),
            SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _blue))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
                      children: [
                        _avatarHeader(),
                        const SizedBox(height: 22),
                        _SectionCard(
                          icon: Icons.person,
                          title: 'Personal info',
                          subtitle: 'Update your personal details',
                          accent: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('First name'),
                              TextField(
                                controller: _firstController,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                decoration: _fieldDecoration(Icons.person),
                              ),
                              const SizedBox(height: 16),
                              _label('Last name'),
                              TextField(
                                controller: _lastController,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                decoration: _fieldDecoration(Icons.person),
                              ),
                              const SizedBox(height: 16),
                              _label('I am a (pick one or both)'),
                              Row(
                                children: [
                                  Expanded(
                                    child: _ActivityOption(
                                      icon: Icons.directions_bike,
                                      label: 'Cyclist',
                                      selected: _cyclist,
                                      onTap: () => setState(() => _cyclist = !_cyclist),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _ActivityOption(
                                      icon: Icons.directions_run,
                                      label: 'Runner',
                                      selected: _runner,
                                      onTap: () => setState(() => _runner = !_runner),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              _SaveButton(isSaving: _isSaving, onTap: _isSaving ? null : _saveProfile),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _SectionCard(
                          icon: Icons.settings,
                          title: 'Account',
                          subtitle: 'Manage your account details',
                          child: Column(
                            children: [
                              _AccountTile(icon: Icons.email_outlined, title: 'Email', subtitle: _email, onTap: _changeEmail),
                              const SizedBox(height: 12),
                              _AccountTile(icon: Icons.lock, title: 'Password', subtitle: 'Change your password', onTap: _changePassword),
                              const SizedBox(height: 12),
                              _AccountTile(icon: Icons.shield_outlined, title: 'Route privacy', subtitle: _privacyLabel, onTap: _choosePrivacy),
                              const SizedBox(height: 12),
                              _AccountTile(
                                icon: Icons.policy_outlined,
                                title: 'Privacy Policy & Terms',
                                subtitle: 'How your data is used',
                                onTap: () => LegalDialog.show(context),
                              ),
                              const SizedBox(height: 12),
                              _AccountTile(icon: Icons.delete_forever, title: 'Delete my account', subtitle: 'Permanently remove your data', onTap: _deleteAccount),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color fill;
  final VoidCallback? onTap;
  const _PillButton({required this.icon, required this.label, required this.color, required this.fill, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: .7))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final bool accent;
  const _SectionCard({required this.icon, required this.title, required this.subtitle, required this.child, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff0B0B0E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            if (accent)
              Positioned(
                left: 0,
                top: 0,
                child: Container(width: 4, height: 84, decoration: const BoxDecoration(color: Color(0xff1E6BFF), borderRadius: BorderRadius.only(bottomRight: Radius.circular(4)))),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _IconCircle(icon: icon, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final double size;
  const _IconCircle({required this.icon, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff0B1B3A)),
      child: Icon(icon, color: const Color(0xff1E6BFF), size: size * .45),
    );
  }
}

class _ActivityOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ActivityOption({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xff1E6BFF);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff0B1B3A) : const Color(0xff101015),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? blue : Colors.white12, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? blue : Colors.grey.shade500, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(color: selected ? blue : Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            if (selected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff00AEEF)),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback? onTap;
  const _SaveButton({required this.isSaving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        height: 48,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(colors: [Color(0xff0A4FD6), Color(0xff2272FF)]),
          boxShadow: [BoxShadow(color: const Color(0xff1E6BFF).withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSaving)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Text('Save changes', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            if (!isSaving)
              const Positioned(right: 18, child: Icon(Icons.arrow_forward, color: Colors.white, size: 20)),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xff101015),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            _IconCircle(icon: icon, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 22),
          ],
        ),
      ),
    );
  }
}
