import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/demo_api.dart';
import '../domain/companion_controller.dart';
import '../domain/speech_models.dart';
import '../speech/speech_player.dart';
import '../speech/voice_kit.dart';
import '../theme.dart';
import 'adhkar_page.dart';
import 'voice_widgets.dart';
import 'widgets.dart';

/// The dhikr game: pick a dhikr, hear Robert say it, hold the microphone and
/// say it. A round ends when the service hears it clearly or after three
/// counted tries, and a finished round earns a star for practising. The star
/// and the balance are the service's; nothing is counted here.
///
/// No timers, no streaks and no rankings. When the day's game stars are all
/// given, the game still plays, and says so warmly.
class DhikrGamePage extends StatefulWidget {
  const DhikrGamePage({
    super.key,
    required this.model,
    required this.access,
    required this.onOpenStyle,
  });

  final CompanionController model;
  final VoiceAccess access;

  /// Leaves the game for the Style tab, to see what stars unlock.
  final VoidCallback onOpenStyle;

  static const intro = 'Pick a dhikr, listen to Robert, then hold the '
      'microphone and say it. Each round you finish earns a star for '
      'practising.';
  static const starsCollected = 'The game’s stars for today are all '
      'collected. You can keep playing just for practice.';
  static const lovelyPractice = 'What lovely practice! The game’s stars for '
      'today are all collected, so this round was just for fun.';
  static const wellDone = 'Well done for practising!';
  static const starEarned = '+1 star · +1 نجمة';

  /// The service says the round is already finished: a try whose answer did
  /// not reach the app (a lost connection) finished it.
  static const finishedEarlier = 'Your last try finished this round. Well '
      'done for practising!';

  @override
  State<DhikrGamePage> createState() => _DhikrGamePageState();
}

class _DhikrGamePageState extends State<DhikrGamePage> {
  late final player = SpeechPlayer(widget.access.kit.playback);
  DemoApi get api => widget.model.api;

  DhikrGame? game;
  bool loading = true;
  String? problem;

  Dhikr? chosen;
  DhikrRound? round;
  bool starting = false;

  /// A try is with the service. The round stays as it is until its answer
  /// is in: choosing another dhikr waits.
  bool sending = false;

  /// One key per dhikr whose round is being started, so a retry after a lost
  /// answer finds the same round rather than making a second one, and
  /// another dhikr never reuses a key with a different request.
  final Map<String, String> roundKeys = {};

  /// The attempt that finished the round, for its feedback line.
  PracticeResult? lastAttempt;

