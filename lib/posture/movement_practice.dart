import 'package:flutter/foundation.dart';

import 'posture.dart';

/// One step of the practice: the posture to take and what it is called.
class PracticeStep {
  const PracticeStep(this.posture, this.title, this.arabic);

  final Posture posture;
  final String title;
  final String arabic;
}

/// Practising the movements of one rak'ah, in order. Movement names only: no
/// recitation, no rulings. The wording awaits the scholarly reviewer like the
/// rest of the religious content (`doc/prayer-movement-helper.md`).
const practiceSteps = [
  PracticeStep(Posture.qiyam, 'Stand', 'القيام'),
  PracticeStep(Posture.ruku, 'Bow', 'الركوع'),
  PracticeStep(Posture.qiyam, 'Stand up again', 'الرفع من الركوع'),
  PracticeStep(Posture.sujud, 'Prostrate', 'السجود'),
  PracticeStep(Posture.julus, 'Sit', 'الجلوس بين السجدتين'),
  PracticeStep(Posture.sujud, 'Prostrate again', 'السجدة الثانية'),
  PracticeStep(Posture.julus, 'Sit', 'الجلوس'),
];

/// Where the child is in the practice.
///
/// A step is done when the child says so ([next]) or, with the movement
/// helper on, when the helper has seen the step's posture steadily for
/// [hold]. Seeing another posture is never a failure: the page just says
/// what the helper sees. Nothing here grants a reward.
class MovementPractice extends ChangeNotifier {
  MovementPractice({this.hold = const Duration(milliseconds: 1200)});

  final Duration hold;

  int _index = 0;
  Posture? _seen;
  DateTime? _since;
  bool _byHelper = false;

  int get index => _index;
  bool get finished => _index >= practiceSteps.length;
  PracticeStep? get step => finished ? null : practiceSteps[_index];

  /// The posture the helper sees steadily now, if any.
  Posture? get seen => _seen;

  /// Whether the last step was completed because the helper saw it.
  bool get lastByHelper => _byHelper;

  /// A steady reading from the helper (or null for none) at [now].
  void observe(Posture? posture, DateTime now) {
    if (posture != _seen) {
      _seen = posture;
      _since = posture == null ? null : now;
      notifyListeners();
    }
    final current = step;
    if (current == null || posture != current.posture) return;
    if (now.difference(_since!) >= hold) _advance(byHelper: true);
  }

  /// The child moves on themselves: the practice never depends on the camera.
  void next() => _advance(byHelper: false);

  void restart() {
    _index = 0;
    _seen = null;
    _since = null;
    _byHelper = false;
    notifyListeners();
  }

  void _advance({required bool byHelper}) {
    if (finished) return;
    _index++;
    _byHelper = byHelper;
    // Every step starts from a fresh look, so a posture held before it never
    // counts towards it.
    _seen = null;
    _since = null;
    notifyListeners();
  }
}
