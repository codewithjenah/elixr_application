import 'package:audioplayers/audioplayers.dart';

/// Small injectable boundary around audioplayers so lifecycle behavior can be
/// tested without opening a native audio device.
abstract interface class AudioPlayerHandle {
  Stream<void> get onPlayerComplete;

  Future<void> setReleaseMode(ReleaseMode mode);
  Future<void> setVolume(double volume);
  Future<void> playAsset(String assetPath);
  Future<void> playFile(String filePath);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

class AudioplayersHandle implements AudioPlayerHandle {
  AudioplayersHandle() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) => _player.setReleaseMode(mode);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> playAsset(String assetPath) =>
      _player.play(AssetSource(assetPath));

  @override
  Future<void> playFile(String filePath) =>
      _player.play(DeviceFileSource(filePath));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
