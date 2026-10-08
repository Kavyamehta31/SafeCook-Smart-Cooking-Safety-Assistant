import 'package:flutter/services.dart';
import 'speech_service.dart';

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;

  final SpeechService _speechService = SpeechService();
  bool _isListening = false;
  bool _restartScheduled = false;
  bool get isListening => _isListening;
  VoidCallback? _onWakeDetected;

  WakeWordService._internal();

  Future<void> startWakeWordDetection({
    required VoidCallback onWakeDetected,
  }) async {
    if (_isListening) return;
    _isListening = true;
    _onWakeDetected = onWakeDetected;
    _runWakeWordLoop();
  }

  Future<void> stopWakeWordDetection() async {
    _isListening = false;
    _restartScheduled = false;
    await _speechService.stopListening();
  }

  Future<void> _runWakeWordLoop() async {
    if (!_isListening) return;

    await _speechService.startListening(
      onResult: (text) {
        final lower = text.toLowerCase();
        if (lower.contains('hello safecook') ||
            lower.contains('hey safecook') ||
            lower.contains('hello safe cook') ||
            lower.contains('hey safe cook') ||
            lower.contains('safecook') ||
            lower.contains('safe cook')) {
          _triggerWakeDetection();
        }
      },
      onError: (err) {
        _scheduleRestart(const Duration(milliseconds: 1000));
      },
      onDoneListening: () {
        _scheduleRestart(const Duration(milliseconds: 500));
      },
    );
  }

  void _scheduleRestart(Duration delay) {
    if (!_isListening || _restartScheduled) return;
    _restartScheduled = true;
    Future<void>.delayed(delay, () {
      _restartScheduled = false;
      if (_isListening) _runWakeWordLoop();
    });
  }

  void _triggerWakeDetection() async {
    if (!_isListening) return;
    _isListening = false;
    await _speechService.stopListening();

    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.vibrate();

    if (_onWakeDetected != null) {
      _onWakeDetected!();
    }
  }
}
