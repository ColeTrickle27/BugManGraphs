import 'package:flutter/material.dart';

/// Approved homepage assets decorate app pages, never the drawing/export scene.
class GraphPageBackdrop extends StatelessWidget {
  const GraphPageBackdrop({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: const BoxDecoration(
          color: Color(0xFFF1F0F2),
          image: DecorationImage(
              image: AssetImage('assets/branding/modern/hex-silver.webp'),
              fit: BoxFit.cover,
              opacity: .25)),
      child: child);
}

class GraphPageHero extends StatelessWidget {
  const GraphPageHero(
      {required this.title,
      required this.subtitle,
      this.compact = false,
      super.key});
  final String title, subtitle;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xFF291D23),
            border: Border.all(color: const Color(0xFF9F172A)),
            image: const DecorationImage(
                image:
                    AssetImage('assets/branding/modern/bugman-hero-face.webp'),
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                opacity: .3)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontFamily: 'Raider Straight',
                  fontSize: compact ? 26 : 34,
                  color: Colors.white,
                  height: 1.15)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFFF3E9EC), fontSize: 13)),
        ]),
      );
}

class GraphFormCard extends StatelessWidget {
  const GraphFormCard(
      {required this.title,
      required this.child,
      this.icon = Icons.edit_note,
      super.key});
  final String title;
  final Widget child;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: const Color(0xFFC20000)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleLarge))
              ]),
              const SizedBox(height: 18),
              child,
            ])),
      );
}

class ResponsiveGraphFields extends StatelessWidget {
  const ResponsiveGraphFields(
      {required this.children, this.fullWidthOnNarrow = const {}, super.key});
  final List<Widget> children;
  final Set<int> fullWidthOnNarrow;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = scale > 1.35
            ? 1
            : constraints.maxWidth >= 660
                ? 3
                : constraints.maxWidth >= 300
                    ? 2
                    : 1;
        final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (var index = 0; index < children.length; index++)
            SizedBox(
                width: columns == 2 && fullWidthOnNarrow.contains(index)
                    ? constraints.maxWidth
                    : width,
                child: children[index])
        ]);
      });
}
