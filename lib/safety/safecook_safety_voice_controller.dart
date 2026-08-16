import 'safecook_safety_engine.dart';
import 'safecook_safety_event.dart';

// Interface that the active context screens must implement to handle safety speech
abstract class SafetyVoiceDelegate {
  void handleSafetyVoiceEvent(SafeCookSafetyEvent event);
}

class SafetyVoiceController {
  static final SafetyVoiceController _instance = SafetyVoiceController._internal();
  factory SafetyVoiceController() => _instance;

  SafetyVoiceController._internal() {
    SafeCookSafetyEngine().onSafetyEvent.listen(_handleSafetyEvent);
  }

  SafetyVoiceDelegate? _homeDelegate;
  SafetyVoiceDelegate? _cookingDelegate;

  void registerHomeScreen(SafetyVoiceDelegate delegate) {
    _homeDelegate = delegate;
  }

  void unregisterHomeScreen(SafetyVoiceDelegate delegate) {
    if (_homeDelegate == delegate) {
      _homeDelegate = null;
    }
  }

  void registerCookingScreen(SafetyVoiceDelegate delegate) {
    _cookingDelegate = delegate;
  }

  void unregisterCookingScreen(SafetyVoiceDelegate delegate) {
    if (_cookingDelegate == delegate) {
      _cookingDelegate = null;
    }
  }

  void _handleSafetyEvent(SafeCookSafetyEvent event) {
    // Topmost context / Cooking guidance screen always takes precedence
    if (_cookingDelegate != null) {
      _cookingDelegate!.handleSafetyVoiceEvent(event);
    } else if (_homeDelegate != null) {
      _homeDelegate!.handleSafetyVoiceEvent(event);
    }
  }
}
