import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  final List<String> spokenTexts = [];

  VoidCallback? _completionCallback;

  void setCompletionCallback(VoidCallback? cb) {
    _completionCallback = cb;
  }

  void clearSpokenTexts() {
    spokenTexts.clear();
  }

  VoiceService._internal() {
    _initTts();
  }

  void _initTts() {
    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      if (_completionCallback != null) {
        _completionCallback!();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
    });
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    spokenTexts.add(text);
    try {
      await stop();
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5); // standard speed
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[VoiceService] speak native error (expected in tests): $e');
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
    _isSpeaking = false;
  }

  bool get isSpeaking => _isSpeaking;
}
