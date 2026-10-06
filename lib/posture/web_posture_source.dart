import 'package:flutter/widgets.dart';

import 'posture.dart';
import 'posture_source.dart';

/// Browser preview fallback. The on-device TFLite model runs only on phones.
class CameraPostureSource implements PostureSource {
  @override
  Stream<PostureReading> get readings => const Stream<PostureReading>.empty();

  @override
  Widget? preview() => null;

  @override
  Future<void> start() async {
    throw const PostureSourceException(
        'The movement helper is available only on Android phones.');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}
}
