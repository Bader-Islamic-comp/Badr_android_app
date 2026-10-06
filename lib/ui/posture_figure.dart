import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../posture/figure_pose.dart';
import '../theme.dart';

export '../posture/figure_pose.dart';

/// A line drawing of a child in one prayer posture on a prayer mat, seen from
/// the side.
///
/// The figure has no face: it stands for any child, not a particular one. It
/// shows the posture only. Where the schools of law differ, such as exactly
/// where the hands rest or how the feet sit, it keeps to the plain shape and
/// does not follow one school.
///
/// It is drawn in code rather than shipped as images, so it stays sharp at any
/// size and carries the app's own ink. The drawing keeps its proportions and is
/// centred in whatever box it is given.
class PostureFigure extends StatelessWidget {
  const PostureFigure({super.key, required this.pose, this.semanticsLabel});

  final FigurePose pose;

  /// Read by screen readers instead of "Drawing of" and the posture.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        image: true,
        label: semanticsLabel ?? 'Drawing of ${pose.description}',
        excludeSemantics: true,
        child: AspectRatio(
          aspectRatio: _FigurePainter.view.width / _FigurePainter.view.height,
          child: CustomPaint(painter: _FigurePainter(pose)),
        ),
      );
}

/// Paints one pose, scaled to fit the canvas.
///
/// The poses are drawn on a square of 100 units, all at the same scale and on
/// the same mat, so the child keeps the same size from one step to the next.
/// Everything is drawn back to front in white with an ink outline, so a part in
/// front hides the lines of the parts behind it, the way a hand drawing would.
class _FigurePainter extends CustomPainter {
  const _FigurePainter(this.pose);

  final FigurePose pose;

  /// The part of the square that is shown: from the top of the standing cap
  /// to the edges of the mat. The empty sky above is cropped away, which
  /// leaves the lower poses larger in a short box.
  static const view = Rect.fromLTRB(2, 10, 98, 95);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / view.width, size.height / view.height);
    canvas
      ..save()
      ..translate((size.width - view.width * scale) / 2,
          (size.height - view.height * scale) / 2)
      ..scale(scale)
      ..translate(-view.left, -view.top);
    final pen = _Pen(canvas);
    pen.shape(_mat);
    switch (pose) {
      case FigurePose.qiyam:
        _standing(pen, folded: true);
      case FigurePose.itidal:
        _standing(pen, folded: false);
      case FigurePose.ruku:
        _bowing(pen);
      case FigurePose.sujud:
        _prostrating(pen);
      case FigurePose.julus:
        _sitting(pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FigurePainter oldDelegate) => oldDelegate.pose != pose;
}

/// The prayer mat, a flat four-sided shape seen a little from above. The
/// figure is drawn over it, so the mat needs no line for the floor.
final _mat = Path()
  ..moveTo(17, 84)
  ..lineTo(85, 84)
  ..lineTo(95, 92.5)
  ..lineTo(5, 92.5)
  ..close();

/// Where the feet, knees, toes, palms and forehead meet the mat.
const _ground = 89.0;

/// Widths in units. A hand is narrower than its sleeve so that the cuff shows.
const _neck = 4.6;
const _sleeve = 5.4;
const _hand = 3.4;

/// Standing, before the bow with the hands folded at the waist and after it
/// with the arms at the sides. The folded hands are one plain shape: which
/// hand lies over which, and exactly how high, is where the schools differ.
void _standing(_Pen pen, {required bool folded}) {
  pen
    ..foot(const Offset(46.8, _ground))
    ..foot(const Offset(45, _ground))
    ..limb(const [Offset(51.6, 33), Offset(52, 27)], _neck)
    ..shape(Path()
      ..moveTo(48, 31.4)
      // Shoulder and back, down to the hem.
      ..cubicTo(45, 31.8, 43.2, 33.4, 42.9, 36.8)
      ..cubicTo(42.5, 46, 42.6, 62, 40.8, 84.2)
      ..quadraticBezierTo(50.7, 85.2, 60.6, 84.2)
      // Front and chest, back up to the collar.
      ..cubicTo(59, 66, 58.4, 54, 58.8, 42)
      ..cubicTo(59, 36.5, 57.8, 33, 55.6, 31.4)
      ..quadraticBezierTo(51.7, 32.6, 48, 31.4)
      ..close())
    ..head(const Offset(52.2, 24.3), 0);
  if (folded) {
    pen
      ..limb(const [Offset(48.8, 35.6), Offset(48.6, 49.6), Offset(55.4, 51.2)],
          _sleeve)
      // Both hands, one over the other, so a little wider than one.
      ..limb(const [Offset(56.2, 50.8), Offset(57.8, 53.6)], 3.8);
  } else {
    pen
      ..limb(const [Offset(48.8, 35.6), Offset(48.8, 49.4), Offset(50.6, 60.8)],
          _sleeve)
      ..limb(const [Offset(50.8, 61.2), Offset(51.6, 65)], _hand);
  }
}

