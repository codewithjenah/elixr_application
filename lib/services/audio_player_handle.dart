import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Serializes commands that enter the Windows audioplayers native backend.
///
/// `audioplayers_windows` resolves media sources on detached C++ threads. A
/// Dart Future protects one [AudioPlayer], but separate players can otherwise
/// issue source, stop, and disposal commands against Media Foundation at the
/// same time. Keeping one process-wide tail prevents that native race without
/// preventing already-started players from continuing to play concurrently.
class AudioOperationGate {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }
}

/// Small injectable boundary around audioplayers so lifecycle behavior can be
/// tested without opening a native audio device.
abstract interface class AudioPlayerHandle {
  Stream<void> get onPlayerComplete;

  Future<void> setReleaseMode(ReleaseMode mode);
  Future<void> setVolume(double volume);
  Future<void> setSourceAsset(String assetPath);
  Future<void> playAsset(String assetPath);
  Future<void> playAssetAtPosition(String assetPath, {Duration? position});
  Future<void> playFile(String filePath);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

class AudioplayersHandle implements AudioPlayerHandle {
  AudioplayersHandle()
    : _player = AudioPlayer(),
      _operationGate =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
          ? _windowsOperationGate
          : null;

  static final AudioOperationGate _windowsOperationGate = AudioOperationGate();

  final AudioPlayer _player;
  final AudioOperationGate? _operationGate;

  Future<void> _run(Future<void> Function() action) =>
      _operationGate?.run(action) ?? Future<void>.sync(action);

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) =>
      _run(() => _player.setReleaseMode(mode));

  @override
  Future<void> setVolume(double volume) =>
      _run(() => _player.setVolume(volume));

  @override
  Future<void> setSourceAsset(String assetPath) =>
      _run(() => _player.setSource(AssetSource(assetPath)));

  @override
  Future<void> playAsset(String assetPath) =>
      _run(() => _player.play(AssetSource(assetPath)));

  @override
  Future<void> playAssetAtPosition(String assetPath, {Duration? position}) =>
      _run(() => _player.play(AssetSource(assetPath), position: position));

  @override
  Future<void> playFile(String filePath) =>
      _run(() => _player.play(DeviceFileSource(filePath)));

  @override
  Future<void> pause() => _run(_player.pause);

  @override
  Future<void> resume() => _run(_player.resume);

  @override
  Future<void> stop() => _run(_player.stop);

  @override
  Future<void> dispose() => _run(_player.dispose);
}
