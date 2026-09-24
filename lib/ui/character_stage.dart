import 'package:flutter/material.dart';

import '../bridge/avatar_bridge.dart';
import '../theme.dart';

/// The character room's place on the main page.
///
/// With a room composited behind Flutter the page is full-bleed: this reserves
/// the space and stays transparent so the live 3D shows through, carrying only
/// the tap target. Without one it falls back to the supplied static preview on
/// its own card.
///
/// It deliberately applies no motion to that static image: animating a PNG
/// would misrepresent a 3D runtime that is not there.
class CharacterStage extends StatelessWidget {
  const CharacterStage({
    super.key,
    required this.status,
    required this.animating,
    required this.motionEnabled,
    required this.surfaceAttached,
    this.onTapCharacter,
    this.onOpenRoom,
  });

  final AvatarStatus status;

  /// True when the room is initialized, visible, foregrounded and allowed to
  /// move. Only the room's own renderer acts on it.
  final bool animating;
  final bool motionEnabled;

  /// True when a room surface is composited behind Flutter, so this may be a
  /// transparent window rather than a static card.
  final bool surfaceAttached;
  final VoidCallback? onTapCharacter;
  final VoidCallback? onOpenRoom;

  bool get _ready => status == AvatarStatus.ready;

  /// How the room is doing, in words. The character page does not show this —
  /// it is developer state, not something a child needs over Robert's face —
  /// so the parent area renders it instead.
  static String statusLabel(
          AvatarStatus status, bool animating, bool surfaceAttached) =>
      switch (status) {
        AvatarStatus.ready =>
          animating ? 'Character room · playing' : 'Character room · paused',
        AvatarStatus.connecting => 'Looking for the character room…',
        AvatarStatus.staticPreview => surfaceAttached
            ? 'Character room · not connected'
            : 'Robert · static preview',
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // Readable text and reachable controls take priority over the
          // character: the stage gives up its own height first.
          final available =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0;
          final compact = available < 210;
          final figure = (available - (compact ? 56 : 84)).clamp(0.0, 300.0);
          return Container(
            padding: EdgeInsets.all(compact ? 12 : 18),
            decoration: BoxDecoration(
                // Transparent over a live room; the sage card only frames the
                // static preview.
                color: surfaceAttached ? Colors.transparent : sage,
                borderRadius: BorderRadius.circular(28)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                    child: _roomSurface(height: figure < 72 ? 72 : figure)),
                // Only meaningful when the room is not already the page's
                // background. Over a full-bleed room it would sit across the
                // character's feet and open what is already open.
                if (_ready &&
                    onOpenRoom != null &&
                    !compact &&
                    !surfaceAttached) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                      onPressed: onOpenRoom,
                      child: const Text('Open character room')),
                ],
              ],
            ),
          );
        },
      );

  Widget _roomSurface({required double height}) {
    // A live room draws itself behind this; painting anything here would cover
    // it. The space is still reserved, and still tappable.
    final figure = surfaceAttached
        ? SizedBox(height: height, width: double.infinity)
        : ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/robert/Robert.png',
              height: height,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stack) => SizedBox(
                  height: height,
                  child: const Center(
                      child: Icon(Icons.smart_toy_outlined,
                          size: 96, color: teal))),
            ),
          );
    if (onTapCharacter == null) {
      return Semantics(
        image: !surfaceAttached,
        label: 'Robert, your orange and teal robot learning companion',
        child: figure,
      );
    }
    // GestureDetector contributes the tap action; this annotates that same node
    // rather than replacing it, so assistive technology can still activate it.
    return Semantics(
      button: true,
      label: 'Say hello to Robert',
      hint: 'Robert gives a short wave or nod',
      child: GestureDetector(
        onTap: onTapCharacter,
        behavior: HitTestBehavior.opaque,
        child: figure,
      ),
    );
  }
}
