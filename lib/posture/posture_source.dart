import 'package:flutter/widgets.dart';

import 'posture.dart';

/// Whether this build carries the movement helper at all. A build made with
/// `--dart-define=POSTURE_HELPER=false` has no camera practice and no parent
/// switch for it: the kill switch.
const postureHelperBuilt =
    bool.fromEnvironment('POSTURE_HELPER', defaultValue: true);

/// Where posture readings come from while the movement helper is on: the
/// camera and the on-device model on a phone, a script in tests.
abstract class PostureSource {
  /// Starts the camera and the model. Throws [PostureSourceException] when the
  /// camera cannot be used.
  Future<void> start();

  /// One reading for each classified frame, while started.
  Stream<PostureReading> get readings;

  /// The live picture, or null when the camera is off.
  Widget? preview();

  /// Stops the camera. The source can start again.
  Future<void> stop();

  /// Stops the camera and releases the model.
  Future<void> close();
}

class PostureSourceException implements Exception {
  const PostureSourceException(this.message);

  /// Written for the adult beside the child.
  final String message;

  @override
  String toString() => message;
}