  /// The service reported the round as already finished, by a try whose
  /// answer never reached the app. Whether it gave a star is not known here;
  /// the balance read again from the service shows it.
  bool finishedEarlier = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      problem = null;
    });
    try {
      final loaded = await api.dhikrGame();
      if (mounted) setState(() => game = loaded);
    } on DemoApiException catch (error) {
      if (mounted) setState(() => problem = error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _start(Dhikr dhikr) async {
    await player.stop();
    if (!mounted) return;
    setState(() {
      chosen = dhikr;
      round = null;
      lastAttempt = null;
      finishedEarlier = false;
      starting = true;
      problem = null;
    });
    try {
      final key = roundKeys[dhikr.id] ??= DemoApi.newKey();
      final started = await api.startDhikrRound(dhikr.id, key);
      roundKeys.remove(dhikr.id);
      // The child chose another dhikr while this one was starting: the round
      // is left unplayed, and Robert does not say a dhikr no longer shown.
      if (!mounted || chosen?.id != dhikr.id) return;
      setState(() => round = started);
      // Robert says it first, so the child hears it before trying.
      if (dhikr.audio) {
        unawaited(
            player.play('dhikr:${dhikr.id}', () => api.dhikrAudio(dhikr.id)));
      }
    } on DemoApiException catch (error) {
      if (mounted && chosen?.id == dhikr.id) {
        setState(() => problem = error.message);
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<PracticeResult> _attempt(Uint8List wav) async {
    final current = round!;
    final dhikr = chosen!;
    // Only the round this try was sent to takes its answer. A late answer for
    // a round the child has left is never shown on another one.
    bool stillHere() =>
        mounted &&
        chosen?.id == dhikr.id &&
        round?.roundId == current.roundId &&
        !round!.complete;
    setState(() => sending = true);
    try {
      final result =
          await api.dhikrAttempt(current.roundId, wav, DemoApi.newKey());
      if (!stillHere()) {
        // Left mid-try: the star chip elsewhere is read again from the
        // service, never counted here.
        if (result.round.starAwarded) {
          unawaited(widget.model.refreshProgress());
        }
        return result.attempt;
      }
      setState(() {
        round = result.round;
        if (result.round.complete) lastAttempt = result.attempt;
      });
      if (result.round.complete) {
        // The service's own balance after the round, shown even when a
        // refresh cannot run now; the refresh then reads the rest.
        widget.model.showServiceBalance(result.balance);
        unawaited(_finished(refresh: result.round.starAwarded));
      }
      return result.attempt;
    } on DemoApiException catch (error) {
      if (stillHere()) {
        if (error.code == 'round_complete') {
          // A try whose answer was lost finished the round on the service.
          // It is shown finished, and the balance is read again for its star.
          setState(() {
            round = DhikrRound(
                roundId: current.roundId,
                dhikrId: current.dhikrId,
                attempts: current.attempts,
                countedAttempts: current.countedAttempts,
                complete: true,
                starAwarded: false);
            lastAttempt = null;
            finishedEarlier = true;
          });
          unawaited(_finished(refresh: true));
        } else if (error.code == 'round_not_found') {
          // The service has no open round to add this to: say so, and offer
          // a new one.
          setState(() {
            round = null;
            problem = error.message;
          });
        }
      }
      rethrow;
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// A round finished: the balance is read again from the service when
  /// [refresh] says it may have changed, and the game's own count of today's
  /// stars with it.
  Future<void> _finished({required bool refresh}) async {
    if (refresh) await widget.model.refreshProgress();
    try {
      final loaded = await api.dhikrGame();
      if (mounted) setState(() => game = loaded);
    } on DemoApiException {
      // The round is already shown as finished; the count can wait.
    }
  }

  void _choose() {
    unawaited(player.stop());
    setState(() {
      chosen = null;
      round = null;
      lastAttempt = null;
      finishedEarlier = false;
      problem = null;
    });
  }

  @override
  Widget build(BuildContext context) => VoicePageFrame(
        title: 'Dhikr game · لعبة الذكر',
        actions: [
          ListenableBuilder(
            listenable: widget.model,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StarChip(balance: widget.model.balance),
            ),
          ),
        ],
        children: [
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (game == null)
            RetryPanel(message: problem ?? '', onRetry: _load)
          else if (chosen == null)
            ..._picker(context, game!)
          else
            ..._round(context, chosen!),
          const SizedBox(height: 16),
          const Text(practiceOnly, style: TextStyle(color: muted)),
        ],
      );

  List<Widget> _picker(BuildContext context, DhikrGame game) => [
        const Text(DhikrGamePage.intro, style: TextStyle(color: muted)),
        const SizedBox(height: 12),
        if (game.starsCollected) ...[
          const Panel(
              child: Row(children: [
            Icon(Icons.favorite_rounded, color: orange),
            SizedBox(width: 12),
            Expanded(child: Text(DhikrGamePage.starsCollected)),
          ])),
          const SizedBox(height: 12),
        ],
        if (problem != null) ...[
          VoiceNote(problem!),
          const SizedBox(height: 12),
        ],
        for (final dhikr in game.items) ...[
          Panel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${dhikr.nameEn} · ${dhikr.nameAr}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              PracticeWords(text: dhikr.text),
              const SizedBox(height: 8),
              FilledButton(
                onPressed:
                    dhikr.practice && !starting ? () => _start(dhikr) : null,
                child: Text('Play with ${dhikr.nameEn}'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
      ];

  List<Widget> _round(BuildContext context, Dhikr dhikr) {
    final round = this.round;
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${dhikr.nameEn} · ${dhikr.nameAr}',
              style: Theme.of(context).textTheme.titleLarge),
          if (dhikr.audio)
            ListenButton(
              player: player,
              id: 'dhikr:${dhikr.id}',
              fetch: () => api.dhikrAudio(dhikr.id),
              label: 'Hear Robert say it',
            ),
          const SizedBox(height: 8),
          if (round == null)
            starting
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        if (problem != null) VoiceNote(problem!),
                        const SizedBox(height: 8),
                        FilledButton(
                            onPressed: () => _start(dhikr),
                            child: const Text('Start a new round')),
                      ])
          else if (!round.complete) ...[
            _tries(round),
            const SizedBox(height: 12),
            PracticePanel(
              key: ValueKey('round-${round.roundId}'),
              text: dhikr.text,
              access: widget.access,
              send: _attempt,
              player: player,
              feedbackAudio: api.feedbackAudio,
            ),
          ] else
            _complete(context, round),
        ]),
      ),
      const SizedBox(height: 12),
      // Not while a try is with the service: its answer belongs to this round.
      TextButton(
          onPressed: sending ? null : _choose,
          child: const Text('Choose another dhikr')),
    ];
  }

  /// Three tries a round: the ones the service counted, and the one now.
  Widget _tries(DhikrRound round) {
    final now = (round.countedAttempts + 1).clamp(1, DhikrRound.tries);
    return Semantics(
      label: 'Try $now of ${DhikrRound.tries}',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 0; i < DhikrRound.tries; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
                i < round.countedAttempts
                    ? Icons.circle
                    : Icons.circle_outlined,
                size: 14,
                color: teal),
          ),
        const SizedBox(width: 6),
        Text('Try $now of ${DhikrRound.tries}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _complete(BuildContext context, DhikrRound round) {
    final last = lastAttempt;
    final balance = ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => widget.model.balance == null
          ? const SizedBox.shrink()
          : Text('You have ${widget.model.balance} learning stars.',
              style: const TextStyle(color: muted)),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (last != null) ...[
        FeedbackLine(result: last, player: player, audio: api.feedbackAudio),
        const SizedBox(height: 16),
      ],
      if (finishedEarlier) ...[
        const Text(DhikrGamePage.finishedEarlier,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        balance,
      ] else if (round.starAwarded) ...[
        _Celebration(reduceMotion: MediaQuery.disableAnimationsOf(context)),
        const SizedBox(height: 8),
        const Text(DhikrGamePage.wellDone,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        balance,
      ] else
        const Text(DhikrGamePage.lovelyPractice,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 8, children: [
        FilledButton(
            onPressed: starting ? null : () => _start(chosen!),
            child: const Text('Play again')),
        OutlinedButton.icon(
            onPressed: widget.onOpenStyle,
            icon: const Icon(Icons.spa_outlined),
            label: const Text('See looks in Style')),
      ]),
    ]);
  }
}

/// "+1 star": a small, quick grow-in, still under reduced motion.
class _Celebration extends StatelessWidget {
  const _Celebration({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    const content = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, color: orange, size: 40),
      SizedBox(width: 8),
      Text(DhikrGamePage.starEarned,
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w800, color: orange)),
    ]);
    return Semantics(
      liveRegion: true,
      label: 'One star earned for practising',
      excludeSemantics: true,
      child: reduceMotion
          ? content
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: content,
            ),
    );
  }
}
