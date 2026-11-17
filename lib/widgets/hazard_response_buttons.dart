import 'package:flutter/material.dart';

/// "Still here?" / "Clear now" answer for one hazard. A person answers each
/// hazard once: after either choice both buttons lock, the chosen one is
/// highlighted and the other is dimmed.
class HazardResponseButtons extends StatelessWidget {
  final bool verifiedByMe;
  final bool clearedByMe;
  final bool busy;
  final int clearCount;
  final VoidCallback onStillHere;
  final VoidCallback onClear;

  const HazardResponseButtons({
    super.key,
    required this.verifiedByMe,
    required this.clearedByMe,
    required this.busy,
    required this.clearCount,
    required this.onStillHere,
    required this.onClear,
  });

  bool get _answered => verifiedByMe || clearedByMe;

  Widget _button({
    required bool chosen,
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final locked = _answered;
    final dim = locked && !chosen;
    final fg = chosen ? color : (dim ? Colors.white24 : Colors.white70);
    return Expanded(
      child: GestureDetector(
        onTap: (locked || busy) ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: chosen ? color.withValues(alpha: .18) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: chosen ? color : (dim ? Colors.white10 : Colors.white24), width: chosen ? 1.6 : 1),
          ),
          child: busy && !locked
              ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(chosen ? Icons.check_circle_rounded : icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12, fontWeight: chosen ? FontWeight.w800 : FontWeight.w600))),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _button(
          chosen: verifiedByMe,
          color: Colors.blue,
          icon: Icons.push_pin_outlined,
          label: verifiedByMe ? 'You said: still here' : 'Still Here?',
          onTap: onStillHere,
        ),
        const SizedBox(width: 10),
        _button(
          chosen: clearedByMe,
          color: Colors.green,
          icon: Icons.cleaning_services_outlined,
          label: clearedByMe ? 'You said: cleared ($clearCount/3)' : 'Clear Now ($clearCount/3)',
          onTap: onClear,
        ),
      ],
    );
  }
}
