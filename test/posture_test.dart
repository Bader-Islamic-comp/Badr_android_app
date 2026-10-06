import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:companion_mobile/posture/camera_posture_source.dart';
import 'package:companion_mobile/posture/movement_practice.dart';
import 'package:companion_mobile/posture/posture.dart';
import 'package:companion_mobile/posture/posture_input.dart';
import 'package:companion_mobile/posture/posture_smoother.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The on-device posture helper's logic, without a camera or a model: the
/// model's input, the steadying of its readings and the practice steps.

const _side = PostureInput.side;

/// The red, green and blue at output pixel ([row], [column]).
List<double> _at(Float32List input, int row, int column) {
  final i = (row * _side + column) * 3;
  return [input[i], input[i + 1], input[i + 2]];
}

/// A [width]×[height] frame whose luma is [luma] row by row, with neutral
/// chroma unless [u] and [v] are given, and a Y row stride wider than the
/// frame, as camera buffers often are.
YuvFrame _frame(int width, int height, List<int> luma,
    {int rotation = 0, int u = 128, int v = 128}) {
  final stride = width + 2;
  final y = Uint8List(stride * height);
  for (var row = 0; row < height; row++) {
    for (var column = 0; column < width; column++) {
      y[row * stride + column] = luma[row * width + column];
    }
  }
  final chroma = ((width + 1) ~/ 2) * ((height + 1) ~/ 2);
  return YuvFrame(
    width: width,
    height: height,
    y: y,
    u: Uint8List(chroma)..fillRange(0, chroma, u),
    v: Uint8List(chroma)..fillRange(0, chroma, v),
    yRowStride: stride,
    uvRowStride: (width + 1) ~/ 2,
    uvPixelStride: 1,
    rotation: rotation,
  );
}

/// A reading sure enough of [posture] to pass any threshold unless
/// [confidence] says otherwise.
PostureReading _reading(Posture? posture, [double confidence = 0.995]) {
  final rest = (1 - confidence) / Posture.values.length;
  return PostureReading([
    for (final p in Posture.values) p == posture ? confidence : rest,
    posture == null ? confidence : rest,
  ]);
}

