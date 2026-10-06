import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/avatar_bridge.dart';
import '../bridge/avatar_room.dart';
import '../data/demo_api.dart';
import '../domain/companion_controller.dart';
import '../domain/models.dart';
import '../speech/robert_voice.dart';
import '../speech/voice_capture.dart';
import '../speech/voice_kit.dart';
import '../theme.dart';
import 'adhkar_page.dart';
import 'dhikr_game_page.dart';
import 'duas_page.dart';
import 'learn_page.dart';
import 'parent_sheet.dart';
import 'quests_page.dart';
import 'robert_cues.dart';
import 'style_page.dart';
import 'talk_page.dart';
import 'text_direction.dart';
import 'voice_widgets.dart';
import 'widgets.dart';

enum CompanionDestination { talk, learn, quests, style }

/// Character-first shell following `design/ui-reference.png`: a compact header,
/// the character room and reply surface, a bottom composer and compact
/// navigation. Flutter owns every interactive control.
class CompanionHome extends StatefulWidget {
  const CompanionHome(
      {super.key, this.controller, this.room, this.startTimer, this.voice});
  final CompanionController? controller;
  final AvatarRoom? room;

  /// The speech preview's parts. Tests pass fakes and their own build switch.
  final VoiceKit? voice;

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

  /// Whether a parent has turned on the microphone for the speech preview.
  /// Off at every start and never saved: nothing records by default.
  bool microphone = false;

  late final VoiceKit kit = widget.voice ?? const VoiceKit();

  /// Robert reading his reply aloud, on request.
  late final RobertVoice robertVoice;

  /// The composer's hold-to-talk, made the first time it is shown.
  VoiceCapture? questionMic;
  bool transcribing = false;

  /// What the composer says about the last spoken question.
  String? voiceNote;

  /// The language a spoken question is heard in.
  bool speakArabic = true;

  static const heardCopy =
      'Check the words, then send them. · تأكّد من الكلمات ثم أرسلها';
  static const unsureCopy = 'I didn’t catch that. Try again or type it. · '
      'لم أسمعك جيدًا، جرّب مرة أخرى أو اكتبها';
  static const writingCopy = 'Writing down what you said…';

  /// What of the speech preview shows: the build, the service and the
  /// parent's switch together.
  VoiceAccess get access => VoiceAccess(
      kit: kit,
      features: model.speech,
      connected: model.connected,
      microphone: microphone);

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
    robertVoice = RobertVoice(model.api, kit,
        onSpeaking: (speaking) =>
            speaking ? cues.voiceStarted() : cues.voiceEnded());
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
    // Robert's voice belongs to one reply: a new one, a clear or a service
    // without the preview ends it.
    final voiced = robertVoice.turnId;
    if (voiced != null &&
        (voiced != model.reply?.turnId || !access.robertVoice)) {
      unawaited(robertVoice.stop());
    }
    if (!access.voiceQuestions) questionMic?.cancel();
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
    if (!foreground) {
      // Robert's voice stops with the app; a recording drops itself.
      unawaited(robertVoice.stop());
      cues.backgrounded();
    }
    room.setForeground(foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_syncCosmetic);
    room.removeListener(_syncCosmetic);
    model.removeListener(_syncTalk);
    robertVoice.dispose();
    questionMic?.dispose();
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
    if (!talk) {
      unawaited(robertVoice.stop());
      questionMic?.cancel();
      cues.quiet();
    }
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

  void _setMicrophone(bool value) {
    setState(() => microphone = value);
    if (!value) {
      questionMic?.cancel();
      voiceNote = null;
    }
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  void _openStyle() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _select(CompanionDestination.style);
  }

  /// The composer's microphone, for the service's current bound.
  VoiceCapture get _questionMic {
    final existing = questionMic;
    if (existing != null && existing.maxSeconds == access.maxSeconds) {
      return existing;
    }
    existing?.dispose();
    return questionMic = VoiceCapture(
        recorder: kit.recorder,
        maxSeconds: access.maxSeconds,
        onRecorded: _transcribe);
  }

