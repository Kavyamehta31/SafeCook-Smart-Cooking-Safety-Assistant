import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  SpeechService._internal();

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) => debugPrint('[SpeechService] Error: $val'),
        onStatus: (val) => debugPrint('[SpeechService] Status: $val'),
      );
    } catch (e) {
      debugPrint('[SpeechService] Initialization exception: $e');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  Future<void> startListening({
    required Function(String) onResult,
    required Function(String) onError,
    required VoidCallback onDoneListening,
  }) async {
    final hasPermission = await initialize();
    if (!hasPermission) {
      onError('Speech recognition not initialized or permission denied');
      return;
    }

    bool doneCalled = false;
    _speech.statusListener = (status) {
      debugPrint('[SpeechService] status=$status doneCalled=$doneCalled');
      if (status == 'done' || status == 'notListening') {
        if (!doneCalled) {
          doneCalled = true;
          onDoneListening();
        }
      }
    };

    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _isInitialized;
}
