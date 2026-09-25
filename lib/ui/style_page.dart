import 'package:flutter/material.dart';

import '../domain/companion_controller.dart';
import '../domain/models.dart';
import '../theme.dart';
import 'widgets.dart';

/// The customization tab.
///
/// Ownership, price and equipment are all server-authoritative: a look is
/// earned only after the service records the spend, and reaches the character
/// room only through the service's own record of what is worn. Nothing here
/// unlocks anything locally, and there is no purchase with money, no trade and
/// no randomness — only learning stars the service granted.
class StylePage extends StatelessWidget {
  const StylePage({
    super.key,
    required this.model,
    required this.onEquipped,
  });

  final CompanionController model;
  final VoidCallback onEquipped;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Robert’s looks',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text(
              'Looks are earned with learning stars from quests and lessons. '
              'They are never bought with real money, traded, or won by chance.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          _balance(context),
          const SizedBox(height: 20),
          if (model.cosmetics.isEmpty)
            const Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('The wardrobe lives on the service',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text(
                        'Robert’s static preview is always available. Connect the '
                        'development service to see which looks you have earned.'),
                  ]),
            )
          else
            for (final cosmetic in model.cosmetics)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _lookCard(context, cosmetic),
              ),
          const SizedBox(height: 4),
          const Panel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.brush_outlined, color: orange),
              SizedBox(height: 12),
              Text('What a look changes',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                  'Colour looks recolour Robert in the character room. Outfits '
                  'give him new clothes, like a hat, a vest or boots. Either way '
                  'his face stays as it is, and every look is earned the same '
                  'way: with learning stars.'),
            ]),
          ),
          const SizedBox(height: 16),
          ConnectionCard(
            connected: model.connected,
            configured: model.api.config.enabled,
            busy: model.busy,
            onConnect: model.connect,
          ),
        ],
      );

  Widget _balance(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration:
            BoxDecoration(color: sand, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.star_rounded, color: orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                model.balance == null
                    ? 'Connect to see the stars you have earned'
                    : '${model.balance} learning stars to spend',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, color: ink)),
          ),
        ]),
      );

  Widget _lookCard(BuildContext context, Cosmetic cosmetic) {
    final affordable = model.canAfford(cosmetic);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _swatch(cosmetic),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cosmetic.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(cosmetic.description,
                  style: const TextStyle(fontSize: 15, color: muted)),
            ]),
          ),
          if (cosmetic.equipped) const SectionLabel('In use', color: teal),
        ]),
        const SizedBox(height: 14),
        Text(_state(cosmetic, affordable),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _action(cosmetic, affordable),
      ]),
    );
  }

  /// Colour looks show the colour they install; outfits show a render of
  /// Robert wearing them, because an outfit changes his shape and a colour dot
  /// cannot show that. `default` restores the model's own colours, so it shows
  /// a mark rather than claiming one colour. The picture is decorative: the
  /// look's name follows it.
  Widget _swatch(Cosmetic cosmetic) {
    final preview = cosmeticPreviews[cosmetic.id];
    if (preview != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(preview,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            excludeFromSemantics: true),
      );
    }
    final colour = cosmeticSwatches[cosmetic.id];
    return SizedBox.square(
      dimension: 56,
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: colour ?? sage,
              shape: BoxShape.circle,
              border: Border.all(color: hairline)),
          child: colour == null
              ? const Icon(Icons.auto_awesome_rounded, size: 22, color: teal)
              : null,
        ),
      ),
    );
  }

  String _state(Cosmetic cosmetic, bool affordable) {
    if (cosmetic.equipped) return 'Robert is wearing this.';
    if (cosmetic.owned) return 'Earned · confirmed by the service.';
    if (model.balance == null) return 'Connect to see whether this is earned.';
    if (affordable) return 'Ready to earn for ${cosmetic.cost} stars.';
    return 'Needs ${cosmetic.cost - model.balance!} more stars.';
  }

  Widget _action(Cosmetic cosmetic, bool affordable) {
    if (cosmetic.equipped) {
      return const OutlinedButton(
          onPressed: null, child: Text('Already wearing this'));
    }
    if (cosmetic.owned) {
      return OutlinedButton(
        onPressed: model.busy
            ? null
            : () async {
                // The shell pushes the confirmed look to the room by watching
                // what the service reports, so this only has to record it.
                if (await model.equipCosmetic(cosmetic)) onEquipped();
              },
        child: const Text('Wear this look'),
      );
    }
    return FilledButton(
      onPressed: model.busy || !affordable
          ? null
          : () => model.claimCosmetic(cosmetic),
      child: Text('Earn for ${cosmetic.cost} stars'),
    );
  }
}
