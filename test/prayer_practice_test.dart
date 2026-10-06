import 'dart:async';

import 'package:companion_mobile/main.dart';
import 'package:companion_mobile/posture/movement_practice.dart';
import 'package:companion_mobile/posture/posture.dart';
import 'package:companion_mobile/posture/posture_source.dart';
import 'package:companion_mobile/theme.dart';
import 'package:companion_mobile/ui/posture_figure.dart';
import 'package:companion_mobile/ui/prayer_practice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The prayer-movement practice and its camera helper, with a scripted
/// source in place of the camera and the model.

class _ScriptedSource implements PostureSource {
  _ScriptedSource({this.failure});

  final PostureSourceException? failure;
  final _readings = StreamController<PostureReading>.broadcast();
  int starts = 0;
  int stops = 0;
  bool closed = false;
  bool running = false;

  /// A confident reading of [posture], or of nobody when it is null.
  void show(Posture? posture) => _readings.add(PostureReading([
        for (final p in Posture.values) p == posture ? 0.92 : 0.02,
        posture == null ? 0.92 : 0.02,
      ]));

  @override
  Stream<PostureReading> get readings => _readings.stream;

  @override
  Widget? preview() => running
      ? const ColoredBox(color: teal, child: SizedBox(height: 120))
      : null;

  @override
  Future<void> start() async {
    starts++;
    if (failure != null) throw failure!;
    running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Future<void> close() async {
    await stop();
    closed = true;
    await _readings.close();
  }
}

Future<void> _open(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: companionTheme(), home: page));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without the helper, the child practises by tapping Next',
      (tester) async {
    await _open(tester, const PrayerPracticePage(helperAllowed: false));
    expect(find.text('Movement 1 of 7'.toUpperCase()), findsOneWidget);
    expect(find.text('Stand'), findsOneWidget);
    expect(find.text('القيام'), findsOneWidget);
    expect(find.textContaining('A parent can turn on the movement helper'),
        findsOneWidget);
    expect(find.text('Turn on the camera'), findsNothing);
    expect(find.textContaining('cannot tell whether a prayer is correct'),
        findsOneWidget);

    for (final step in practiceSteps) {
      expect(find.text(step.title), findsOneWidget);
      expect(tester.widget<PostureFigure>(find.byType(PostureFigure)).pose,
          step.figure);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('All 7 movements practised'), findsOneWidget);
    expect(find.byType(PostureFigure), findsNothing);
    expect(find.textContaining('helper saw'), findsNothing);
    await tester.tap(find.text('Practise again'));
    await tester.pumpAndSettle();
    expect(find.text('Stand'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each step shows its drawing, standing up again its own',
      (tester) async {
    expect([
      for (final step in practiceSteps) step.figure
    ], [
      FigurePose.qiyam,
      FigurePose.ruku,
      FigurePose.itidal,
      FigurePose.sujud,
      FigurePose.julus,
      FigurePose.sujud,
      FigurePose.julus,
    ]);
    final handle = tester.ensureSemantics();
    await _open(tester, const PrayerPracticePage(helperAllowed: false));
    expect(find.bySemanticsLabel('Drawing of standing'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Drawing of bowing'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the practice fits a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
        theme: companionTheme(),
        home: const PrayerPracticePage(helperAllowed: false)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final step in practiceSteps) {
      // The card is taller than the screen here, so its top may have
      // scrolled away by now.
      expect(find.text(step.title, skipOffstage: false), findsOneWidget);
      final figure = find.byType(PostureFigure, skipOffstage: false);
      await tester.ensureVisible(figure);
      await tester.pumpAndSettle();
      expect(tester.getSize(figure).height, 180);
      expect(tester.getSize(figure).width, lessThanOrEqualTo(320));
      await tester.ensureVisible(find.text('Next', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('All 7 movements practised'), findsOneWidget);
  });

  testWidgets('the camera starts only when asked, and the helper moves on',
      (tester) async {
    final source = _ScriptedSource();
    var now = DateTime(2026, 10, 6, 9);
    await _open(
        tester,
        PrayerPracticePage(
            helperAllowed: true, source: () => source, clock: () => now));
    expect(source.starts, 0, reason: 'opening the page does not start it');
    expect(find.text('Camera on'), findsNothing);

    await tester.tap(find.text('Turn on the camera'));
    await tester.pumpAndSettle();
    expect(source.starts, 1);
    expect(find.text('Camera on'), findsOneWidget);
    expect(find.text('The helper is watching…'), findsOneWidget);

    // An empty view moves nothing on.
    for (var i = 0; i < 5; i++) {
      source.show(null);
      await tester.pump();
    }
    now = now.add(const Duration(seconds: 5));
    source.show(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('The helper is watching…'), findsOneWidget);
    expect(find.text('Stand'), findsOneWidget);

    // Sitting is shown, not counted.
    for (var i = 0; i < 3; i++) {
      source.show(Posture.julus);
      await tester.pump();
    }
    // A reading that lands during a frame shows on the next one.
    await tester.pump();
    expect(find.text('The helper sees: Sitting · الجلوس'), findsOneWidget);
    expect(find.text('Stand'), findsOneWidget);

    // Standing, held, completes the first step.
    for (var i = 0; i < 4; i++) {
      source.show(Posture.qiyam);
      await tester.pump();
    }
    now = now.add(const Duration(seconds: 2));
    source.show(Posture.qiyam);
    await tester.pumpAndSettle();
    expect(find.text('Bow'), findsOneWidget);
    expect(find.text('The helper saw your last movement. Well done!'),
        findsOneWidget);

    await tester.tap(find.text('Turn off the camera'));
    await tester.pumpAndSettle();
    expect(source.stops, 1);
    expect(find.text('Camera on'), findsNothing);
    expect(find.text('Turn on the camera'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the camera stops when the app leaves the screen or the page '
      'closes', (tester) async {
    final source = _ScriptedSource();
    await _open(
        tester, PrayerPracticePage(helperAllowed: true, source: () => source));
    await tester.tap(find.text('Turn on the camera'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(source.stops, 1);
    // No frames are drawn while the app is away; the page shows the camera
    // off when it comes back, and does not restart it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Camera on'), findsNothing);
    expect(source.starts, 1);

    await tester.tap(find.text('Turn on the camera'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(source.closed, isTrue);
  });

  testWidgets('a refused camera leaves the practice working', (tester) async {
    final source = _ScriptedSource(
        failure: const PostureSourceException(
            'Camera permission was not given. Practice still works: tap Next '
            'after each movement.'));
    await _open(
        tester, PrayerPracticePage(helperAllowed: true, source: () => source));
    await tester.tap(find.text('Turn on the camera'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Camera permission was not given'), findsOneWidget);
    expect(find.text('Camera on'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Bow'), findsOneWidget);
  });

  testWidgets('a parent turns the helper on from the parent area',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CompanionApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practise the movements'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on the camera'), findsNothing,
        reason: 'the helper is off by default');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Parent area'));
    await tester.pumpAndSettle();
    final helper =
        find.widgetWithText(SwitchListTile, 'Movement helper (camera)');
    expect(tester.widget<SwitchListTile>(helper).value, isFalse);
    await tester.ensureVisible(helper);
    await tester.tap(helper);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(helper).value, isTrue);
    await tester.tap(find.text('Back to preview'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practise the movements'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on the camera'), findsOneWidget);
    expect(find.text('Camera on'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
