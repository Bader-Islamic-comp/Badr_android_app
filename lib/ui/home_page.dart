import 'package:flutter/material.dart';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../data/demo_api.dart';
import '../domain/companion_controller.dart';
import '../theme.dart';
import 'learn_page.dart';
import 'parent_sheet.dart';
import 'quests_page.dart';
import 'style_page.dart';
import 'talk_page.dart';
import 'widgets.dart';

enum CompanionDestination { talk, learn, quests, style }

/// Character-first shell following `design/ui-reference.png`: a compact header,
/// the character room and reply surface, a bottom composer and compact
/// navigation. Flutter owns every interactive control.
class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key, this.controller, this.room});
  final CompanionController? controller;
  final AvatarRoom? room;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome>
    with WidgetsBindingObserver {
  late final CompanionController model;
  late final AvatarRoom room;
  final question = TextEditingController();
  CompanionDestination destination = CompanionDestination.talk;
  int? lessonStep;

  /// `null` follows the platform's reduce-motion setting; a guardian or
  /// operator can override it from the parent area.
  bool? motionOverride;
  bool platformReducedMotion = false;

  bool get motionEnabled => motionOverride ?? !platformReducedMotion;

  @override
  void initState() {
    super.initState();
    model = widget.controller ??
        CompanionController(DemoApi(DemoConfig.environment()));
    room = widget.room ?? AvatarRoom();
    WidgetsBinding.instance.addObserver(this);
    _startRoom();
  }

  Future<void> _startRoom() async {
    await room.start();
    if (!mounted) return;
    await room.setMotionEnabled(motionEnabled);
    await room.setOnCharacterPage(destination == CompanionDestination.talk);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == platformReducedMotion) return;
    platformReducedMotion = reduced;
    room.setMotionEnabled(motionEnabled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    room.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    question.dispose();
    if (widget.controller == null) model.dispose();
    if (widget.room == null) room.dispose();
    super.dispose();
  }

  void _select(CompanionDestination value) {
    setState(() => destination = value);
    room.setOnCharacterPage(value == CompanionDestination.talk);
  }

  void _setMotion(bool enabled) {
    setState(() => motionOverride = enabled);
    room.setMotionEnabled(enabled);
  }

  /// Local deterministic presentation cue. Never a model-generated command.
  void _cue(AvatarReaction reaction) => room.react(reaction);

  Future<void> _startOrientation() async {
    setState(() {
      destination = CompanionDestination.learn;
      lessonStep = 0;
    });
    await room.setOnCharacterPage(false);
  }

  Future<void> _finishOrientation() async {
    final celebrated = await model.completeOrientation();
    if (!mounted) return;
    setState(() {
      lessonStep = null;
      destination = CompanionDestination.quests;
    });
    await room.setOnCharacterPage(false);
    if (celebrated) _cue(AvatarReaction.celebrate);
  }

  Future<void> _ask() async {
    final released = await model.ask(question.text);
    if (!mounted) return;
    if (!model.canRetryQuestion) question.clear();
    if (released) _cue(AvatarReaction.nod);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([model, room]),
        builder: (context, _) => Scaffold(
          // Full bleed: with a room composited behind Flutter the page itself
          // must not paint, or it hides the 3D. Without one it stays opaque,
          // because transparency over nothing shows an empty window.
          backgroundColor: room.surfaceAttached ? Colors.transparent : ivory,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(children: [
                  _header(context),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(children: [
                        DevelopmentBanner(overRoom: room.surfaceAttached),
                        if (model.busy)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                  semanticsLabel: 'Working')),
                        if (model.notice != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Scrim(
                                      enabled: room.surfaceAttached,
                                      child: Text(model.notice!,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14))))),
                      ])),
                  Expanded(child: _page()),
                  if (destination == CompanionDestination.talk) _composer(),
                ]),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: destination.index,
            onDestinationSelected: (value) =>
                _select(CompanionDestination.values[value]),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Talk'),
              NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'Learn'),
              NavigationDestination(
                  icon: Icon(Icons.flag_outlined),
                  selectedIcon: Icon(Icons.flag),
                  label: 'Quests'),
              NavigationDestination(
                  icon: Icon(Icons.spa_outlined),
                  selectedIcon: Icon(Icons.spa),
                  label: 'Style'),
            ],
          ),
        ),
      );

  Widget _header(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        // The header carries the app name, the balance and the parent entry, so
        // it keeps its own surface over a live scene.
        color: room.surfaceAttached ? ivoryScrim : Colors.transparent,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: teal, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Flexible(
              child: Text('little steps',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18, color: ink))),
          const Spacer(),
          StarChip(balance: model.balance),
          IconButton(
              tooltip: 'Parent area',
              onPressed: () => showParentSheet(
                    context,
                    motionEnabled: motionEnabled,
                    onMotionChanged: _setMotion,
                  ),
              icon: const Icon(Icons.shield_outlined)),
        ]),
      );

  Widget _page() => switch (destination) {
        CompanionDestination.talk => TalkPage(
            model: model,
            room: room,
            overRoom: room.surfaceAttached,
            onTapCharacter: () => _cue(AvatarReaction.wave),
            onStartOrientation: _startOrientation,
          ),
        CompanionDestination.learn => LearnPage(
            model: model,
            step: lessonStep,
            onStep: (value) => setState(() => lessonStep = value),
            onFinish: _finishOrientation,
          ),
        CompanionDestination.quests => QuestsPage(model: model),
        CompanionDestination.style => StylePage(
            model: model,
            room: room,
            onEquipped: () => _cue(AvatarReaction.celebrate),
          ),
      };

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        color: room.surfaceAttached ? ivoryScrim : Colors.transparent,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: question,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              enabled: !model.busy && !model.canRetryQuestion,
              onSubmitted: (_) => model.busy ? null : _ask(),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                hintText: model.connected
                    ? 'Type a synthetic test question'
                    : 'Connect the development service to ask',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: hairline)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: hairline)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filled(
              tooltip: model.canRetryQuestion
                  ? 'Retry the same request'
                  : 'Send test question',
              onPressed: model.busy ? null : _ask,
              icon: Icon(model.canRetryQuestion
                  ? Icons.refresh_rounded
                  : Icons.arrow_upward_rounded),
            ),
          ),
        ]),
      );
}
