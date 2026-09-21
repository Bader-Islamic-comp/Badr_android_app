import 'package:flutter/material.dart';

import '../theme.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: hairline),
            borderRadius: BorderRadius.circular(24)),
        child: child,
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = orange});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 1),
      );
}

/// The adult-operator notice. It stays until the release gates in
/// `doc/development-boundary.md` pass.
class DevelopmentBanner extends StatelessWidget {
  const DevelopmentBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration:
            BoxDecoration(color: sand, borderRadius: BorderRadius.circular(10)),
        child: const Text(
          'ADULT DEVELOPMENT PREVIEW · Synthetic data only. Not ready for children.',
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink),
        ),
      );
}

/// Server-owned balance. The reference layout shows a placeholder number; this
/// renders nothing at all until the service has reported a real value.
class StarChip extends StatelessWidget {
  const StarChip({super.key, required this.balance});
  final int? balance;

  @override
  Widget build(BuildContext context) {
    if (balance == null) return const SizedBox.shrink();
    return Semantics(
      label: '$balance learning stars, confirmed by the service',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: sand, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 18, color: orange),
          const SizedBox(width: 4),
          Text('$balance',
              style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        ]),
      ),
    );
  }
}

/// A short status line that never invents a connection or a reward.
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.connected,
    required this.configured,
    required this.busy,
    required this.onConnect,
  });

  final bool connected;
  final bool configured;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              connected ? 'Development service connected' : 'Exploring offline',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(configured
              ? 'Connect or refresh the synthetic server state.'
              : 'Orientation and Robert’s preview work here. A developer must '
                  'configure a demo service to use questions, saved progress '
                  'and inventory.'),
          if (configured)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton(
                    onPressed: busy ? null : onConnect,
                    child: Text(connected
                        ? 'Refresh demo state'
                        : 'Connect development service'))),
        ]),
      );
}