void main() {
  group('the model', () {
    test('its labels are the postures, in order', () {
      final labels = File('assets/models/prayer_posture_labels.txt')
          .readAsLinesSync()
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(labels, [for (final p in Posture.values) p.name, 'none']);
    });

    test('is bundled, small, and declared as an asset', () {
      final model = File('assets/models/prayer_posture.tflite');
      expect(model.existsSync(), isTrue);
      expect(model.lengthSync(), lessThan(3 * 1024 * 1024));
      // A TensorFlow Lite flatbuffer carries its identifier at byte 4.
      expect(
          String.fromCharCodes(model.readAsBytesSync().sublist(4, 8)), 'TFL3');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains(CameraPostureSource.modelAsset));
    });
  });

  group('PostureReading', () {
    test('names the most likely posture', () {
      final reading = PostureReading([0.1, 0.65, 0.15, 0.05, 0.05]);
      expect(reading.top, Posture.ruku);
      expect(reading.confidence, 0.65);
    });

    test('names no posture when nobody is the most likely', () {
      final reading = PostureReading([0.1, 0.1, 0.05, 0.05, 0.7]);
      expect(reading.top, isNull);
      expect(reading.confidence, 0.7);
    });

    test('needs one probability per posture and one for nobody', () {
      expect(() => PostureReading([0.5, 0.5]), throwsArgumentError);
      expect(
          () => PostureReading([0.25, 0.25, 0.25, 0.25]), throwsArgumentError);
    });
  });

  group('PostureInput', () {
    test('letterboxes a wide still on gray, centred', () {
      // Two pixels, dark then bright: each becomes a 112-pixel square.
      final rgba = Uint8List.fromList([10, 20, 30, 255, 200, 210, 220, 255]);
      final input = PostureInput.fromRgba(rgba, 2, 1);
      expect(input.length, _side * _side * 3);
      expect(_at(input, 0, 0), [114, 114, 114]);
      expect(_at(input, 55, 100), [114, 114, 114]);
      expect(_at(input, 56, 0), [10, 20, 30]);
      expect(_at(input, 167, 111), [10, 20, 30]);
      expect(_at(input, 56, 112), [200, 210, 220]);
      expect(_at(input, 168, 112), [114, 114, 114]);
    });

    test('reads a camera frame as it is stored when it needs no turn', () {
      final input = PostureInput.fromYuv(_frame(2, 1, [10, 200]));
      expect(_at(input, 0, 0), [114, 114, 114]);
      expect(_at(input, 56, 0), [10, 10, 10]);
      expect(_at(input, 56, 223), [200, 200, 200]);
    });

    test('turns a sideways frame upright', () {
      // Turned a quarter clockwise, the frame's left pixel is at the top.
      final clockwise =
          PostureInput.fromYuv(_frame(2, 1, [10, 200], rotation: 90));
      expect(_at(clockwise, 0, 56), [10, 10, 10]);
      expect(_at(clockwise, 223, 56), [200, 200, 200]);
      expect(_at(clockwise, 100, 0), [114, 114, 114]);
      // Three quarters, it is at the bottom.
      final anticlockwise =
          PostureInput.fromYuv(_frame(2, 1, [10, 200], rotation: 270));
      expect(_at(anticlockwise, 0, 56), [200, 200, 200]);
      expect(_at(anticlockwise, 223, 56), [10, 10, 10]);
      // Half a turn swaps left and right.
      final upsideDown =
          PostureInput.fromYuv(_frame(2, 1, [10, 200], rotation: 180));
      expect(_at(upsideDown, 56, 0), [200, 200, 200]);
      expect(_at(upsideDown, 56, 223), [10, 10, 10]);
    });

    test('converts colour with the full-range BT.601 matrix', () {
      final input =
          PostureInput.fromYuv(_frame(2, 2, [100, 100, 100, 100], v: 228));
      final rgb = _at(input, 100, 100);
      expect(rgb[0], closeTo(240.2, 0.01));
      expect(rgb[1], closeTo(28.59, 0.01));
      expect(rgb[2], closeTo(100, 0.01));
      final bright =
          PostureInput.fromYuv(_frame(2, 2, [250, 250, 250, 250], u: 255));
      expect(_at(bright, 100, 100)[2], 255, reason: 'clamped to a byte');
    });
  });

  group('uprightRotation', () {
    test('follows Android for the front and back cameras', () {
      int turn(int sensor, bool front, DeviceOrientation device) =>
          CameraPostureSource.uprightRotation(
              sensorOrientation: sensor, front: front, device: device);
      expect(turn(270, true, DeviceOrientation.portraitUp), 270);
      expect(turn(90, false, DeviceOrientation.portraitUp), 90);
      expect(turn(270, true, DeviceOrientation.landscapeLeft), 0);
      expect(turn(90, false, DeviceOrientation.landscapeLeft), 0);
      expect(turn(90, false, DeviceOrientation.landscapeRight), 180);
    });
  });

  group('PostureSmoother', () {
    test('needs a posture in most of the last frames', () {
      final smoother = PostureSmoother();
      expect(smoother.add(_reading(Posture.ruku)), isNull);
      expect(smoother.add(_reading(Posture.ruku)), isNull);
      expect(smoother.add(_reading(Posture.ruku)), Posture.ruku);
    });

    test('nobody in view is nothing seen', () {
      final smoother = PostureSmoother();
      for (var i = 0; i < 5; i++) {
        expect(smoother.add(_reading(null, 0.95)), isNull);
      }
    });

    test('does not count frames the model is unsure of', () {
      final smoother = PostureSmoother();
      for (var i = 0; i < 5; i++) {
        expect(smoother.add(_reading(Posture.sujud, 0.5)), isNull);
      }
    });

    test('holds each posture to its own threshold', () {
      final smoother = PostureSmoother(thresholds: {
        Posture.qiyam: 0.6,
        Posture.ruku: 0.6,
        Posture.sujud: 0.9,
        Posture.julus: 0.6,
      });
      for (var i = 0; i < 5; i++) {
        expect(smoother.add(_reading(Posture.sujud, 0.85)), isNull);
      }
      smoother.reset();
      for (var i = 0; i < 3; i++) {
        smoother.add(_reading(Posture.julus, 0.65));
      }
      expect(smoother.add(_reading(Posture.julus, 0.65)), Posture.julus);
      smoother.reset();
      smoother.add(_reading(Posture.sujud, 0.9));
      smoother.add(_reading(Posture.sujud, 0.9));
      expect(smoother.add(_reading(Posture.sujud, 0.9)), Posture.sujud);
    });

    test('nobody never counts, however sure the model is', () {
      final smoother = PostureSmoother(
          thresholds: {for (final posture in Posture.values) posture: 0});
      for (var i = 0; i < 5; i++) {
        expect(smoother.add(_reading(null, 0.4)), isNull);
      }
    });

    test('needs a threshold for every posture', () {
      expect(() => PostureSmoother(thresholds: {Posture.qiyam: 0.6}),
          throwsA(isA<AssertionError>()));
    });

    test('its thresholds are the ones calibrated with the bundled model', () {
      final calibration = jsonDecode(
          File('ml/prayer_posture/results/thresholds.json')
              .readAsStringSync()) as Map<String, dynamic>;
      final thresholds = calibration['thresholds'] as Map<String, dynamic>;
      expect(
          thresholds.keys, unorderedEquals(Posture.values.map((p) => p.name)));
      for (final posture in Posture.values) {
        expect(PostureSmoother.defaultThresholds[posture],
            (thresholds[posture.name] as num).toDouble(),
            reason: posture.name);
      }
      expect(PostureSmoother().thresholds, PostureSmoother.defaultThresholds);
    });

    test('lets go of a posture the child has left', () {
      final smoother = PostureSmoother();
      for (var i = 0; i < 3; i++) {
        smoother.add(_reading(Posture.qiyam));
      }
      expect(smoother.add(_reading(Posture.ruku)), Posture.qiyam);
      expect(smoother.add(_reading(Posture.ruku)), Posture.qiyam);
      expect(smoother.add(_reading(Posture.ruku)), Posture.ruku);
      smoother.reset();
      expect(smoother.add(_reading(Posture.ruku)), isNull);
    });
  });

  group('MovementPractice', () {
    final start = DateTime(2026, 10, 6, 9);
    DateTime at(int milliseconds) =>
        start.add(Duration(milliseconds: milliseconds));

    test('runs through the movements of one rak\'ah in order', () {
      expect([
        for (final step in practiceSteps) step.posture
      ], [
        Posture.qiyam,
        Posture.ruku,
        Posture.qiyam,
        Posture.sujud,
        Posture.julus,
        Posture.sujud,
        Posture.julus,
      ]);
      // A step never asks for the posture the last one held.
      for (var i = 1; i < practiceSteps.length; i++) {
        expect(practiceSteps[i].posture, isNot(practiceSteps[i - 1].posture));
      }
    });

    test('moves on when the helper sees the step held', () {
      final practice = MovementPractice();
      practice.observe(Posture.qiyam, at(0));
      expect(practice.index, 0);
      practice.observe(Posture.qiyam, at(1199));
      expect(practice.index, 0);
      practice.observe(Posture.qiyam, at(1200));
      expect(practice.index, 1);
      expect(practice.lastByHelper, isTrue);
      expect(practice.seen, isNull, reason: 'the next step starts afresh');
    });

    test('another posture is shown, never counted as a mistake', () {
      final practice = MovementPractice();
      practice.observe(Posture.julus, at(0));
      practice.observe(Posture.julus, at(5000));
      expect(practice.index, 0);
      expect(practice.seen, Posture.julus);
      // Losing the posture restarts the hold.
      practice.observe(Posture.qiyam, at(5000));
      practice.observe(null, at(5600));
      practice.observe(Posture.qiyam, at(6000));
      practice.observe(Posture.qiyam, at(7000));
      expect(practice.index, 0);
      practice.observe(Posture.qiyam, at(7200));
      expect(practice.index, 1);
    });

    test('works without the camera, and can start again', () {
      final practice = MovementPractice();
      for (var i = 0; i < practiceSteps.length; i++) {
        expect(practice.finished, isFalse);
        practice.next();
      }
      expect(practice.finished, isTrue);
      expect(practice.step, isNull);
      expect(practice.lastByHelper, isFalse);
      practice.next();
      expect(practice.index, practiceSteps.length);
      practice.restart();
      expect(practice.index, 0);
    });
  });
}
