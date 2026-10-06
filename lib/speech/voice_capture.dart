import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/demo_api.dart';
import 'voice_recorder.dart';
import 'wav.dart';

enum CaptureState {
  /// Nothing is recording.
  idle,

  /// The button is down and the microphone is being asked for or started.
  starting,

  /// Recording, while the button is held.
  listening,
}

/// One hold-to-talk button's recording: from press to release, and nothing
/// before or after.
///
/// The microphone runs only while the button is held, and never while the app
/// is away from the screen. Audio is gathered in memory, never in a file, and
/// is bounded twice: by [maxSeconds] and by what one request may carry
/// ([DemoApi.maxAudioBytes] with the WAV header). Reaching either ends the
/// recording as if the button were let go. Letting go hands the WAV to
/// [onRecorded]; when that returns, the bytes are cleared and nothing keeps
/// them. A cancel, leaving the page or leaving the app drops them unsent,
/// even while the microphone is still stopping.
///
/// Android asks for the microphone in a window of its own, which takes the
/// touch and leaves the app `inactive` behind it. While that question is
/// open the press waits for the answer rather than ending: a refusal says so,
/// and a yes says to hold the button again ([nowHold]).
class VoiceCapture extends ChangeNotifier with WidgetsBindingObserver {
  VoiceCapture({
    required VoiceRecorder Function() recorder,
    required this.maxSeconds,
    required this.onRecorded,
    this.shortest = const Duration(milliseconds: 300),
  }) : _makeRecorder = recorder {
    WidgetsBinding.instance.addObserver(this);
  }

  static const permissionRefused =
      'The microphone permission was not given, so nothing was recorded.';
  static const couldNotStart =
      'The microphone did not start. Please try again.';
  static const holdLonger = 'Hold the button down while you speak.';
  static const nowHold = 'The microphone is ready. Now hold to talk. · '
      'الميكروفون جاهز، اضغط مطوّلًا وتكلّم';

  final VoiceRecorder Function() _makeRecorder;
  final int maxSeconds;
  final Future<void> Function(Uint8List wav) onRecorded;

  /// A press shorter than this is taken as a tap, and nothing is sent.
  final Duration shortest;

  CaptureState state = CaptureState.idle;

  /// Whole seconds recorded so far, for the listening indicator.
  int seconds = 0;

  /// Why the last press recorded nothing, written for the child.
  String? problem;

  VoiceRecorder? _recorder;
  StreamSubscription<Uint8List>? _chunks;
  BytesBuilder? _pcm;
  Timer? _ticker;
  bool _held = false;
  bool _foreground = true;
  bool _disposed = false;
  int _session = 0;

  /// The permission question is open, and whether Android's prompt took the
  /// screen (and the touch) while it was.
  bool _asking = false;
  bool _askInterrupted = false;

  /// A finished recording is waiting for the microphone to stop before it is
  /// handed over. No new press starts meanwhile: it would race that stop.
  bool _handingOver = false;

  bool get listening => state == CaptureState.listening;

  /// The most PCM one recording may hold.
  int get maxPcmBytes => math.min(maxSeconds * recordingBytesPerSecond,
      DemoApi.maxAudioBytes - wavHeaderBytes);

  int get _shortestBytes =>
      recordingBytesPerSecond * shortest.inMilliseconds ~/ 1000;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The button went down.
  Future<void> press() async {
    if (_disposed ||
        _handingOver ||
        state != CaptureState.idle ||
        !_foreground) {
      return;
    }
    _held = true;
    problem = null;
    state = CaptureState.starting;
    _changed();
    final session = ++_session;
    final recorder = _recorder ??= _makeRecorder();
    bool allowed;
    _asking = true;
    _askInterrupted = false;
    try {
      allowed = await recorder.ensurePermission();
    } catch (_) {
      allowed = false;
    } finally {
      _asking = false;
    }
    if (session != _session || _disposed) return;
    if (!allowed) {
      state = CaptureState.idle;
      problem = permissionRefused;
      _changed();
      return;
    }
    // Android's prompt took the touch: the finger that pressed is gone, so
    // the next hold records.
    if (_askInterrupted) {
      state = CaptureState.idle;
      problem = nowHold;
      _changed();
      return;
    }
    // Let go while the system was asking, or the app left the screen.
    if (!_held || !_foreground) {
      state = CaptureState.idle;
      _changed();
      return;
    }
    try {
      final stream = await recorder.start();
      if (session != _session || _disposed) {
        await recorder.stop();
        return;
      }
      if (!_held || !_foreground) {
        // Let go before the microphone was ready: a tap, not a recording.
        await recorder.stop();
        state = CaptureState.idle;
        problem = _foreground ? holdLonger : null;
        _changed();
        return;
      }
      _pcm = BytesBuilder(copy: true);
      seconds = 0;
      _chunks =
          stream.listen(_add, onError: (Object _) => _drop(couldNotStart));
      _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
      state = CaptureState.listening;
      _changed();
    } catch (_) {
      if (session != _session || _disposed) return;
      state = CaptureState.idle;
      problem = couldNotStart;
      _changed();
    }
  }