/// Bowing: legs straight, back and head level, hands on the knees.
void _bowing(_Pen pen) {
  pen
    ..foot(const Offset(33.6, _ground))
    ..foot(const Offset(31.8, _ground))
    ..limb(const [Offset(59.5, 52.8), Offset(63, 52.6)], _neck)
    ..shape(Path()
      ..moveTo(61.6, 49.6)
      // The flat back and the round of the hips.
      ..cubicTo(56, 48.2, 46, 48.2, 37.6, 48.6)
      ..cubicTo(32, 48.8, 29.4, 52.6, 29.6, 58.6)
      // Down the back of the legs to the hem, and up their front.
      ..cubicTo(29.8, 68, 29.4, 77, 28.8, 84.2)
      ..quadraticBezierTo(37.4, 85.1, 46, 84.2)
      ..cubicTo(45.6, 77, 45.6, 69, 47.8, 63)
      // Under the chest to the collar.
      ..cubicTo(50.2, 58.6, 55.6, 57.2, 61.2, 56.2)
      ..quadraticBezierTo(60.6, 52.8, 61.6, 49.6)
      ..close())
    ..head(const Offset(66.8, 52.8), math.pi / 2)
    ..limb(const [Offset(55.6, 51.4), Offset(51.4, 61.2), Offset(47.6, 70.4)],
        _sleeve)
    ..limb(const [Offset(47.4, 70.8), Offset(46.4, 75)], _hand);
}

/// Prostrating: forehead, palms, knees and toes on the mat, hips raised. The
/// elbows are off the mat; how far they spread cannot be seen from the side.
void _prostrating(_Pen pen) {
  pen
    // The foot behind the robe's hem, upright on its toes.
    ..shape(Path()
      ..moveTo(33, 79.8)
      ..cubicTo(29, 80.2, 27, 81, 25.6, 80.6)
      ..cubicTo(24.6, 78.6, 23.4, 77.6, 22.2, 77.8)
      ..cubicTo(20.8, 78, 20.4, 79.4, 20.5, 81)
      ..lineTo(20.8, 86.6)
      ..cubicTo(20.9, 88.3, 21.9, _ground, 23.3, _ground)
      ..lineTo(27.2, _ground)
      ..cubicTo(28.4, _ground, 28.6, 87.6, 27.8, 86.8)
      ..cubicTo(28.6, 86.2, 30.2, 86.4, 33, 86.8)
      ..close())
    ..limb(const [Offset(62, 79.2), Offset(66, 81.2)], _neck)
    ..shape(Path()
      ..moveTo(63.6, 76)
      // The back rising to the hips, then down over the legs to the hem.
      ..cubicTo(56, 71.2, 45.6, 63.6, 38.4, 62.6)
      ..cubicTo(33.4, 62, 31.2, 65.8, 31.4, 70.4)
      ..cubicTo(31.6, 74.6, 31, 77.4, 30.4, 79.6)
      ..lineTo(31, 88.6)
      // Along the mat to the knee, and under the chest to the collar.
      ..lineTo(44.6, 88.8)
      ..cubicTo(47, 88.8, 48.6, 86, 49.8, 83.6)
      ..cubicTo(52.4, 81.8, 57, 81.4, 62.6, 82.6)
      ..quadraticBezierTo(62.6, 79.2, 63.6, 76)
      ..close())
    // Turned a little past a quarter, so the forehead and nose are lowest.
    ..head(const Offset(70.2, 82.4), 100 * math.pi / 180)
    ..limb(const [Offset(57, 76.6), Offset(53.6, 82.6), Offset(58.4, 87.2)],
        _sleeve)
    // Flat on the mat, so seen edge on.
    ..limb(const [Offset(59, 87.4), Offset(63.2, 87.6)], 2.8);
}

