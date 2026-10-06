import 'posture.dart';

/// Steadies the classifier: a posture counts as seen only when it is the
/// confident top choice in most of the last few frames. A child moving
/// between postures, a frame the model is unsure of, or a frame with nobody in
/// it reads as nothing seen rather than as a wrong posture.
class PostureSmoother {
  PostureSmoother({this.window = 5, this.needed = 3, this.minConfidence = 0.6})
      : assert(needed <= window);

  final int window;
  final int needed;
  final double minConfidence;

  final _recent = <Posture?>[];

  /// The steady posture after [reading], or null when there is none.
  Posture? add(PostureReading reading) {
    _recent.add(reading.confidence >= minConfidence ? reading.top : null);
    if (_recent.length > window) _recent.removeAt(0);
    for (final posture in Posture.values) {
      if (_recent.where((seen) => seen == posture).length >= needed) {
        return posture;
      }
    }
    return null;
  }

  void reset() => _recent.clear();
}
