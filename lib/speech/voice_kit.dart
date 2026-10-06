import '../domain/speech_models.dart';
import 'audio_playback.dart';
import 'voice_recorder.dart';

/// Whether this build carries the speech preview at all. A build made with
/// `--dart-define=VOICE=false` has no speech screen, no microphone button, no
/// parent switch for it and never asks for the microphone: the kill switch.
const voiceBuilt = bool.fromEnvironment('VOICE', defaultValue: true);

/// What the speech preview is built from. The app uses the defaults; tests
/// pass fakes, a fake clock and their own build switch.
class VoiceKit {
  const VoiceKit({
    this.built = voiceBuilt,
    this.recorder = RecordVoiceRecorder.new,
    this.playback = AudioPlayersPlayback.new,
    this.wait,
    this.now,
    this.pollInterval = const Duration(seconds: 2),
    this.voiceDeadline = const Duration(minutes: 5),
  });

  /// The build's kill switch. Tests set it to check the logic of both builds.
  final bool built;
  final VoiceRecorder Function() recorder;
  final AudioPlayback Function() playback;

  /// Waits between reads of Robert's voice. Defaults to a real delay.
  final Future<void> Function(Duration)? wait;

  /// The time, for the voice deadline. Defaults to the clock.
  final DateTime Function()? now;

  /// How often Robert's voice is read again while it is being made.
  final Duration pollInterval;

  /// How long a Listen waits for Robert's voice before giving up.
  final Duration voiceDeadline;

  Future<void> pause(Duration duration) =>
      (wait ?? (value) => Future<void>.delayed(value))(duration);

  DateTime clock() => (now ?? DateTime.now)();
}

/// Which parts of the speech preview show right now: the build's switch, the
/// service's switches and the parent's microphone switch together.
class VoiceAccess {
  const VoiceAccess({
    required this.kit,
    required this.features,
    required this.connected,
    required this.microphone,
  });

  final VoiceKit kit;
  final SpeechFeatures features;
  final bool connected;

  /// The parent area's "Microphone (hold to talk)". Off at every start.
  final bool microphone;

  /// The service runs the preview and this build carries it.
  bool get preview => kit.built && connected && features.preview;

  /// Adhkar and dua practice, and the dhikr game.
  bool get recitation => preview && features.recitation;

  /// Asking Robert out loud. Needs the microphone switch too.
  bool get voiceQuestions => preview && features.voiceQuestions && microphone;

  /// The Listen button under Robert's replies. Needs no switch.
  bool get robertVoice => preview && features.robertVoice;

  /// Whether anything may record. Listening to audio needs no switch.
  bool get canRecord => preview && microphone;

  int get maxSeconds => features.maxRecordingSeconds;
}
