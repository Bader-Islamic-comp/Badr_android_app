/// The four prayer postures the on-device classifier tells apart, in the
/// order of its output (`assets/models/prayer_posture_labels.txt`). Its fifth
/// output is "none": a picture with nobody in it.
///
/// The helper names a posture; it never judges a prayer. See
/// `doc/prayer-movement-helper.md`.
enum Posture {
  qiyam('Standing', 'القيام'),
  ruku('Bowing', 'الركوع'),
  sujud('Prostrating', 'السجود'),
  julus('Sitting', 'الجلوس');

  const Posture(this.english, this.arabic);

  final String english;
  final String arabic;
}

/// One classification of one camera frame: a probability for each posture,
/// then one for nobody being there.
class PostureReading {
  PostureReading(List<double> probabilities)
      : probabilities = List.unmodifiable(probabilities) {
    if (probabilities.length != outputs) {
      throw ArgumentError.value(probabilities.length, 'probabilities',
          'one per posture and one for nobody ($outputs)');
    }
  }

  /// The model's outputs: the postures and "none".
  static final outputs = Posture.values.length + 1;

  final List<double> probabilities;

  int get _best {
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    return best;
  }

  /// The most likely posture, or null when nobody being there is the most
  /// likely.
  Posture? get top =>
      _best < Posture.values.length ? Posture.values[_best] : null;

  double get confidence => probabilities[_best];

  @override
  String toString() =>
      'PostureReading(${top?.name ?? 'none'} ${(confidence * 100).round()}%)';
}
