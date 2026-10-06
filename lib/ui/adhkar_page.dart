import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/demo_api.dart';
import '../domain/speech_models.dart';
import '../speech/speech_player.dart';
import '../speech/voice_kit.dart';
import '../theme.dart';
import 'voice_widgets.dart';
import 'widgets.dart';

/// Practice of a text, attempt by attempt. The service takes attempts 1 to
/// 10; after that the practice rests until the page opens again.
const practiceAttempts = 10;

/// Said when a text has had all its attempts for now. Warm, and no loss.
const practiceRest =
    'Lovely practising! Have a rest, and come back to it whenever you like.';

/// Said at the foot of every practice page.
const practiceOnly = 'This is practice for saying the words clearly. It is '
    'not a test, and Robert does not judge anyone’s worship. Ask a parent or '
    'teacher about reciting.';

/// The four short adhkar: listen to Robert, then practise saying them.
/// Practice earns no stars; that is the dhikr game on Quests.
class AdhkarPage extends StatefulWidget {
  const AdhkarPage({super.key, required this.api, required this.access});

  final DemoApi api;
  final VoiceAccess access;

  @override
  State<AdhkarPage> createState() => _AdhkarPageState();
}

class _AdhkarPageState extends State<AdhkarPage> {
  late final player = SpeechPlayer(widget.access.kit.playback);
  AdhkarList? list;
  String? problem;
  bool loading = true;

  /// The dhikr whose practice is open. One at a time.
  String? practising;
  final Map<String, int> attempts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      problem = null;
    });
    try {
      final loaded = await widget.api.adhkar();
      if (mounted) setState(() => list = loaded);
    } on DemoApiException catch (error) {
      if (mounted) setState(() => problem = error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<PracticeResult> _practise(String id, Uint8List wav) async {
    final attempt = (attempts[id] ?? 0) + 1;
    final result = await widget.api.practise(
        itemId: id,
        segment: 0,
        attempt: attempt,
        wav: wav,
        key: DemoApi.newKey());
    if (mounted) setState(() => attempts[id] = attempt);
    return result;
  }

  @override
  Widget build(BuildContext context) => VoicePageFrame(
        title: 'Adhkar · أذكار',
        children: [
          const Text(
              'Listen to Robert say each dhikr, then hold the microphone and '
              'say it yourself. Practice helps your pronunciation. There are '
              'no stars here, just practice.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          if (list?.draft ?? true) ...[
            const DraftVoiceNotice(),
            const SizedBox(height: 16),
          ],
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (problem != null)
            RetryPanel(message: problem!, onRetry: _load)
          else
            for (final dhikr in list!.items) ...[
              Panel(child: _card(context, dhikr)),
              const SizedBox(height: 16),
            ],
          const Text(practiceOnly, style: TextStyle(color: muted)),
        ],
      );

  Widget _card(BuildContext context, Dhikr dhikr) {
    final open = practising == dhikr.id;
    final canPractise = widget.access.recitation && dhikr.practice;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${dhikr.nameEn} · ${dhikr.nameAr}',
          style: Theme.of(context).textTheme.titleLarge),
      if (dhikr.transliteration != null)
        Text(dhikr.transliteration!,
            style: const TextStyle(color: muted, fontStyle: FontStyle.italic)),
      const SizedBox(height: 12),
      if (open)
        PracticePanel(
          key: ValueKey('practice-${dhikr.id}'),
          text: dhikr.text,
          access: widget.access,
          send: (wav) => _practise(dhikr.id, wav),
          player: player,
          feedbackAudio: widget.api.feedbackAudio,
          closed: (attempts[dhikr.id] ?? 0) >= practiceAttempts
              ? practiceRest
              : null,
        )
      else
        PracticeWords(text: dhikr.text),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        if (dhikr.audio)
          ListenButton(
            player: player,
            id: 'dhikr:${dhikr.id}',
            fetch: () => widget.api.dhikrAudio(dhikr.id),
          ),
        if (canPractise)
          TextButton.icon(
            onPressed: () =>
                setState(() => practising = open ? null : dhikr.id),
            icon: Icon(open ? Icons.close_rounded : Icons.mic_none_rounded),
            label: Text(open ? 'Close practice' : 'Practise'),
          ),
      ]),
    ]);
  }
}

/// A pushed page of the speech preview: its own app bar, the adult-operator
/// notice and a scrolling column, like the prayer practice page.
class VoicePageFrame extends StatelessWidget {
  const VoicePageFrame(
      {super.key, required this.title, required this.children, this.actions});

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(title), backgroundColor: ivory, actions: actions),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const DevelopmentBanner(),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );
}

/// A load that did not work, and a way to try again.
class RetryPanel extends StatelessWidget {
  const RetryPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          VoiceNote(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      );
}
