import 'package:flutter/material.dart';

import '../bridge/avatar_bridge.dart';
import '../theme.dart';

/// The central character room of the main page.
///
/// Robert's 3D presentation belongs to Unity. Until the native
/// Unity-as-a-Library host is integrated and validated on a device, this
/// renders the supplied static preview. It deliberately applies no motion to
/// that image: animating a PNG would misrepresent an unimplemented 3D runtime.
/// When a host exists, the Unity surface composites behind [_roomSurface] and
/// Flutter keeps every interactive control above it.
class CharacterStage extends StatelessWidget {
  const CharacterStage({
    super.key,
    required this.status,
    required this.animating,
    required this.motionEnabled,
    this.onTapCharacter,
    this.onOpenRoom,
  });

  final AvatarStatus status;

  /// True when the room is initialized, visible, foregrounded and allowed to
  /// move. Only the room's own renderer acts on it.
  final bool animating;
  final bool motionEnabled;
  final VoidCallback? onTapCharacter;
  final VoidCallback? onOpenRoom;

  bool get _ready => status == AvatarStatus.ready;

  String get _statusLabel => switch (status) {
        AvatarStatus.ready =>
          animating ? 'Character room · playing' : 'Character room · paused',
        AvatarStatus.connecting => 'Looking for the character room…',
        AvatarStatus.staticPreview => 'Robert · static preview',
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
                color: sage, borderRadius: BorderRadius.circular(28)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statusRow(),
                const SizedBox(height: 8),
                if (figure >= 72)
                  Flexible(child: _roomSurface(height: figure))
                else
                  Flexible(child: _roomSurface(height: 72)),
                if (_ready && onOpenRoom != null && !compact) ...[
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

  Widget _statusRow() => Row(children: [
        Icon(Icons.circle, size: 8, color: _ready ? teal : muted),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, color: ink))),
        if (!motionEnabled)
          const Tooltip(
              message: 'Reduced motion is on',
              child: Icon(Icons.motion_photos_off_outlined,
                  size: 18, color: muted)),
      ]);

  Widget _roomSurface({required double height}) {
    // The preview render carries its own dark backdrop. Rounding it frames the
    // room the way the reference layout does instead of repainting the art.
    final figure = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.asset(
        'assets/robert/Robert.png',
        height: height,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stack) => SizedBox(
            height: height,
            child: const Center(
                child: Icon(Icons.smart_toy_outlined, size: 96, color: teal))),
      ),
    );
    if (onTapCharacter == null) {
      return Semantics(
        image: true,
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
