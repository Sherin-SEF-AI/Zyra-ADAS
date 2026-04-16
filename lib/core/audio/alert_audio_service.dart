import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Lightweight audio alert service with 3 pre-loaded one-shot players.
/// Each player has a 500ms cooldown to prevent rapid re-triggers during
/// state-machine jitter.
class AlertAudioService {
  AlertAudioService();

  final AudioPlayer _fcwWarnPlayer = AudioPlayer();
  final AudioPlayer _fcwAlertPlayer = AudioPlayer();
  final AudioPlayer _ldwAlertPlayer = AudioPlayer();

  DateTime _lastFcwWarn = DateTime(2000);
  DateTime _lastFcwAlert = DateTime(2000);
  DateTime _lastLdwAlert = DateTime(2000);

  static const Duration _cooldown = Duration(milliseconds: 500);

  bool _disposed = false;

  /// Pre-load the WAV assets so first playback is instant.
  Future<void> init() async {
    await Future.wait(<Future<void>>[
      _fcwWarnPlayer.setAsset('assets/audio/fcw_warn.wav'),
      _fcwAlertPlayer.setAsset('assets/audio/fcw_alert.wav'),
      _ldwAlertPlayer.setAsset('assets/audio/ldw_alert.wav'),
    ]);
  }

  void playFcwWarn() {
    if (_disposed) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastFcwWarn) < _cooldown) return;
    _lastFcwWarn = now;
    _replay(_fcwWarnPlayer);
  }

  void playFcwAlert() {
    if (_disposed) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastFcwAlert) < _cooldown) return;
    _lastFcwAlert = now;
    _replay(_fcwAlertPlayer);
  }

  void playLdwAlert() {
    if (_disposed) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastLdwAlert) < _cooldown) return;
    _lastLdwAlert = now;
    _replay(_ldwAlertPlayer);
  }

  void _replay(AudioPlayer player) {
    player.seek(Duration.zero).then((_) => player.play());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _fcwWarnPlayer.dispose();
    await _fcwAlertPlayer.dispose();
    await _ldwAlertPlayer.dispose();
  }
}

/// Riverpod provider — initialises once and disposes on app teardown.
final Provider<AlertAudioService> alertAudioProvider =
    Provider<AlertAudioService>((Ref ref) {
  final AlertAudioService service = AlertAudioService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});
