import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'posture.dart';
import 'posture_input.dart';
import 'posture_source.dart';

/// The front camera and the on-device posture model.
///
/// Frames are classified in memory, at most one every [interval], and then
/// dropped: no frame is written to storage, logged or sent anywhere, and the
/// camera records no audio. The model is loaded the first time the helper is
/// turned on, never at app start.
class CameraPostureSource implements PostureSource {
  CameraPostureSource({this.interval = const Duration(milliseconds: 300)});

  static const modelAsset = 'assets/models/prayer_posture.tflite';

  final Duration interval;

  CameraController? _camera;
  Interpreter? _interpreter;
  IsolateInterpreter? _model;
  final _readings = StreamController<PostureReading>.broadcast();
  bool _busy = false;
  bool _running = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Stream<PostureReading> get readings => _readings.stream;

  @override
  Widget? preview() {
    final camera = _camera;
    return camera != null && camera.value.isInitialized
        ? CameraPreview(camera)
        : null;
  }

  @override
  Future<void> start() async {
    if (_running) return;
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (error) {
      throw PostureSourceException(_explain(error));
    }
    if (cameras.isEmpty) {
      throw const PostureSourceException('This phone has no camera.');
    }
    // The front camera, so the child can see themselves practise.
    final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first);
    final camera = CameraController(description, ResolutionPreset.low,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    try {
      await camera.initialize();
      _interpreter ??= await Interpreter.fromAsset(modelAsset,
          options: InterpreterOptions()..threads = 2);
      _model ??=
          await IsolateInterpreter.create(address: _interpreter!.address);
      _camera = camera;
      _running = true;
      await camera.startImageStream(_frame);
    } on CameraException catch (error) {
      _running = false;
      _camera = null;
      await camera.dispose();
      throw PostureSourceException(_explain(error));
    }
  }

  void _frame(CameraImage image) {
    final camera = _camera;
    final now = DateTime.now();
    if (!_running ||
        _busy ||
        camera == null ||
        now.difference(_last) < interval) {
      return;
    }
    if (image.planes.length < 3) return;
    _busy = true;
    _last = now;
    final frame = YuvFrame(
      width: image.width,
      height: image.height,
      y: image.planes[0].bytes,
      u: image.planes[1].bytes,
      v: image.planes[2].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
      rotation: uprightRotation(
        sensorOrientation: camera.description.sensorOrientation,
        front: camera.description.lensDirection == CameraLensDirection.front,
        device: camera.value.deviceOrientation,
      ),
    );
    unawaited(_classify(frame));
  }

  Future<void> _classify(YuvFrame frame) async {
    try {
      final input = await Isolate.run(() => PostureInput.fromYuv(frame));
      final output = Float32List(PostureReading.outputs);
      await _model!.run(input.buffer.asUint8List(), output.buffer);
      if (_running && !_readings.isClosed) {
        _readings.add(PostureReading(output.toList()));
      }
    } on Object {
      // A frame that could not be read is skipped; the next one follows.
    } finally {
      _busy = false;
    }
  }

  /// How far a frame turns clockwise to stand upright, as Android computes
  /// it for a camera image: the sensor's mounting, with the device's own
  /// rotation added for the front camera and taken away for the back.
  static int uprightRotation({
    required int sensorOrientation,
    required bool front,
    required DeviceOrientation device,
  }) {
    final turned = switch (device) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return front
        ? (sensorOrientation + turned) % 360
        : (sensorOrientation - turned + 360) % 360;
  }

  static String _explain(CameraException error) => switch (error.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' ||
        'cameraPermission' =>
          'Camera permission was not given. Practice still works: tap Next '
              'after each movement.',
        _ => 'The camera could not start. Practice still works: tap Next '
            'after each movement.',
      };

  @override
  Future<void> stop() async {
    _running = false;
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    if (camera.value.isStreamingImages) await camera.stopImageStream();
    await camera.dispose();
  }

  @override
  Future<void> close() async {
    await stop();
    // An inference already running finishes before the model goes.
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _model?.close();
    _interpreter?.close();
    _model = null;
    _interpreter = null;
    await _readings.close();
  }
}
