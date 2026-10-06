import 'dart:async';

import 'package:flutter/material.dart';

import '../posture/camera_posture_source.dart'
    if (dart.library.js_interop) '../posture/web_posture_source.dart';
import '../posture/movement_practice.dart';
import '../posture/posture.dart';
import '../posture/posture_smoother.dart';
import '../posture/posture_source.dart';
import '../theme.dart';
import 'posture_figure.dart';
import 'widgets.dart';

/// Practising the prayer movements, one step at a time.
///
/// The practice works without the camera: the child taps Next after each
/// movement. With the movement helper on (a parent turns it on in the parent
/// area) the child can also turn on the front camera, and the on-device model
/// moves to the next step when it sees the movement. The camera is off until
/// the child turns it on here, stops when the page closes or the app leaves the
/// screen, and nothing it sees is kept or sent.
class PrayerPracticePage extends StatefulWidget {
  const PrayerPracticePage({
    super.key,
    required this.helperAllowed,
    this.source,
    this.clock,
  });

  /// Whether a parent has turned the movement helper on.
  final bool helperAllowed;

  /// Makes the posture source. Tests pass their own; the default is the
  /// camera and the bundled model.
  final PostureSource Function()? source;

  /// The time for a reading. Tests pass their own.
  final DateTime Function()? clock;

  @override
  State<PrayerPracticePage> createState() => _PrayerPracticePageState();
}

class _PrayerPracticePageState extends State<PrayerPracticePage>
    with WidgetsBindingObserver {
  final practice = MovementPractice();
  final smoother = PostureSmoother();
  PostureSource? source;
  StreamSubscription<PostureReading>? readings;
  bool cameraOn = false;
  bool starting = false;
  String? problem;

  bool get _helperAvailable => postureHelperBuilt && widget.helperAllowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    practice.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera never runs behind another app or a locked screen.
    if (state != AppLifecycleState.resumed && cameraOn) {
      unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    practice.removeListener(_changed);
    practice.dispose();
    unawaited(readings?.cancel());
    unawaited(source?.close());
    super.dispose();
  }

  Future<void> _startCamera() async {
    setState(() {
      starting = true;
      problem = null;
    });
    final helper = source ??= (widget.source ?? CameraPostureSource.new)();
    try {
      await helper.start();
      if (!mounted) return;
      smoother.reset();
      readings = helper.readings.listen((reading) => practice.observe(
          smoother.add(reading), (widget.clock ?? DateTime.now)()));
      setState(() => cameraOn = true);
    } on PostureSourceException catch (error) {
      if (mounted) setState(() => problem = error.message);
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> _stopCamera() async {
    // Readings stop at once; the cancel itself needs no waiting for.
    unawaited(readings?.cancel());
    readings = null;
    await source?.stop();
    smoother.reset();
    practice.observe(null, (widget.clock ?? DateTime.now)());
    if (mounted) setState(() => cameraOn = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Prayer movements'),
            backgroundColor: ivory,
            actions: [if (cameraOn) const _CameraOnBadge()]),
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
                  Panel(child: _stepPanel(context)),
                  if (postureHelperBuilt) ...[
                    const SizedBox(height: 16),
                    Panel(child: _helperPanel(context)),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                      'The helper checks the movement only. It cannot tell '
                      'whether a prayer is correct or accepted. Ask a parent or '
                      'teacher what to say in each movement.',
                      style: TextStyle(color: muted)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _stepPanel(BuildContext context) {
    final step = practice.step;
    final total = practiceSteps.length;
    if (step == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle_outline, size: 36, color: teal),
        const SizedBox(height: 12),
        Text('All $total movements practised',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Well done for practising. You can go through them again '
            'whenever you like.'),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: practice.restart, child: const Text('Practise again')),
      ]);
    }
    final seen = practice.seen;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionLabel('Movement ${practice.index + 1} of $total'),
      const SizedBox(height: 12),
      LinearProgressIndicator(
          value: (practice.index + 1) / total,
          semanticsLabel:
              'Practice progress, movement ${practice.index + 1} of $total'),
      const SizedBox(height: 20),
      Text(step.title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(step.arabic,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontSize: 20, color: ink)),
      const SizedBox(height: 16),
      _FigurePlate(step.figure),
      if (practice.index > 0 && practice.lastByHelper) ...[
        const SizedBox(height: 12),
        const Text('The helper saw your last movement. Well done!',
            style: TextStyle(color: teal, fontWeight: FontWeight.w600)),
      ],
      if (cameraOn) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
              seen == null
                  ? 'The helper is watching…'
                  : 'The helper sees: ${seen.english} · ${seen.arabic}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        MergeSemantics(
          child: Semantics(
            hint: 'Moves to the next movement',
            child: FilledButton(
                onPressed: practice.next, child: const Text('Next')),
          ),
        ),
        TextButton(
            onPressed: practice.index == 0 ? null : practice.restart,
            child: const Text('Start again')),
      ]),
    ]);
  }

  Widget _helperPanel(BuildContext context) {
    if (!_helperAvailable) {
      return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.videocam_off_outlined, color: muted),
        SizedBox(width: 12),
        Expanded(
            child: Text('A parent can turn on the movement helper in the '
                'parent area. It uses the camera to recognise standing, '
                'bowing, prostrating and sitting.')),
      ]);
    }
    final preview = cameraOn ? source?.preview() : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Movement helper', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Put the phone where it can see all of you. The picture stays '
          'on this phone: nothing is recorded, saved or sent.'),
      if (preview != null) ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Center(child: preview)),
        ),
      ],
      if (problem != null) ...[
        const SizedBox(height: 12),
        Semantics(
            liveRegion: true,
            child: Text(problem!,
                style: const TextStyle(
                    color: orange, fontWeight: FontWeight.w600))),
      ],
      const SizedBox(height: 16),
      cameraOn
          ? OutlinedButton.icon(
              onPressed: _stopCamera,
              icon: const Icon(Icons.videocam_off_outlined),
              label: const Text('Turn off the camera'))
          : FilledButton.tonalIcon(
              onPressed: starting ? null : _startCamera,
              icon: const Icon(Icons.videocam_outlined),
              label: Text(starting ? 'Starting…' : 'Turn on the camera')),
    ]);
  }
}

/// The drawing of the movement to make, on its own soft surface so the white
/// figure stands apart from the white card. Its height is fixed so the card
/// keeps its shape from one step to the next.
class _FigurePlate extends StatelessWidget {
  const _FigurePlate(this.pose);

  final FigurePose pose;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
            color: ivory, borderRadius: BorderRadius.circular(16)),
        child: PostureFigure(pose: pose),
      );
}

/// Always visible while the camera runs, so nobody has to guess.
class _CameraOnBadge extends StatelessWidget {
  const _CameraOnBadge();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Camera on',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: sand, borderRadius: BorderRadius.circular(999)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 10, color: orange),
            SizedBox(width: 6),
            Text('Camera on',
                style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          ]),
        ),
      );
}
