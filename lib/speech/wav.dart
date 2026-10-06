import 'dart:typed_data';

/// What the microphone records for the speech preview: 16-bit PCM, mono,
/// 16 kHz, the speech service's own input format.
const recordingSampleRate = 16000;
const recordingChannels = 1;
const recordingBitsPerSample = 16;

/// Bytes of PCM in one second of a recording.
const recordingBytesPerSecond =
    recordingSampleRate * recordingChannels * recordingBitsPerSample ~/ 8;

/// The canonical WAV header: RIFF, `fmt ` and `data` chunks.
const wavHeaderBytes = 44;

/// Wraps raw little-endian 16-bit PCM in a WAV header, in memory. A trailing
/// odd byte (half a sample) is left out.
Uint8List wavFromPcm16(
  Uint8List pcm, {
  int sampleRate = recordingSampleRate,
  int channels = recordingChannels,
}) {
  final length = pcm.length - pcm.length % 2;
  const bytesPerSample = recordingBitsPerSample ~/ 8;
  final wav = Uint8List(wavHeaderBytes + length);
  final header = ByteData.sublistView(wav, 0, wavHeaderBytes);
  void tag(int offset, String value) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  // Everything after this field: the rest of the header and the samples.
  header.setUint32(4, wavHeaderBytes - 8 + length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM's fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM, uncompressed
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(
      28, sampleRate * channels * bytesPerSample, Endian.little); // byte rate
  header.setUint16(32, channels * bytesPerSample, Endian.little); // block
  header.setUint16(34, recordingBitsPerSample, Endian.little);
  tag(36, 'data');
  header.setUint32(40, length, Endian.little);
  wav.setRange(wavHeaderBytes, wavHeaderBytes + length, pcm);
  return wav;
}
