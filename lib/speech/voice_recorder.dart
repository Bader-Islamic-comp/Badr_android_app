import 'dart:typed_data';

import 'package:record/record.dart';

import 'wav.dart';

/// The microphone, as the speech preview uses it: PCM streamed into memory
/// while a button is held. Tests pass a fake.
abstract class VoiceRecorder {
  /// Asks for the microphone permission when it is not given yet. False when
  /// it is refused.
  Future<bool> ensurePermission();

  /// Starts recording 16-bit PCM, mono, 16 kHz, delivered as chunks of bytes.
  /// Nothing is written to a file.
  Future<Stream<Uint8List>> start();

  /// Stops recording. The recorder can start again.
  Future<void> stop();

  /// Stops recording and releases the microphone for good.
  Future<void> dispose();
}

/// [VoiceRecorder] on the `record` plugin (Android's `AudioRecord`). It only
/// ever streams: the plugin's file recording is never used, so no temporary
/// audio file exists.
class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder();

  AudioRecorder? _recorder;

  /// Made on first use, never at app start: a build that never records never
  /// creates a recorder.
  AudioRecorder get _plugin => _recorder ??= AudioRecorder();

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: recordingSampleRate,
    numChannels: recordingChannels,
    androidConfig: AndroidRecordConfig(
      // Tuned for speech recognition, and no Bluetooth headset handling.
      audioSource: AndroidAudioSource.voiceRecognition,
      manageBluetooth: false,
    ),
  );

  @override
  Future<bool> ensurePermission() => _plugin.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _plugin.startStream(_config);

  @override
  Future<void> stop() async {
    await _recorder?.stop();
  }

  @override
  Future<void> dispose() async {
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
  }
}
