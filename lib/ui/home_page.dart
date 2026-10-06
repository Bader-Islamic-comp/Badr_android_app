import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../data/demo_api.dart';
import '../domain/companion_controller.dart';
import '../domain/models.dart';
import '../theme.dart';
import 'learn_page.dart';
import 'parent_sheet.dart';
import 'quests_page.dart';
import 'robert_cues.dart';
import 'style_page.dart';
import 'talk_page.dart';
import 'text_direction.dart';
import 'widgets.dart';

enum CompanionDestination { talk, learn, quests, style }

/// Character-first shell following `design/ui-reference.png`: a compact header,
/// the character room and reply surface, a bottom composer and compact
/// navigation. Flutter owns every interactive control.
class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key, this.controller, this.room, this.startTimer});
  final CompanionController? controller;
  final AvatarRoom? room;

  /// Times how long Robert talks. Tests pass their own so they can end a talk
  /// without waiting on the clock.
  final StartTimer? startTimer;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome>
    with WidgetsBindingObserver {
  late final CompanionController model;
  late final AvatarRoom room;
  late final RobertCues cues;

  /// The reply Robert is talking about, by identity: when the controller no
  /// longer shows it, the talk stops.
  Reply? speaking;
  final question = TextEditingController();
  CompanionDestination destination = CompanionDestination.talk;
  int? lessonStep;

  /// `null` follows the platform's reduce-motion setting; a guardian or
  /// operator can override it from the parent area.
  bool? motionOverride;
  bool platformReducedMotion = false;

  /// Whether a parent has turned on the movement helper. Off at every start:
  /// the camera is never on by default.
  bool movementHelper = false;

  bool get motionEnabled => motionOverride ?? !platformReducedMotion;
  bool get onCharacterPage => destination == CompanionDestination.talk;

  /// The look this room session has been told about, so a look is pushed once
  /// per room rather than on every notification.
  String? appliedCosmetic;

  @override
  void initState() {
    super.initState();
    model = widget.controller ??
        CompanionController(DemoApi(DemoConfig.environment()));
    room = widget.room ?? AvatarRoom();
    cues = RobertCues(room, startTimer: widget.startTimer);
    // The room follows the service's record of what is worn, not the tap that
    // changed it: that is also what restores the look after a relaunch or a
    // room rebuild, neither of which involves a tap.
    model.addListener(_syncCosmetic);
    room.addListener(_syncCosmetic);
    model.addListener(_syncTalk);
    WidgetsBinding.instance.addObserver(this);
    _startRoom();
  }

  /// Robert stops talking the moment the reply he is talking about goes:
  /// cleared, or replaced when a new question starts.
  void _syncTalk() {
    if (speaking == null || identical(model.reply, speaking)) return;
    speaking = null;
    cues.quiet();
  }

  void _syncCosmetic() {
    if (room.status != AvatarStatus.ready) {
      // A rebuilt room installs its default look, so the next ready room has
      // to be told again.
      appliedCosmetic = null;
      return;
    }
    final equipped = model.equippedCosmeticId;
    if (equipped == null || equipped == appliedCosmetic) return;
    appliedCosmetic = equipped;
    unawaited(room.applyServerConfirmedCosmetic(equipped));
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
    if (!motionEnabled) cues.quiet();
    room.setMotionEnabled(motionEnabled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (!foreground) cues.backgrounded();
    room.setForeground(foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_syncCosmetic);
    room.removeListener(_syncCosmetic);
    model.removeListener(_syncTalk);
    cues.dispose();
    question.dispose();
    if (widget.controller == null) model.dispose();
    if (widget.room == null) room.dispose();
    super.dispose();
  }

  Future<void> _select(CompanionDestination value) async {
    setState(() => destination = value);
    final talk = value == CompanionDestination.talk;
    // Ended while the room is still resumed, so the room accepts it; the
    // bridge would also end a talk on the pause that follows.
    if (!talk) cues.quiet();
    await room.setOnCharacterPage(talk);
    if (talk && mounted && destination == CompanionDestination.talk) {
      cues.characterShown();
    }
  }

  void _setMotion(bool enabled) {
    setState(() => motionOverride = enabled);
    if (!enabled) cues.quiet();
    room.setMotionEnabled(enabled);
  }

  Future<void> _finishOrientation() async {
    final celebrated = await model.completeOrientation();
    if (!mounted) return;
    setState(() {
      lessonStep = null;
      destination = CompanionDestination.quests;
    });
    await room.setOnCharacterPage(false);
    // Robert is off screen on Quests, so the celebration waits for him.
    if (celebrated) cues.orientationCompleted();
  }

  Future<void> _ask() async {
    // A new question: whatever Robert was saying about the last reply stops.
    speaking = null;
    cues.quiet();
    final released = await model.ask(question.text);
    if (!mounted) return;
    if (!model.canRetryQuestion) question.clear();
    final reply = model.reply;
    if (released && reply != null && onCharacterPage) {
      speaking = reply;
      // The answer type and the length are all that leave the reply here.
      cues.replyShown(reply.type, reply.text.runes.length);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([model, room]),
        builder: (context, _) => Scaffold(
          // Full bleed: with a room composited behind Flutter the page itself
          // must not paint, or it hides the 3D. Without one it stays opaque,
          // because transparency over nothing shows an empty window.
          backgroundColor: room.surfaceAttached ? Colors.transparent : ivory,
          // Off the character page the backdrop covers the whole window, not
          // just the content: the header strip and the notch area would
          // otherwise still be a window onto the live room, with Robert
          // showing through beside the title.
          body: _backdrop(
              child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(children: [
                  // The character page is the character's: no title bar and no
                  // banner over him. Both stay on every other page, so the
                  // parent entry, the balance and the adult-operator notice are
                  // one tap away and are not lost.
                  if (!onCharacterPage) _header(context),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(children: [
                        if (!onCharacterPage) const DevelopmentBanner(),
                        // On the character page the thinking bubble already
                        // says Robert is working, for as long as a reply takes;
                        // a bar across the top of his page would say it twice.
                        if (model.busy &&
                            !(onCharacterPage && model.waitingForReply))
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
                  if (onCharacterPage)
                    Shortcuts(shortcuts: _clipboardKeys, child: _composer()),
                ]),
              ),
            ),
          )),
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

  /// Robert lives in the room, and the room is the character page. Every other
  /// page shows the same place without him — the backdrop's own picture, the
  /// one the Unity room renders, veiled so a headline stays readable over it.
  /// It also makes those pages look the same whether or not a room is running.
  Widget _backdrop({required Widget child}) {
    if (onCharacterPage) return child;
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/room/backdrop_desert.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(color: backdropVeil, child: child),
    );
  }

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
                    model: model,
                    room: room,
                    motionEnabled: motionEnabled,
                    onMotionChanged: _setMotion,
                    movementHelper: movementHelper,
                    onMovementHelperChanged: (value) =>
                        setState(() => movementHelper = value),
                  ),
              icon: const Icon(Icons.shield_outlined)),
        ]),
      );

  Widget _page() => switch (destination) {
        CompanionDestination.talk => TalkPage(
            model: model,
            room: room,
            overRoom: room.surfaceAttached,
            onTapCharacter: () {
              cues.tapped();
            },
          ),
        CompanionDestination.learn => LearnPage(
            model: model,
            step: lessonStep,
            onStep: (value) => setState(() => lessonStep = value),
            onFinish: _finishOrientation,
            movementHelper: movementHelper,
          ),
        CompanionDestination.quests => QuestsPage(model: model),
        CompanionDestination.style => StylePage(
            model: model,
            onEarned: cues.lookEarned,
            onEquipped: cues.lookWorn,
          ),
      };

  /// A hardware keyboard's own Paste, Copy and Cut keys (Android's
  /// KEYCODE_PASTE, _COPY and _CUT). Flutter maps Ctrl+V, Ctrl+C and Ctrl+X
  /// for a text field, but not these, so without this they did nothing.
  static final _clipboardKeys = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.paste):
        const PasteTextIntent(SelectionChangedCause.keyboard),
    const SingleActivator(LogicalKeyboardKey.copy):
        CopySelectionTextIntent.copy,
    const SingleActivator(LogicalKeyboardKey.cut):
        const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  };

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        color: room.surfaceAttached ? ivoryScrim : Colors.transparent,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            // An Arabic question is typed right to left, like its reply.
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: question,
              builder: (context, value, _) => TextField(
                controller: question,
                textDirection: directionOf(value.text),
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
                  // Friendly, but still says the text is for testing: this is a
                  // development build and nothing real belongs in it. Kept short
                  // so that at 320 px and 2× text it wraps less than the old
                  // hint did, not more.
                  hintText: !model.connected
                      ? 'Connect the development service to ask'
                      : model.unreviewedDrafts
                          ? 'Ask the draft corpus (adults only)'
                          : 'Say hi or ask (test text only)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: hairline)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: hairline)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: _connectsHere
                ? IconButton.filled(
                    tooltip: 'Connect development service',
                    onPressed: model.busy ? null : model.connect,
                    icon: const Icon(Icons.link_rounded),
                  )
                : IconButton.filled(
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

  /// A configured build that is not connected yet connects from the composer:
  /// its hint asks for a connection, and sending could only say the same
  /// again. Connecting stays something an adult does, never automatic.
  bool get _connectsHere => !model.connected && model.api.config.enabled;
}
