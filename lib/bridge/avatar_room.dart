import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'avatar_bridge.dart';

/// Owns the character room's lifecycle across bridge instances.
///
/// A terminal transport failure cannot be recovered inside one [AvatarBridge]:
/// the native receiver keeps its sequence watermark and initialization state, so
/// reusing the same Flutter bridge would send stale sequences into a live
/// receiver. Recovery therefore disposes this bridge, asks the host to dispose
/// the native room, and starts a fresh session with both sides reset together.
///
/// The `disposeRoom` method is part of the `companion/unity_commands` host API
/// alongside `sendMessage` and `openRoom`. It carries no envelope, so the
/// bridge v1 message contract is unchanged.
class AvatarRoom extends ChangeNotifier {
  AvatarRoom({
    MethodChannel? commands,
    AvatarBridge Function()? create,
    this.maxAttempts = 3,
  })  : _commands = commands ?? const MethodChannel('companion/unity_commands'),
        _create = create ?? AvatarBridge.new {
    _bridge = _create();
    _bridge.addListener(_onBridgeChanged);
  }

  final MethodChannel _commands;
  final AvatarBridge Function() _create;

  /// Recreation is bounded: a host that never recovers must not be retried in a
  /// loop while a child is waiting on the static avatar.
  final int maxAttempts;

  late AvatarBridge _bridge;
  int _attempts = 0;
  bool _started = false;
  bool _recreating = false;
  bool _disposed = false;
  bool _surfaceAttached = false;
  bool _onCharacterPage = false;
  bool _foreground = true;
  bool _motionEnabled = true;

  AvatarBridge get bridge => _bridge;

  /// True when the host has a room surface composited behind Flutter. The UI
  /// may only paint transparently while this holds.
  bool get surfaceAttached => _surfaceAttached;
  AvatarStatus get status => _bridge.status;
  bool get recreating => _recreating;
  bool get motionEnabled => _motionEnabled;

  /// True once a started session has fallen back and a fresh room may be tried.
  bool get canRetry =>
      _started &&
      !_recreating &&
      !_disposed &&
      _bridge.status == AvatarStatus.staticPreview &&
      _attempts < maxAttempts;

  void _onBridgeChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _attempts = 1;
    // Whether a surface is composited is a presentation detail. Asking must not
    // delay the handshake, so it runs alongside it.
    unawaited(_probeSurface());
    await _bridge.initialize();
  }

  Future<void> retry() async {
    if (!canRetry) return;
    _recreating = true;
    _attempts++;
    notifyListeners();
    try {
      _bridge.removeListener(_onBridgeChanged);
      _bridge.dispose();
      // Best effort: a host without the method, or no host at all, still leaves
      // the static avatar usable.
      try {
        await _commands.invokeMethod<void>('disposeRoom');
      } catch (_) {
        // The next initialize() decides whether a room is actually available.
      }
      if (_disposed) return;
      _bridge = _create();
      _bridge.addListener(_onBridgeChanged);
      unawaited(_probeSurface());
      await _bridge.initialize();
      if (_disposed) return;
      await _bridge.setMotionEnabled(_motionEnabled);
      await _bridge.setForeground(_foreground);
      await _bridge.setOnCharacterPage(_onCharacterPage);
    } finally {
      _recreating = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _probeSurface() async {
    final attached = await _bridge.probeSurface();
    if (_disposed || attached == _surfaceAttached) return;
    _surfaceAttached = attached;
    notifyListeners();
  }

  Future<void> setOnCharacterPage(bool value) {
    _onCharacterPage = value;
    return _bridge.setOnCharacterPage(value);
  }

  Future<void> setForeground(bool value) {
    _foreground = value;
    return _bridge.setForeground(value);
  }

  Future<void> setMotionEnabled(bool value) {
    _motionEnabled = value;
    return _bridge.setMotionEnabled(value);
  }

  bool react(AvatarReaction reaction) => _bridge.react(reaction);

  Future<bool> openRoom() => _bridge.openRoom();

  Future<bool> applyServerConfirmedCosmetic(String cosmeticId) =>
      _bridge.applyServerConfirmedCosmetic(cosmeticId);

  @override
  void dispose() {
    _disposed = true;
    _bridge.removeListener(_onBridgeChanged);
    _bridge.dispose();
    super.dispose();
  }
}