/// Sitting back on the folded legs, back upright, hands on the thighs. The
/// robe covers the feet: how they are placed is another thing the schools
/// differ on, and the drawing does not choose.
void _sitting(_Pen pen) {
  pen
    ..limb(const [Offset(46.2, 51), Offset(46.6, 45)], _neck)
    ..shape(Path()
      ..moveTo(42.6, 49.4)
      // Shoulder and back, round the seat to the mat.
      ..cubicTo(40.2, 49.8, 38.8, 51.6, 38.6, 55)
      ..cubicTo(38.2, 63, 38.4, 70, 37.6, 76)
      ..cubicTo(34.6, 79.5, 34.8, 88.8, 39.6, 88.8)
      // Along the mat, round the knee and back along the thigh.
      ..lineTo(60.4, 88.8)
      ..cubicTo(65.6, 88.8, 66.2, 80.4, 61.2, 79.6)
      ..cubicTo(57, 79, 53, 78.6, 51.4, 77.6)
      // Up the front to the collar.
      ..cubicTo(52.6, 70, 53.6, 60, 53, 55)
      ..cubicTo(52.6, 51.4, 51.4, 49.8, 49.8, 49.4)
      ..quadraticBezierTo(46.2, 50.6, 42.6, 49.4)
      ..close())
    // Where the thigh lies on the shin.
    ..line(Path()
      ..moveTo(59.5, 84)
      ..quadraticBezierTo(50, 84.4, 41.5, 83.2))
    ..head(const Offset(47, 42.2), 0)
    ..limb(const [Offset(45.4, 53.6), Offset(45.2, 66.6), Offset(53.4, 75.2)],
        _sleeve)
    // Resting on the thigh, so a little flatter than a hanging hand.
    ..limb(const [Offset(54, 76.4), Offset(59, 77.4)], 3);
}

/// Draws in the figure's one line weight: white shapes with an ink outline.
class _Pen {
  _Pen(this.canvas);

  final Canvas canvas;

  /// The outline's width in units, so it grows and shrinks with the drawing.
  static const weight = 0.9;

  static const _headRadius = 6.5;

  static final _fill = Paint()..color = Colors.white;
  static final _ink = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = weight
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// A closed shape, filled so that it covers what was drawn before it.
  void shape(Path path) {
    canvas
      ..drawPath(path, _fill)
      ..drawPath(path, _ink);
  }

  /// A line inside a shape, such as a fold.
  void line(Path path) => canvas.drawPath(path, _ink);

  /// A rounded tube through [points], [width] units across: a sleeve, a hand
  /// or the neck. It is a wide ink stroke under a narrower white one, which
  /// leaves an outline of the usual weight along both sides and round ends.
  void limb(List<Offset> points, double width) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas
      ..drawPath(path, Paint.from(_ink)..strokeWidth = width + weight)
      ..drawPath(
          path,
          Paint.from(_ink)
            ..color = Colors.white
            ..strokeWidth = width - weight);
  }

  /// A foot seen from the side, toes forward, its heel at [heel] on the mat.
  void foot(Offset heel) {
    final x = heel.dx, y = heel.dy;
    shape(Path()
      ..moveTo(x + 1.4, y - 6.5)
      ..cubicTo(x + 1.2, y - 3.6, x - 0.8, y - 1.6, x + 0.8, y)
      ..lineTo(x + 9.6, y)
      ..cubicTo(x + 11.4, y, x + 11.6, y - 2.4, x + 9.8, y - 2.9)
      ..cubicTo(x + 8, y - 3.4, x + 6.6, y - 4.4, x + 5.8, y - 6.5)
      ..close());
  }

  /// A plain round head in a small round cap, with no face. [turn] tilts it
  /// from upright, clockwise in radians: a quarter turn points the crown
  /// forward, as in the bow.
  void head(Offset centre, double turn) {
    const r = _headRadius;
    // The cap's lower edge, measured from the centre towards the crown, and
    // how far the cap stands off the head so that it reads as a cap.
    const band = 0.3 * r;
    const lift = 1.9;
    final half = math.sqrt(r * r - band * band) + 0.5;
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(turn);
    shape(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    shape(Path()
      ..moveTo(-half, -band)
      ..arcTo(Rect.fromLTRB(-half, -r - lift, half, r + lift - 2 * band),
          math.pi, math.pi, false)
      ..close());
    canvas.restore();
  }
}
