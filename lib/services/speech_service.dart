import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceConversationMode {
  bool _active = false;

  bool get isActive => _active;

  void activate() => _active = true;

  void deactivate() => _active = false;

  bool shouldListenAfterTts({bool inactivityTimedOut = false}) =>
      _active && !inactivityTimedOut;
}

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _listenRequestActive = false;
  int _listenCycle = 0;

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
    if (_listenRequestActive || _speech.isListening) {
      debugPrint('[SpeechService] Ignoring overlapping listen request');
      return;
    }

    _listenRequestActive = true;
    final cycle = ++_listenCycle;
    final hasPermission = await initialize();
    if (!hasPermission) {
      if (cycle == _listenCycle) {
        _listenRequestActive = false;
        onError('Speech recognition not initialized or permission denied');
      }
      return;
    }

    bool doneCalled = false;
    _speech.statusListener = (status) {
      debugPrint('[SpeechService] status=$status doneCalled=$doneCalled');
      if (status == 'done' || status == 'notListening') {
        if (!doneCalled && cycle == _listenCycle) {
          doneCalled = true;
          _listenRequestActive = false;
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
      if (cycle == _listenCycle) {
        _listenRequestActive = false;
        onError(e.toString());
      }
    }
  }

  Future<void> stopListening() async {
    _listenCycle++;
    _listenRequestActive = false;
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _isInitialized;
}
