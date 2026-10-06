/// The drawings of the prayer movements, one for each posture the practice
/// steps through.
///
/// Rising from the bow has its own drawing although the helper counts it as
/// standing: the arms hang at the sides there, where the first standing shows
/// them folded.
enum FigurePose {
  qiyam('standing'),
  itidal('standing up after bowing'),
  ruku('bowing'),
  sujud('prostrating'),
  julus('sitting');

  const FigurePose(this.description);

  /// What the drawing shows, in words, for screen readers.
  final String description;
}
