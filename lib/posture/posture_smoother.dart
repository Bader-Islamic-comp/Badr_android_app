import 'posture.dart';

/// Steadies the classifier: a posture counts as seen only when, in most of the
/// last few frames, it is the top choice and the model is at least as sure of
/// it as that posture's threshold. A child moving between postures, a frame
/// the model is unsure of, or a frame with nobody in it reads as nothing seen
/// rather than as a wrong posture.
class PostureSmoother {
  PostureSmoother({
    this.window = 5,
    this.needed = 3,
    Map<Posture, double> thresholds = defaultThresholds,
  })  : thresholds = Map.unmodifiable(thresholds),
        assert(needed <= window),
        assert(Posture.values.every(thresholds.containsKey));

  /// How sure the model must be of each posture for a frame to count, set on
  /// the validation split so that each posture is rarely called wrongly
  /// (`ml/prayer_posture/calibrate.py`). They match
  /// `ml/prayer_posture/results/thresholds.json`.
  static const defaultThresholds = {
    Posture.qiyam: 0.6,
    Posture.ruku: 0.6,
    Posture.sujud: 0.6,
    Posture.julus: 0.6,
  };

  final int window;
  final int needed;
  final Map<Posture, double> thresholds;

  final _recent = <Posture?>[];

  /// The steady posture after [reading], or null when there is none.
  Posture? add(PostureReading reading) {
    final top = reading.top;
    final counts = top != null && reading.confidence >= thresholds[top]!;
    _recent.add(counts ? top : null);
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
