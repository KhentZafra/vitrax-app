import '../services/activity_preference.dart';
import 'package:flutter/material.dart';
import '../widgets/skeleton_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/community_impact_service.dart';
import '../widgets/user_actions_sheet.dart';
import '../widgets/user_avatar.dart';

/// Another member's public profile, opened from "View profile" in the
/// Community Feed menu. Read-only: photo, name, what they are (Cyclist or
/// Runner) and their Community Impact. Private details such as email are
/// never shown.
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;
  final String? fallbackAvatarUrl;

  const UserProfileScreen({super.key, required this.userId, required this.fallbackName, this.fallbackAvatarUrl});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String _name = '';
  String? _avatarUrl;
  String? _primaryActivity;
  CommunityImpactStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _name = widget.fallbackName;
    _avatarUrl = widget.fallbackAvatarUrl;
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('first_name, last_name, avatar_url, primary_activity')
          .eq('id', widget.userId)
          .maybeSingle();
      if (p != null) {
        final full = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
        if (full.isNotEmpty) _name = full;
        _avatarUrl = p['avatar_url'] as String? ?? _avatarUrl;
        _primaryActivity = p['primary_activity'] as String?;
      }
    } catch (_) {}
    _stats = await CommunityImpactService.fetchStats(widget.userId);
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      backgroundColor: const Color(0xff050505),
      appBar: AppBar(
        backgroundColor: const Color(0xff050505),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showUserActionsSheet(
              context,
              userId: widget.userId,
              userName: _name,
              avatarUrl: _avatarUrl,
              includeViewProfile: false,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const ProfileSkeleton()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(
                  child: UserAvatar(
                    avatarUrl: _avatarUrl,
                    radius: 52,
                    backgroundColor: Colors.blue.withValues(alpha: .15),
                    iconColor: Colors.blue,
                  ),
                ),
                const SizedBox(height: 14),
                Center(child: Text(_name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                if (_primaryActivity != null) ...[
                  const SizedBox(height: 4),
                  Center(child: Text(ActivityPreference.label(_primaryActivity), style: const TextStyle(color: Colors.blue, fontSize: 14))),
                ],
                const SizedBox(height: 24),
                if (stats != null) ...[
                  const Text('Community Impact', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _StatRow(label: 'Total Hazards Verified', value: '${stats.hazardsVerified}'),
                  _StatRow(label: 'Route Obstacles Cleared', value: '${stats.obstaclesCleared}'),
                  _StatRow(label: 'Community Safety Score', value: stats.tier.label),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showUserActionsSheet(
                      context,
                      userId: widget.userId,
                      userName: _name,
                      avatarUrl: _avatarUrl,
                      includeViewProfile: false,
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message, block or report'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xff141414), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
