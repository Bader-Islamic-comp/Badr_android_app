import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/demo_api.dart';
import '../domain/speech_models.dart';
import '../speech/speech_player.dart';
import '../speech/voice_kit.dart';
import '../theme.dart';
import 'adhkar_page.dart';
import 'text_direction.dart';
import 'voice_widgets.dart';
import 'widgets.dart';

/// The duas of the day. Each has a slot for a recorded human voice, which
/// stays empty until a reviewed recording exists: no dua is ever spoken by a
/// computer voice. Some can be practised part by part.
class DuasPage extends StatefulWidget {
  const DuasPage({super.key, required this.api, required this.access});

  final DemoApi api;
  final VoiceAccess access;

  static const voiceComing = 'A recorded voice is coming';
  static const fromQuran =
      'The words come from the Quran. Read them with a grown-up.';

  @override
  State<DuasPage> createState() => _DuasPageState();
}

class _DuasPageState extends State<DuasPage> {
  late final player = SpeechPlayer(widget.access.kit.playback);
  DuaList? list;
  String? problem;
  bool loading = true;

  /// The part being practised, as `dua#index`. One at a time.
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
      final loaded = await widget.api.duas();
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

  Future<PracticeResult> _practise(
      Dua dua, DuaSegment segment, Uint8List wav) async {
    final slot = '${dua.id}#${segment.index}';
    final attempt = (attempts[slot] ?? 0) + 1;
    final result = await widget.api.practise(
        itemId: dua.id,
        segment: segment.index,
        attempt: attempt,
        wav: wav,
        key: DemoApi.newKey());
    if (mounted) setState(() => attempts[slot] = attempt);
    return result;
  }

  @override
  Widget build(BuildContext context) => VoicePageFrame(
        title: 'Duas · أدعية',
        children: [
          const Text(
              'Duas for the day. A recorded voice is added to each one once a '
              'person has read it and it has been checked. Some duas can be '
              'practised part by part.',
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
            for (final dua in list!.items) ...[
              Panel(child: _card(context, dua)),
              const SizedBox(height: 16),
            ],
          const Text(practiceOnly, style: TextStyle(color: muted)),
        ],
      );

  Widget _card(BuildContext context, Dua dua) {
    final canPractise = widget.access.recitation && dua.segments.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      directionalText(dua.title, style: Theme.of(context).textTheme.titleLarge),
      if (dua.childNote != null) ...[
        const SizedBox(height: 6),
        directionalText(dua.childNote!, style: const TextStyle(color: muted)),
      ],
      if (dua.repeat != null && dua.repeat! > 1) ...[
        const SizedBox(height: 6),
        Text('Said ${dua.repeat} times',
            style: const TextStyle(fontSize: 13, color: muted)),
      ],
      if (dua.kind.startsWith('quran')) ...[
        const SizedBox(height: 6),
        const Text(DuasPage.fromQuran,
            style: TextStyle(fontSize: 13, color: muted)),
      ],
      const SizedBox(height: 8),
      // The recorded voice's slot: a person's reading, never a computer's.
      if (dua.recorded)
        ListenButton(
          player: player,
          id: 'dua:${dua.id}',
          fetch: () => widget.api.duaAudio(dua.id),
          label: 'Listen to the recorded voice',
        )
      else
        const Row(children: [
          Icon(Icons.record_voice_over_outlined, color: muted, size: 20),
          SizedBox(width: 8),
          Flexible(
              child:
                  Text(DuasPage.voiceComing, style: TextStyle(color: muted))),
        ]),
      if (canPractise)
        for (final segment in dua.segments) _segment(dua, segment),
    ]);
  }

  Widget _segment(Dua dua, DuaSegment segment) {
    final slot = '${dua.id}#${segment.index}';
    final open = practising == slot;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: hairline))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Part ${segment.index + 1} of ${dua.segments.length}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
        const SizedBox(height: 6),
        if (open)
          PracticePanel(
            key: ValueKey('practice-$slot'),
            text: segment.text,
            access: widget.access,
            send: (wav) => _practise(dua, segment, wav),
            player: player,
            feedbackAudio: widget.api.feedbackAudio,
            closed:
                (attempts[slot] ?? 0) >= practiceAttempts ? practiceRest : null,
          )
        else
          PracticeWords(text: segment.text),
        TextButton.icon(
          onPressed: () => setState(() => practising = open ? null : slot),
          icon: Icon(open ? Icons.close_rounded : Icons.mic_none_rounded),
          label: Text(open ? 'Close practice' : 'Practise this part'),
        ),
      ]),
    );
  }
}
