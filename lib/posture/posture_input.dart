import 'dart:typed_data';

/// One Android camera frame in YUV_420_888, as the camera plugin streams it:
/// a full-resolution Y plane and two half-resolution chroma planes.
///
/// [rotation] is how far the frame must turn clockwise to stand upright (0,
/// 90, 180 or 270): camera sensors are mounted sideways, so a portrait phone
/// usually streams frames that need a quarter turn.
class YuvFrame {
  const YuvFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.rotation,
  });

  final int width;
  final int height;
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int rotation;
}

/// The classifier's input: 224×224 RGB floats in 0–255, the whole frame
/// upright and letterboxed on gray 114, which is how the model was trained
/// (`ml/prayer_posture/train.py`). Nothing here is kept or sent: the input
/// exists for one inference.
class PostureInput {
  PostureInput._();

  static const side = 224;
  static const gray = 114.0;

  /// From a camera frame. Pixels are sampled nearest-neighbour and converted
  /// with the full-range BT.601 matrix Android cameras use.
  static Float32List fromYuv(YuvFrame frame) {
    final out = Float32List(side * side * 3)
      ..fillRange(0, side * side * 3, gray);
    _letterbox(frame.width, frame.height, frame.rotation, out, (x, y, at) {
      final luma = frame.y[y * frame.yRowStride + x].toDouble();
      final chroma =
          (y >> 1) * frame.uvRowStride + (x >> 1) * frame.uvPixelStride;
      final u = frame.u[chroma] - 128.0;
      final v = frame.v[chroma] - 128.0;
      out[at] = _byte(luma + 1.402 * v);
      out[at + 1] = _byte(luma - 0.344136 * u - 0.714136 * v);
      out[at + 2] = _byte(luma + 1.772 * u);
    });
    return out;
  }

  /// From an upright RGBA image, such as a decoded still.
  static Float32List fromRgba(Uint8List rgba, int width, int height) {
    final out = Float32List(side * side * 3)
      ..fillRange(0, side * side * 3, gray);
    _letterbox(width, height, 0, out, (x, y, at) {
      final i = (y * width + x) * 4;
      out[at] = rgba[i].toDouble();
      out[at + 1] = rgba[i + 1].toDouble();
      out[at + 2] = rgba[i + 2].toDouble();
    });
    return out;
  }

  static double _byte(double value) =>
      value < 0 ? 0 : (value > 255 ? 255 : value);

  /// Calls [pixel] with the source pixel behind every output pixel inside the
  /// letterbox, and the output index of its red value.
  static void _letterbox(int width, int height, int rotation, Float32List out,
      void Function(int x, int y, int at) pixel) {
    final quarter = rotation == 90 || rotation == 270;
    final uprightWidth = quarter ? height : width;
    final uprightHeight = quarter ? width : height;
    final longest = uprightWidth > uprightHeight ? uprightWidth : uprightHeight;
    final scale = side / longest;
    final drawnWidth = (uprightWidth * scale).round();
    final drawnHeight = (uprightHeight * scale).round();
    final left = (side - drawnWidth) ~/ 2;
    final top = (side - drawnHeight) ~/ 2;
    for (var row = 0; row < drawnHeight; row++) {
      final v = ((row + 0.5) / scale).floor().clamp(0, uprightHeight - 1);
      for (var column = 0; column < drawnWidth; column++) {
        final u = ((column + 0.5) / scale).floor().clamp(0, uprightWidth - 1);
        // Upright (u, v) back to the stored frame, undoing a clockwise turn.
        final (x, y) = switch (rotation) {
          90 => (v, height - 1 - u),
          180 => (width - 1 - u, height - 1 - v),
          270 => (width - 1 - v, u),
          _ => (u, v),
        };
        pixel(x, y, ((top + row) * side + left + column) * 3);
      }
    }
  }
}
