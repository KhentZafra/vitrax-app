import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/legal_text.dart';

/// Privacy Policy and Terms of Use, readable inside the app.
/// [initialTab]: 0 = Privacy Policy, 1 = Terms of Use.
class LegalScreen extends StatelessWidget {
  final int initialTab;
  const LegalScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Privacy & Terms', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            indicatorColor: Color(0xff3D7DFF),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            tabs: [Tab(text: 'Privacy Policy'), Tab(text: 'Terms of Use')],
          ),
        ),
        body: const TabBarView(
          children: [
            _SectionList(sections: kPrivacyPolicy),
            _SectionList(sections: kTermsOfUse),
          ],
        ),
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  final List<LegalSection> sections;
  const _SectionList({required this.sections});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Version $kPolicyVersion', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 8),
        for (var i = 0; i < sections.length; i++) ...[
          const SizedBox(height: 16),
          Text('${i + 1}. ${sections[i].heading}', style: const TextStyle(color: Color(0xff6AA2FF), fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final p in sections[i].paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(p, style: TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.5)),
            ),
        ],
      ],
    );
  }
}

/// Existing accounts made before the policy existed (or when it changes)
/// must accept it once. Returns true if the user may continue.
class ConsentGate {
  static final _supabase = Supabase.instance.client;

  /// True when this user has already accepted the current version, or when
  /// we can't tell (column missing / offline) so nobody is locked out.
  static Future<bool> hasAccepted() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return true;
    try {
      final row = await _supabase.from('profiles').select('consent_version').eq('id', user.id).maybeSingle();
      if (row == null) return true;
      return row['consent_version'] == kPolicyVersion;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> record() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('profiles').update({
        'consent_version': kPolicyVersion,
        'consent_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Prompt shown to existing accounts. Returns true if accepted.
  static Future<bool> prompt(BuildContext context) async {
    final accepted = await LegalDialog.show(
      context,
      requireDecision: true,
      dismissible: false,
      intro: 'We have added a Privacy Policy and Terms of Use. To keep using VITRAX, please read and accept them.',
      declineLabel: 'Decline',
    );
    if (accepted != true) return false;
    return record();
  }
}

// ---------------------------------------------------------------------------
// Terms & Privacy card dialog (black / white / blue theme).
// ---------------------------------------------------------------------------

const Color _kBlue = Color(0xff3D7DFF);
const Color _kBlueSoft = Color(0xff6AA2FF);
const Color _kCard = Color(0xff111111);

class LegalDialog {
  /// Shows the card. Returns true if Accept was tapped, false if Decline,
  /// null if it was closed with the X / barrier.
  ///
  /// [requireDecision] false = read-only: a single Close button.
  static Future<bool?> show(
    BuildContext context, {
    int initialTab = 0,
    bool requireDecision = false,
    bool dismissible = true,
    String? intro,
    String acceptLabel = 'Accept',
    String declineLabel = 'Decline',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: Colors.black.withValues(alpha: .78),
      builder: (_) => PopScope(
        canPop: dismissible,
        child: _LegalCard(
          initialTab: initialTab,
          requireDecision: requireDecision,
          showClose: dismissible,
          intro: intro,
          acceptLabel: acceptLabel,
          declineLabel: declineLabel,
        ),
      ),
    );
  }
}

class _LegalCard extends StatefulWidget {
  final int initialTab;
  final bool requireDecision;
  final bool showClose;
  final String? intro;
  final String acceptLabel;
  final String declineLabel;
  const _LegalCard({
    required this.initialTab,
    required this.requireDecision,
    required this.showClose,
    required this.intro,
    required this.acceptLabel,
    required this.declineLabel,
  });

  @override
  State<_LegalCard> createState() => _LegalCardState();
}

class _LegalCardState extends State<_LegalCard> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final sections = _tab == 0 ? kPrivacyPolicy : kTermsOfUse;
    final screenH = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: screenH * .82),
        child: Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
            boxShadow: [BoxShadow(color: _kBlue.withValues(alpha: .18), blurRadius: 32, spreadRadius: 1)],
          ),
          child: Column(
            children: [
              // ---- Header ----
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 10, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Privacy & Terms',
                        style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: .3),
                      ),
                    ),
                    if (widget.showClose)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                        tooltip: 'Close',
                      )
                    else
                      const SizedBox(height: 48),
                  ],
                ),
              ),

              // ---- Tabs ----
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                child: Row(
                  children: [
                    _TabPill(label: 'Privacy Policy', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                    const SizedBox(width: 8),
                    _TabPill(label: 'Terms of Use', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
                  ],
                ),
              ),

              // ---- Scrollable text ----
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    scrollbarTheme: ScrollbarThemeData(
                      thumbColor: WidgetStatePropertyAll(_kBlue.withValues(alpha: .85)),
                      thickness: const WidgetStatePropertyAll(4),
                      radius: const Radius.circular(4),
                    ),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      key: ValueKey(_tab),
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                      children: [
                        Text(
                          _tab == 0 ? 'Privacy Policy' : 'Terms of Use',
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: .4),
                        ),
                        const SizedBox(height: 2),
                        Text('Version $kPolicyVersion', style: const TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: .3)),
                        if (widget.intro != null) ...[
                          const SizedBox(height: 14),
                          Text(widget.intro!, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.55)),
                        ],
                        for (var i = 0; i < sections.length; i++) ...[
                          const SizedBox(height: 20),
                          Text(
                            '${i + 1}. ${sections[i].heading.toUpperCase()}',
                            style: const TextStyle(color: _kBlueSoft, fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: .6),
                          ),
                          const SizedBox(height: 6),
                          for (final para in sections[i].paragraphs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(para, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.6, letterSpacing: .2)),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ---- Footer ----
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                decoration: const BoxDecoration(
                  color: Color(0xff0B0B0B),
                  border: Border(top: BorderSide(color: Colors.white12)),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: widget.requireDecision
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _AcceptButton(label: widget.acceptLabel, onPressed: () => Navigator.pop(context, true)),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kBlueSoft,
                              side: const BorderSide(color: _kBlue),
                              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: Text(widget.declineLabel, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: .4)),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.centerRight,
                        child: _AcceptButton(label: 'Close', onPressed: () => Navigator.pop(context)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _kBlue.withValues(alpha: .18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kBlue : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kBlueSoft : Colors.white54,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _AcceptButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: _kBlue.withValues(alpha: .45), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: .4)),
      ),
    );
  }
}