  /// Sends a spoken question to be written down, and puts what was heard in
  /// the composer for the child to check and send. Nothing is sent to Robert
  /// until they do.
  Future<void> _transcribe(Uint8List wav) async {
    setState(() {
      transcribing = true;
      voiceNote = null;
    });
    try {
      final heard =
          await model.api.transcribe(wav, language: speakArabic ? 'ar' : 'en');
      if (!mounted) return;
      final text = heard.text;
      if (text == null) {
        voiceNote = unsureCopy;
      } else {
        final before = question.text.trim();
        var combined = before.isEmpty ? text : '$before $text';
        if (combined.length > 1000) combined = combined.substring(0, 1000);
        question.value = TextEditingValue(
            text: combined,
            selection: TextSelection.collapsed(offset: combined.length));
        voiceNote = heardCopy;
      }
    } on DemoApiException catch (error) {
      voiceNote = error.message;
    } finally {
      if (mounted) setState(() => transcribing = false);
    }
  }

  Future<void> _ask() async {
    // A new question: whatever Robert was saying about the last reply stops.
    speaking = null;
    unawaited(robertVoice.stop());
    voiceNote = null;
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
                    voice: access,
                    onMicrophoneChanged: _setMicrophone,
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
            voice: access.robertVoice ? robertVoice : null,
            voiceStrip: switch (_composerMic) {
              final mic? => _voiceStrip(mic),
              null => null,
            },
          ),
        CompanionDestination.learn => LearnPage(
            model: model,
            step: lessonStep,
            onStep: (value) => setState(() => lessonStep = value),
            onFinish: _finishOrientation,
            movementHelper: movementHelper,
            onOpenAdhkar: access.preview
                ? () => _push(AdhkarPage(api: model.api, access: access))
                : null,
            onOpenDuas: access.preview
                ? () => _push(DuasPage(api: model.api, access: access))
                : null,
          ),
        CompanionDestination.quests => QuestsPage(
            model: model,
            onOpenGame: access.recitation
                ? () => _push(DhikrGamePage(
                    model: model, access: access, onOpenStyle: _openStyle))
                : null,
          ),
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

  /// The composer's microphone, when a question can be asked out loud here.
  VoiceCapture? get _composerMic =>
      access.voiceQuestions && !_connectsHere ? _questionMic : null;

  Widget _composer() {
    final mic = _composerMic;
    final canSpeak = !model.busy && !model.canRetryQuestion && !transcribing;
    return Container(
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
        // With the microphone on and nothing typed, the button is the
        // microphone: there is nothing to send yet. Typing brings Send back.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: question,
          builder: (context, value, _) => SizedBox(
            width: 52,
            height: 52,
            child: _connectsHere
                ? IconButton.filled(
                    tooltip: 'Connect development service',
                    onPressed: model.busy ? null : model.connect,
                    icon: const Icon(Icons.link_rounded),
                  )
                : mic != null &&
                        value.text.trim().isEmpty &&
                        !model.canRetryQuestion
                    ? HoldToTalkButton(
                        capture: mic,
                        enabled: canSpeak,
                        label: 'Hold to ask Robert out loud',
                        onPress: () {
                          unawaited(robertVoice.stop());
                          setState(() => voiceNote = null);
                        },
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
        ),
      ]),
    );
  }

  /// Just above the composer, at the foot of Talk, while the microphone is
  /// on: the listening indicator while held, then what happened to the
  /// question, and beside it the language a question is heard in.
  Widget _voiceStrip(VoiceCapture mic) => ListenableBuilder(
        listenable: mic,
        builder: (context, _) {
          final Widget line = mic.listening
              ? ListeningIndicator(capture: mic)
              : transcribing
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Flexible(child: Text(writingCopy)),
                    ])
                  : Row(children: [
                      _languageToggle(),
                      const SizedBox(width: 10),
                      Expanded(
                          child: mic.problem != null
                              ? VoiceNote(mic.problem!)
                              : voiceNote != null
                                  ? VoiceNote(voiceNote!)
                                  : const SizedBox.shrink()),
                    ]);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
            child: Align(alignment: Alignment.centerLeft, child: line),
          );
        },
      );

  /// The language a spoken question is heard in: Arabic unless changed.
  Widget _languageToggle() => Semantics(
        button: true,
        label: speakArabic
            ? 'Speaking Arabic. Tap for English.'
            : 'Speaking English. Tap for Arabic.',
        excludeSemantics: true,
        child: OutlinedButton(
          onPressed: () => setState(() => speakArabic = !speakArabic),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact),
          child: Text(speakArabic ? 'ع' : 'EN',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      );

  /// A configured build that is not connected yet connects from the composer:
  /// its hint asks for a connection, and sending could only say the same
  /// again. Connecting stays something an adult does, never automatic.
  bool get _connectsHere => !model.connected && model.api.config.enabled;
}
