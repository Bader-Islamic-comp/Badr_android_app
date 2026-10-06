import 'package:companion_mobile/ui/posture_figure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The drawings of the prayer movements. The goldens are the drawings
/// themselves: a change to a figure shows up as a changed picture to look at
/// before it reaches a child. The combined sheet is copied to
/// `design/prayer-postures.png` for the docs.

/// [child] on a white page [width] pixels wide and as tall as it needs.
Future<void> _paint(WidgetTester tester, Widget child,
    {required double width}) async {
  tester.view.physicalSize = Size(width, width);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: RepaintBoundary(
            child: ColoredBox(color: Colors.white, child: child)),
      ),
    ),
  ));
}

void main() {
  for (final pose in FigurePose.values) {
    testWidgets('the ${pose.name} drawing', (tester) async {
      await _paint(tester, PostureFigure(pose: pose), width: 400);
      await expectLater(find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/posture_${pose.name}.png'));
    });
  }

  testWidgets('the five drawings side by side', (tester) async {
    await _paint(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            for (final pose in FigurePose.values)
              Expanded(child: PostureFigure(pose: pose)),
          ]),
        ),
        width: 1600);
    await expectLater(find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/posture_figures.png'));
  });

  testWidgets('a drawing is one picture to a screen reader, never text',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: SizedBox(
              height: 180, child: PostureFigure(pose: FigurePose.ruku))),
    ));
    expect(tester.getSemantics(find.byType(PostureFigure)),
        isSemantics(label: 'Drawing of bowing', isImage: true));
    // Given only a height, the drawing takes its own proportions: a little
    // wider than tall, from the top of the cap to the ends of the mat.
    final size = tester.getSize(find.byType(PostureFigure));
    expect(size.height, 180);
    expect(size.width / size.height, closeTo(96 / 85, 0.01));

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: PostureFigure(
          pose: FigurePose.julus, semanticsLabel: 'Sitting between the two'),
    ));
    expect(tester.getSemantics(find.byType(PostureFigure)),
        isSemantics(label: 'Sitting between the two', isImage: true));
    handle.dispose();
  });
}
