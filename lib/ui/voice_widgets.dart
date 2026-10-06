import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/demo_api.dart';
import '../domain/speech_models.dart';
import '../speech/speech_player.dart';
import '../speech/voice_capture.dart';
import '../speech/voice_kit.dart';
import '../theme.dart';
import 'text_direction.dart';

/// Hold to record, let go to send. The microphone runs only while a finger is
/// on the button; [VoiceCapture] bounds it and drops it on leaving.
class HoldToTalkButton extends StatelessWidget {
  const HoldToTalkButton({
    super.key,
    required this.capture,
    this.enabled = true,
    this.label = 'Hold to talk',
    this.onPress,
    this.size = 52,
  });

  final VoiceCapture capture;
  final bool enabled;
  final String label;

  /// Called as the button goes down, before recording starts: a page stops
  /// any voice it is playing, so the microphone does not hear it.
  final VoidCallback? onPress;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: capture,
        builder: (context, _) {
          final active = capture.state != CaptureState.idle;
          return Semantics(
            button: true,
            enabled: enabled,
            label: label,
            hint: 'Hold while you speak, then let go to send',
            excludeSemantics: true,
            // Raw pointer events, not a gesture: holding must start at once,
            // and a scrolling list must not take the release away.
            child: Listener(
              onPointerDown: enabled
                  ? (_) {
                      onPress?.call();
                      capture.press();
                    }
                  : null,
              onPointerUp: (_) => capture.release(),
              onPointerCancel: (_) => capture.touchCancelled(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: !enabled
                      ? hairline
                      : active
                          ? listeningRed
                          : teal,
                  shape: BoxShape.circle,
                ),
                child: Icon(active ? Icons.mic : Icons.mic_none_rounded,
                    color: enabled ? Colors.white : muted),
              ),
            ),
          );
        },
      );
}

/// "Listening…" with a red dot and the seconds, while the microphone runs.
class ListeningIndicator extends StatelessWidget {
  const ListeningIndicator({super.key, required this.capture});

  final VoiceCapture capture;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: capture,
        builder: (context, _) {
          if (!capture.listening) return const SizedBox.shrink();
          final seconds = capture.seconds;
          return Semantics(
            liveRegion: true,
            label: 'Listening, $seconds seconds. Let go to send.',
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                      color: listeningRed, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Flexible(
                // One line, so the indicator never grows the composer; the
                // seconds come first and stay in view.
                child: Text('Listening… $seconds s · أستمع',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink)),
              ),
            ]),
          );
        },
      );
}

/// Why a press recorded nothing, if it did.
class CaptureProblem extends StatelessWidget {
  const CaptureProblem({super.key, required this.capture});

  final VoiceCapture capture;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: capture,
        builder: (context, _) => capture.problem == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: VoiceNote(capture.problem!),
              ),
      );
}

/// A short, calm line about the voice: never an alert colour.
class VoiceNote extends StatelessWidget {
  const VoiceNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: directionalText(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: muted)),
      );
}

/// Shown where practice would record while the parent switch is off.
class MicrophoneOffNote extends StatelessWidget {
  const MicrophoneOffNote({super.key});

  static const text = 'A parent can turn on the microphone in the parent area '
      'to practise out loud. Listening works without it.';

  @override
  Widget build(BuildContext context) =>
      const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.mic_off_outlined, color: muted),
        SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: muted))),
      ]);
}

/// The speech preview's content is a draft for adults to try.
class DraftVoiceNotice extends StatelessWidget {
  const DraftVoiceNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12)),
        child: const Text(
            'Draft for adult testing: these texts, and Robert’s '
            'computer-made voice, await scholarly review.',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
      );
}

/// Plays a voice from the service on [player], as [id]: Listen, or Stop
/// while it loads and plays.
class ListenButton extends StatelessWidget {
  const ListenButton({
    super.key,
    required this.player,
    required this.id,
    required this.fetch,
    this.label = 'Listen',
  });

  final SpeechPlayer player;
  final String id;
  final Future<Uint8List> Function() fetch;
  final String label;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final busy = player.busyWith(id);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: busy ? player.stop : () => player.play(id, fetch),
                  icon: player.loading == id
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          busy ? Icons.stop_rounded : Icons.volume_up_rounded),
                  label: Text(busy ? 'Stop' : label),
                ),
                if (player.problemId == id && player.problem != null)
                  VoiceNote(player.problem!),
              ]);
        },
      );
}

/// The words of a practice text, each gently marked by what the service
/// heard when [show] is true: a soft green for "sounded clear", a soft sand
/// with an underline for "let's practise this one", nothing when it could not
/// tell. Without [show] the text is plain.
class PracticeWords extends StatelessWidget {
  const PracticeWords(
      {super.key,
      required this.text,
      this.words = const [],
      this.show = false});

  final String text;
  final List<PracticeWord> words;
  final bool show;

  static const clearLabel = 'sounded clear · واضحة';
  static const practiseLabel = 'practise this one · لنتمرّن عليها';