  /// The button came up: what was heard is sent.
  Future<void> release() async {
    _held = false;
    if (state == CaptureState.listening) await _finish();
  }

  /// Drops whatever is recording, unsent, and a finished recording that is
  /// still waiting for the microphone to stop.
  void cancel() {
    _held = false;
    if (state == CaptureState.idle) {
      _session++;
      return;
    }
    _drop(null);
  }

  /// The system took the touch away. While Android's permission prompt is
  /// open this is the prompt itself, and the answer is still awaited;
  /// otherwise it is a [cancel].
  void touchCancelled() {
    if (_asking) {
      _interruptAsk();
    } else {
      cancel();
    }
  }

  void _interruptAsk() {
    _held = false;
    _askInterrupted = true;
  }

  void _tick(Timer timer) {
    if (state != CaptureState.listening) return;
    seconds++;
    _changed();
    if (seconds >= maxSeconds) unawaited(_finish());
  }

  void _add(Uint8List chunk) {
    final pcm = _pcm;
    if (pcm == null) return;
    final room = maxPcmBytes - pcm.length;
    if (room <= 0) return;
    pcm.add(
        chunk.length <= room ? chunk : Uint8List.sublistView(chunk, 0, room));
    if (pcm.length >= maxPcmBytes) unawaited(_finish());
  }

  Future<void> _finish() async {
    if (state != CaptureState.listening) return;
    final pcm = _pcm?.takeBytes() ?? Uint8List(0);
    final session = ++_session;
    _handingOver = true;
    try {
      await _stopRecording();
    } finally {
      _handingOver = false;
    }
    // The page closed, or the app left the screen, while the microphone
    // stopped: nothing is sent and nobody is told.
    if (_disposed || session != _session) {
      pcm.fillRange(0, pcm.length, 0);
      return;
    }
    if (pcm.length < _shortestBytes) {
      pcm.fillRange(0, pcm.length, 0);
      problem = holdLonger;
      _changed();
      return;
    }
    final wav = wavFromPcm16(pcm);
    pcm.fillRange(0, pcm.length, 0);
    try {
      await onRecorded(wav);
    } finally {
      wav.fillRange(0, wav.length, 0);
    }
  }

  void _drop(String? reason) {
    _session++;
    final pcm = _pcm?.takeBytes();
    pcm?.fillRange(0, pcm.length, 0);
    unawaited(_stopRecording());
    if (reason != null) problem = reason;
    _changed();
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    _ticker = null;
    final chunks = _chunks;
    _chunks = null;
    _pcm = null;
    state = CaptureState.idle;
    seconds = 0;
    _changed();
    // Not awaited: no more chunks are taken either way, and a cancel can
    // complete outside this zone.
    unawaited(chunks?.cancel());
    try {
      await _recorder?.stop();
    } catch (_) {
      // Already stopped.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) return;
    // Android's permission prompt leaves the app inactive behind it: the
    // press waits for the answer. Leaving the app still ends it.
    if (state == AppLifecycleState.inactive && _asking) {
      _interruptAsk();
      return;
    }
    // No recording behind another app or a locked screen.
    cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    cancel();
    final recorder = _recorder;
    _recorder = null;
    unawaited(recorder?.dispose());
    super.dispose();
  }
}
