import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/achievement.dart';
import '../services/activity_preference.dart';
import '../services/badge_service.dart';
import '../services/community_impact_service.dart';
import '../widgets/badge_medal.dart';
import '../widgets/skeleton_views.dart';
import '../widgets/user_actions_sheet.dart';
import '../widgets/user_avatar.dart';

/// Another member's public profile, opened from "View profile" in the
/// Community Feed menu. Read-only: photo, name, level, rank, stats,
/// achievements and Community Impact. Private details such as email are never
/// shown, and the numbers only count activities that person chose to share.
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;
  final String? fallbackAvatarUrl;

  const UserProfileScreen({super.key, required this.userId, required this.fallbackName, this.fallbackAvatarUrl});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  static const _bg = Color(0xff050505);
  static const _card = Color(0xff111418);
  static const _line = Color(0xff1d242d);
  static const _blue = Color(0xff2F7BFF);
  static const _gold = Color(0xffFFC83D);
  static const _green = Color(0xff22c55e);

  String _name = '';
  String? _avatarUrl;
  String? _primaryActivity;
  CommunityImpactStats? _stats;
  Map<String, dynamic>? _pub; // from public_profile_stats()
  final Map<String, BadgeTier> _tiers = {}; // badge key -> best tier
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _name = widget.fallbackName;
    _avatarUrl = widget.fallbackAvatarUrl;
    _load();
  }

  Future<void> _load() async {
    final sb = Supabase.instance.client;
    try {
      final p = await sb.from('profiles').select('first_name, last_name, avatar_url, primary_activity').eq('id', widget.userId).maybeSingle();
      if (p != null) {
        final full = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
        if (full.isNotEmpty) _name = full;
        _avatarUrl = p['avatar_url'] as String? ?? _avatarUrl;
        _primaryActivity = p['primary_activity'] as String?;
      }
    } catch (_) {}
    try {
      final res = await sb.rpc('public_profile_stats', params: {'p_user': widget.userId});
      if (res is Map) _pub = Map<String, dynamic>.from(res);
    } catch (_) {
      // Function not installed yet: the screen still works without the numbers.
    }
    try {
      final rows = await sb.from('user_badges').select('badge_key, tier').eq('user_id', widget.userId);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final tier = BadgeService.tierFromName(r['tier'] as String?);
        final key = r['badge_key'] as String;
        final old = _tiers[key];
        if (old == null || tier.index > old.index) _tiers[key] = tier;
      }
    } catch (_) {}
    _stats = await CommunityImpactService.fetchStats(widget.userId);
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  // ---- helpers ----
  num _n(String key) => (_pub?[key] as num?) ?? 0;

  /// Level comes from badge points (bronze 1 ... elite 6 per badge).
  int get _points => _n('badge_points').toInt();
  int get _level => 1 + _points ~/ 4;
  double get _levelProgress => (_points % 4) / 4;
  String get _levelTitle {
    if (_level >= 10) return 'Legend';
    if (_level >= 6) return 'Veteran';
    if (_level >= 3) return 'Regular';
    return 'Newcomer';
  }

  Color get _tierColor {
    switch (_stats?.tier) {
      case SafetyTier.trustedContributor:
        return const Color(0xff4FC3E8);
      case SafetyTier.safetyGuardian:
        return _gold;
      case SafetyTier.elite:
        return const Color(0xffE91E8C);
      default:
        return Colors.grey.shade500;
    }
  }

  void _openActions() => showUserActionsSheet(context, userId: widget.userId, userName: _name, avatarUrl: _avatarUrl, includeViewProfile: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: _openActions)],
      ),
      body: _isLoading
          ? const ProfileSkeleton()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
              children: [
                _hero(),
                const SizedBox(height: 16),
                if (_pub != null) ...[
                  _levelCard(),
                  const SizedBox(height: 14),
                  _statGrid(),
                  const SizedBox(height: 14),
                  if (_n('activities').toInt() > 0) ...[
                    _splitCard(),
                    const SizedBox(height: 14),
                  ],
                  _rankRow(),
                  const SizedBox(height: 14),
                ],
                _achievements(),
                const SizedBox(height: 14),
                _impact(),
                const SizedBox(height: 18),
                _actions(),
                const SizedBox(height: 14),
                Text('Numbers count only the activities this member chose to share.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5)),
              ],
            ),
    );
  }

  // ---------------- Hero ----------------
  Widget _hero() {
    final role = ActivityPreference.label(_primaryActivity);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff12203a), Color(0xff0a0f18)]),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_gold, Color(0xffff8a00)])),
                child: UserAvatar(avatarUrl: _avatarUrl, radius: 48, backgroundColor: const Color(0xff0c1624), iconColor: _blue),
              ),
              if (_pub != null)
                Positioned(
                  bottom: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(20), border: Border.all(color: _bg, width: 2)),
                    child: Text('LV $_level', style: const TextStyle(color: Color(0xff1a1200), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .5)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (role.isNotEmpty) _chip(Icons.directions_run_rounded, role, _blue),
              if (_stats != null) _chip(Icons.shield_rounded, _stats!.tier.label, _tierColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ---------------- Level ----------------
  Widget _levelCard() {
    final toNext = 4 - (_points % 4);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Level $_level', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(_levelTitle, style: const TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$_points pts', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: _levelProgress, minHeight: 9, backgroundColor: const Color(0xff1b222c), valueColor: const AlwaysStoppedAnimation(_gold)),
          ),
          const SizedBox(height: 8),
          Text('$toNext more badge point${toNext == 1 ? '' : 's'} to reach level ${_level + 1}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------- Stats ----------------
  Widget _statGrid() {
    final km = _n('total_km').toDouble();
    final hasShared = _n('activities').toInt() > 0;
    return Column(children: [
      if (hasShared)
        Row(children: [
          Expanded(child: _tile(Icons.route_rounded, km >= 100 ? km.toStringAsFixed(0) : km.toStringAsFixed(1), 'km shared', _blue)),
          const SizedBox(width: 12),
          Expanded(child: _tile(Icons.bolt_rounded, '${_n('activities').toInt()}', 'activities', _green)),
        ])
      else
        _noSharedCard(),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _tile(Icons.emoji_events_rounded, '${_n('challenges_completed').toInt()}', 'challenges finished', _gold)),
        const SizedBox(width: 12),
        Expanded(child: _tile(Icons.flag_rounded, '${_n('challenges_joined').toInt()}', 'challenges joined', const Color(0xffA77BFF))),
      ]),
    ]);
  }

  /// Shown instead of the 0 km / 0 activities tiles, so zeros are not read as
  /// "this person does nothing": they simply have not shared anything.
  Widget _noSharedCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, color: Colors.grey.shade500, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'No shared activities yet. This member keeps their activities private.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13.5, height: 1.35),
          ),
        ),
      ]),
    );
  }

  Widget _tile(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  // ---------------- Cycling / Running split ----------------
  Widget _splitCard() {
    final ride = _n('ride_km').toDouble(), run = _n('run_km').toDouble();
    final total = ride + run;
    Widget row(IconData icon, String label, double km, int count, Color color) {
      final frac = total > 0 ? km / total : 0.0;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${km.toStringAsFixed(1)} km  ·  $count', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: frac, minHeight: 7, backgroundColor: const Color(0xff1b222c), valueColor: AlwaysStoppedAnimation(color)),
          ),
        ]),
      );
    }

    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Cycling and running', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        row(Icons.pedal_bike_rounded, 'Cycling', ride, _n('ride_count').toInt(), _blue),
        row(Icons.directions_run_rounded, 'Running', run, _n('run_count').toInt(), _green),
      ]),
    );
  }

  // ---------------- Rank ----------------
  Widget _rankRow() {
    final kmRank = _pub?['km_rank'] as num?;
    return Row(children: [
      Expanded(child: _rankTile('Overall rank', '#${_n('points_rank').toInt()}', 'of ${_n('points_total').toInt()} members', const Color(0xffE91E8C))),
      const SizedBox(width: 12),
      Expanded(child: _rankTile('Distance rank', kmRank == null ? '—' : '#${kmRank.toInt()}', kmRank == null ? 'no shared rides yet' : 'of ${_n('km_total').toInt()} members', _blue)),
    ]);
  }

  Widget _rankTile(String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
        Text(sub, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
      ]),
    );
  }

  // ---------------- Achievements ----------------
  Widget _achievements() {
    final earned = BadgeService.defs.where((d) => (_tiers[d.key] ?? BadgeTier.none) != BadgeTier.none).toList();
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Achievements', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${earned.length}/${BadgeService.defs.length}', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        if (earned.isEmpty)
          Text('No badges earned yet.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
        else
          Wrap(
            spacing: 6,
            runSpacing: 10,
            children: [
              for (final d in earned)
                SizedBox(
                  width: 92,
                  child: Column(children: [
                    BadgeMedal(tier: _tiers[d.key]!, icon: d.icon, size: 72),
                    const SizedBox(height: 4),
                    Text(d.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    Text(_tiers[d.key]!.label, style: TextStyle(color: _tiers[d.key]!.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
          ),
      ]),
    );
  }

  // ---------------- Community impact ----------------
  Widget _impact() {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Community impact', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _tile(Icons.verified_rounded, '${s.hazardsVerified}', 'hazards verified', _green)),
          const SizedBox(width: 12),
          Expanded(child: _tile(Icons.cleaning_services_rounded, '${s.obstaclesCleared}', 'obstacles cleared', _blue)),
        ]),
      ]),
    );
  }

  // ---------------- Actions ----------------
  Widget _actions() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openActions,
        icon: const Icon(Icons.chat_bubble_rounded, size: 18),
        label: const Text('Message, block or report', style: TextStyle(fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)),
      child: child,
    );
  }
}
