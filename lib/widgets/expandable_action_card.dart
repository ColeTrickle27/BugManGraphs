import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The native counterpart of the expandable cards in the Holloman web tools.
class ExpandableActionCard extends StatefulWidget {
  const ExpandableActionCard({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon = Icons.notes_outlined,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  State<ExpandableActionCard> createState() => _ExpandableActionCardState();
}

class _ExpandableActionCardState extends State<ExpandableActionCard> {
  final _controller = ExpansibleController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final duration =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 220);
    const radius = BorderRadius.all(Radius.circular(16));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        controller: _controller,
        maintainState: true,
        minTileHeight: 60,
        clipBehavior: Clip.antiAlias,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor: Colors.white,
        collapsedBackgroundColor: Colors.white,
        textColor: AppColors.foreground,
        collapsedTextColor: AppColors.foreground,
        shape: const RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Color(0x52C20000)),
        ),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Color(0xFFE5DDDD)),
        ),
        expansionAnimationStyle: AnimationStyle(duration: duration),
        leading: ExcludeSemantics(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 19, color: AppColors.red),
          ),
        ),
        title: Text(
          widget.title,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: widget.subtitle == null
            ? null
            : Text(
                widget.subtitle!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6A5F63)),
              ),
        trailing: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => ExcludeSemantics(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _controller.isExpanded
                      ? const Color(0x52C20000)
                      : const Color(0xFFEADFE0),
                ),
              ),
              child: AnimatedSwitcher(
                duration: duration,
                child: Icon(
                  _controller.isExpanded ? Icons.remove : Icons.add,
                  key: ValueKey(_controller.isExpanded),
                  size: 17,
                  color: AppColors.red,
                ),
              ),
            ),
          ),
        ),
        children: widget.children,
      ),
    );
  }
}
