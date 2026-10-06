import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:companion_mobile/posture/camera_posture_source.dart';
import 'package:companion_mobile/posture/posture.dart';
import 'package:companion_mobile/posture/posture_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// The bundled posture model on a phone or emulator, through the app's own
/// input code and the Android runtime.
///
/// It reads held-out photos, one folder per posture, from the app's own
/// internal storage: files the shell puts in the app's external folder are not
/// the app's to read. Install the app, then copy them in with `run-as`
/// (`ml/prayer_posture/README.md` makes the `check` folder):
///
///     adb install -r -t build/app/outputs/flutter-apk/app-debug.apk
///     adb push <prepared>/check /data/local/tmp/posture_check
///     adb shell "tar -cf - -C /data/local/tmp posture_check | run-as dev.learningcompanion.companion_mobile sh -c 'mkdir -p files && tar -xf - -C files'"
///
/// The test run replaces the app in place, which keeps them. With no photos
/// the test is skipped. Only counts and timings are printed, never an image or
/// a file name.
const _folder =
    '/data/user/0/dev.learningcompanion.companion_mobile/files/posture_check';

Future<(Uint8List, int, int)> _rgba(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final image = (await codec.getNextFrame()).image;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final size = (image.width, image.height);
  image.dispose();
  return (bytes!.buffer.asUint8List(), size.$1, size.$2);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the bundled model reads held-out photos on the device',
      (tester) async {
    final root = Directory(_folder);
    if (!root.existsSync()) {
      markTestSkipped('no photos pushed to $_folder');
      return;
    }
    final interpreter = await Interpreter.fromAsset(
        CameraPostureSource.modelAsset,
        options: InterpreterOptions()..threads = 2);
    expect(interpreter.getInputTensor(0).shape, [1, 224, 224, 3]);
    expect(interpreter.getOutputTensor(0).shape, [1, PostureReading.outputs]);

    // Rows and columns: the postures, then nobody.
    final names = [for (final p in Posture.values) p.name, 'none'];
    final confusion = [
      for (final _ in names) List.filled(PostureReading.outputs, 0)
    ];
    var micros = 0;
    var count = 0;
    for (final (index, name) in names.indexed) {
      final folder = Directory('$_folder/$name');
      if (!folder.existsSync()) continue;
      for (final file in folder.listSync().whereType<File>()) {
        final (rgba, width, height) = await _rgba(file);
        final input = PostureInput.fromRgba(rgba, width, height);
        final output = Float32List(PostureReading.outputs);
        interpreter.run(input.buffer.asUint8List(), output.buffer);
        micros += interpreter.lastNativeInferenceDurationMicroSeconds;
        final reading = PostureReading(output.toList());
        expect(reading.probabilities.fold<double>(0, (a, b) => a + b),
            closeTo(1, 0.01));
        confusion[index][reading.top?.index ?? Posture.values.length]++;
        count++;
      }
    }
    interpreter.close();
    expect(count, greaterThan(0));
    final right = [for (var i = 0; i < names.length; i++) confusion[i][i]]
        .fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print('posture model on device: $right/$count right '
        '(${(100 * right / count).toStringAsFixed(1)}%), '
        '${(micros / count / 1000).toStringAsFixed(1)} ms per inference, '
        'confusion $confusion');
    expect(right / count, greaterThan(0.85));
  });
}