  @override
  Widget build(BuildContext context) {
    final states = {for (final word in words) word.index: word.state};
    final parts = text.trim().split(RegExp(r'\s+'));
    const base = TextStyle(fontSize: 26, height: 1.7, color: ink);
    final marked = show && states.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(
        TextSpan(children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            TextSpan(text: parts[i], style: marked ? _style(states[i]) : null),
          ],
        ]),
        style: base,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
      ),
      if (marked) ...[
        const SizedBox(height: 6),
        const Wrap(spacing: 16, runSpacing: 4, children: [
          _Key(colour: sage, label: clearLabel),
          _Key(colour: sand, label: practiseLabel),
        ]),
      ],
    ]);
  }

  static TextStyle? _style(PracticeOutcome? state) => switch (state) {
        PracticeOutcome.clear => const TextStyle(backgroundColor: sage),
        PracticeOutcome.tryAgain => const TextStyle(
            backgroundColor: sand,
            decoration: TextDecoration.underline,
            decorationColor: orange),
        PracticeOutcome.unsure || null => null,
      };
}

class _Key extends StatelessWidget {
  const _Key({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: colour,
                border: Border.all(color: hairline),
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: muted)),
      ]);
}

/// Practising one text out loud: hold the button, say it, let go, and read
/// what the service says back. The words, the outcome and the feedback line
/// are all the service's; this panel adds no judgement of its own.
class PracticePanel extends StatefulWidget {
  const PracticePanel({
    super.key,
    required this.text,
    required this.access,
    required this.send,
    required this.player,
    required this.feedbackAudio,
    this.closed,
  });

  final String text;
  final VoiceAccess access;

  /// Sends one recording and returns what the service said. Throws
  /// [DemoApiException] with words fit to show.
  final Future<PracticeResult> Function(Uint8List wav) send;
  final SpeechPlayer player;
  final Future<Uint8List> Function(String copyId) feedbackAudio;

  /// When set, practice of this text is over for now, and this is said in
  /// place of the button.
  final String? closed;

  static const sendingCopy = 'Robert is listening to it…';
  static const promptCopy = 'Hold the button, say it, then let go.';

  @override
  State<PracticePanel> createState() => _PracticePanelState();
}

class _PracticePanelState extends State<PracticePanel> {
  VoiceCapture? capture;
  bool sending = false;
  PracticeResult? result;
  String? problem;

  @override
  void initState() {
    super.initState();
    if (widget.access.canRecord) {
      capture = VoiceCapture(
        recorder: widget.access.kit.recorder,
        maxSeconds: widget.access.maxSeconds,
        onRecorded: _send,
      );
    }
  }

  Future<void> _send(Uint8List wav) async {
    if (!mounted) return;
    setState(() {
      sending = true;
      problem = null;
    });
    try {
      final heard = await widget.send(wav);
      if (mounted) setState(() => result = heard);
    } on DemoApiException catch (error) {
      if (mounted) setState(() => problem = error.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    capture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heard = result;
    final capture = this.capture;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PracticeWords(
          text: widget.text,
          words: heard?.words ?? const [],
          show: heard?.showWords ?? false),
      const SizedBox(height: 12),
      if (capture == null)
        const MicrophoneOffNote()
      else if (widget.closed != null)
        VoiceNote(widget.closed!)
      else ...[
        Row(children: [
          HoldToTalkButton(
            capture: capture,
            enabled: !sending,
            label: 'Hold to say it',
            onPress: widget.player.stop,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ListenableBuilder(
              listenable: capture,
              builder: (context, _) => capture.listening
                  ? ListeningIndicator(capture: capture)
                  : sending
                      ? const Row(children: [
                          SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Flexible(child: Text(PracticePanel.sendingCopy)),
                        ])
                      : const Text(PracticePanel.promptCopy,
                          style: TextStyle(color: muted)),
            ),
          ),
        ]),
        CaptureProblem(capture: capture),
      ],
      if (problem != null)
        Padding(
            padding: const EdgeInsets.only(top: 8), child: VoiceNote(problem!)),
      if (heard != null) ...[
        const SizedBox(height: 12),
        FeedbackLine(
            result: heard, player: widget.player, audio: widget.feedbackAudio),
      ],
    ]);
  }
}

/// The service's feedback line, and its voice when there is one.
class FeedbackLine extends StatelessWidget {
  const FeedbackLine(
      {super.key,
      required this.result,
      required this.player,
      required this.audio});

  final PracticeResult result;
  final SpeechPlayer player;
  final Future<Uint8List> Function(String copyId) audio;

  @override
  Widget build(BuildContext context) {
    final feedback = result.feedback;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              switch (result.outcome) {
                PracticeOutcome.clear => Icons.auto_awesome_rounded,
                PracticeOutcome.tryAgain => Icons.refresh_rounded,
                PracticeOutcome.unsure => Icons.hearing_outlined,
              },
              color: teal),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: directionalText(feedback.text,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600, color: ink)),
            ),
          ),
        ]),
        if (feedback.audio)
          ListenButton(
            player: player,
            id: 'feedback:${feedback.copyId}',
            fetch: () => audio(feedback.copyId),
            label: 'Hear Robert say it',
          ),
      ]),
    );
  }
}
