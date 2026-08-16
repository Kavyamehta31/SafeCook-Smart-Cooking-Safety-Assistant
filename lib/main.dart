import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/recipe.dart';
import 'screens/recipe_list_screen.dart';
import 'screens/cooking_guidance_screen.dart';
import 'services/speech_service.dart';
import 'services/voice_service.dart';
import 'services/voice_assistant_service.dart';
import 'services/wake_word_service.dart';
import 'agent/safecook_agent.dart';
import 'agent/safecook_context.dart';
import 'agent/safecook_tools.dart';

// SafeCook Safety Thresholds
const int kGasNormalMax = 300;     // Gas levels < 300 are Normal
const int kGasWarningMax = 600;    // Gas levels 300 to 599 are Warning, >= 600 are Critical

const double kDistanceSafeMin = 30.0;    // Distance > 30 cm is Safe
const double kDistanceWarningMin = 15.0; // Distance 15 to 30 cm is Close, < 15 cm is Very Close

void main() {
  runApp(const SafeCookBluetoothTestApp());
}

enum ClassicAdapterState { unknown, on, off }

class BluetoothDevice {
  final String name;
  final String address;
  final String bondState;

  BluetoothDevice({
    required this.name,
    required this.address,
    required this.bondState,
  });

  factory BluetoothDevice.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothDevice(
      name: map['name'] as String? ?? 'Unknown Device',
      address: map['address'] as String? ?? '',
      bondState: map['bondState'] as String? ?? 'unknown',
    );
  }
}

class SafetyEvent {
  final DateTime timestamp;
  final String state;
  final int? gasValue;
  final String? distanceValue;

  SafetyEvent({
    required this.timestamp,
    required this.state,
    this.gasValue,
    this.distanceValue,
  });
}

class SensorDataPoint {
  final DateTime timestamp;
  final double value;

  SensorDataPoint({required this.timestamp, required this.value});
}

class MiniLineChartPainter extends CustomPainter {
  final List<SensorDataPoint> data;
  final Color lineColor;
  final double? minVal;
  final double? maxVal;

  MiniLineChartPainter({
    required this.data,
    required this.lineColor,
    this.minVal,
    this.maxVal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    double min = minVal ?? data.first.value;
    double max = maxVal ?? data.first.value;

    for (var pt in data) {
      if (pt.value < min) min = pt.value;
      if (pt.value > max) max = pt.value;
    }

    if (max == min) {
      max += 1.0;
      min -= 1.0;
    }

    final path = Path();
    final stepX = size.width / 59.0;

    for (int i = 0; i < data.length; i++) {
      final x = size.width - (data.length - 1 - i) * stepX;
      final ratio = (data[i].value - min) / (max - min);
      final y = size.height - (ratio * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant MiniLineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class SafeCookBluetoothTestApp extends StatelessWidget {
  const SafeCookBluetoothTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeCook Bluetooth Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8), // sky blue
          secondary: Color(0xFF0EA5E9),
          surface: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
        ),
      ),
      home: const BluetoothTestPage(),
    );
  }
}

class BluetoothTestPage extends StatefulWidget {
  static bool isTesting = false;
  const BluetoothTestPage({super.key});

  @override
  State<BluetoothTestPage> createState() => BluetoothTestPageState();
}

class BluetoothTestPageState extends State<BluetoothTestPage> {
  static const _methodChannel = MethodChannel('com.safecook.bluetooth/methods');
  static const _eventChannel = EventChannel('com.safecook.bluetooth/events');
  
  StreamSubscription? _eventChannelSub;

  ClassicAdapterState _adapterState = ClassicAdapterState.unknown;
  
  List<BluetoothDevice> _bondedDevices = [];
  final List<BluetoothDevice> _discoveredDevices = [];
  
  bool _isScanning = false;
  bool _isConnecting = false;
  
  BluetoothDevice? _connectedDevice;
  
  String _connectionStatus = 'Disconnected';
  String? _connectedDeviceAddress;
  String? _connectedDeviceName;
  
  String _consoleText = '';
  Timer? _sensorFreshnessTimer;
  Completer<bool>? _connectionCompleter;
  final ScrollController _scrollController = ScrollController();
  
  bool _showPaired = true; // Tab toggle: true = Paired, false = Scanned
  bool _showBluetoothSettings = false;

  // Safety Listeners
  final List<VoidCallback> _sensorListeners = [];

  void addSensorListener(VoidCallback cb) {
    _sensorListeners.add(cb);
  }

  void removeSensorListener(VoidCallback cb) {
    _sensorListeners.remove(cb);
  }

  void _notifySensorListeners() {
    for (final cb in _sensorListeners) {
      cb();
    }
  }

  int? get currentGasValue => _gasValue;
  String? get currentDistanceValue => _distanceValue;
  bool get isBluetoothConnected => _connectedDevice != null;
  String get currentSafetyState => _getCombinedStatus();
  Color get currentSafetyColor => _getCombinedStatusColor();
  Color get currentSafetyBgColor => _getCombinedStatusBgColor();
  Color get currentSafetyBorderColor => _getCombinedStatusBorderColor();

  @visibleForTesting
  set bondedDevicesForTesting(List<BluetoothDevice> devices) {
    _bondedDevices = devices;
  }

  void endCookingSessionOutside() {
    _endCookingSession();
  }

  // -------------------------------------------------------------------------
  // Bluetooth voice tools — called by CookingGuidanceScreen via ToolResult
  // -------------------------------------------------------------------------
  Future<ToolResult> connectBluetoothFromVoice() async {
    final eventId = DateTime.now().millisecondsSinceEpoch;
    if (_connectedDevice != null) {
      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=false\n'
          'actualConnected=true');
      return const ToolResult.ok('Already connected');
    }
    if (_bondedDevices.isEmpty) {
      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=false\n'
          'actualConnected=false\n'
          'failureStage=no_paired_devices');
      return const ToolResult.fail('No paired devices found. Pair the HC-05 in system settings first.');
    }

    // Prioritized search:
    // 1. Exact normalized "hc-05" (Priority 1)
    // 2. Exact normalized "hc05" (Priority 2)
    // 3. Name containing "hc-05" (Priority 3)
    // 4. Name containing "hc05" (Priority 4)
    // 5. Name containing "stove" (Priority 5)
    // 6. Name containing "sensor" (Priority 6)
    
    BluetoothDevice? targetDevice;
    List<BluetoothDevice> candidates = [];
    int bestScore = 999;

    for (final d in _bondedDevices) {
      final name = d.name.toLowerCase().trim();
      int score = 999;
      if (name == 'hc-05') {
        score = 1;
      } else if (name == 'hc05') {
        score = 2;
      } else if (name.contains('hc-05')) {
        score = 3;
      } else if (name.contains('hc05')) {
        score = 4;
      } else if (name.contains('stove')) {
        score = 5;
      } else if (name.contains('sensor')) {
        score = 6;
      }

      if (score < 999) {
        if (score < bestScore) {
          bestScore = score;
          candidates = [d];
        } else if (score == bestScore) {
          candidates.add(d);
        }
      }
    }

    if (candidates.isEmpty) {
      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=false\n'
          'pairedDeviceFound=false\n'
          'actualConnected=false\n'
          'failureStage=no_matching_device');
      return const ToolResult.fail(
          "I couldn't find the paired HC-05 stove sensor. Please make sure HC-05 is paired and powered on.");
    }

    if (candidates.length > 1) {
      // Prefer exact "HC-05"
      final exactMatchList = candidates.where((d) => d.name.toLowerCase().trim() == 'hc-05').toList();
      if (exactMatchList.length == 1) {
        targetDevice = exactMatchList.first;
      } else {
        debugPrint('[SafeCook BT]\n'
            'eventId=$eventId\n'
            'recognized="connect sensor"\n'
            'intent=connectBluetooth\n'
            'tool=connectBluetooth\n'
            'nativeOperationStarted=false\n'
            'pairedDeviceFound=true\n'
            'actualConnected=false\n'
            'failureStage=ambiguous_matches');
        return const ToolResult.fail(
            "Multiple matching stove sensors found. Please select or identify the stove sensor manually.");
      }
    } else {
      targetDevice = candidates.first;
    }

    final matchedDevice = targetDevice;

    if (BluetoothTestPage.isTesting) {
      // Bypass native socket connection during automated tests
      setState(() {
        _connectedDevice = matchedDevice;
        _connectionStatus = 'Connected';
      });
      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=true\n'
          'targetDevice=${matchedDevice.name}\n'
          'targetAddress=${matchedDevice.address}\n'
          'pairedDeviceFound=true\n'
          'actualConnected=true');
      return const ToolResult.ok('Connected to stove sensor');
    }

    try {
      _connectionCompleter = Completer<bool>();
      await _connectToDevice(matchedDevice);
      
      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=true\n'
          'targetDevice=${matchedDevice.name}\n'
          'targetAddress=${matchedDevice.address}\n'
          'pairedDeviceFound=true\n'
          'nativeMethod=connect');

      final success = await _connectionCompleter!.future.timeout(
        const Duration(seconds: 10), // allow time for connection, discovery, and notification enable
        onTimeout: () => false,
      );
      _connectionCompleter = null;

      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=true\n'
          'targetDevice=${matchedDevice.name}\n'
          'targetAddress=${matchedDevice.address}\n'
          'pairedDeviceFound=true\n'
          'connectionEvent=${success ? "success" : "failed"}\n'
          'actualConnected=$success');

      if (success) {
        return const ToolResult.ok('Connected to stove sensor');
      } else {
        return const ToolResult.fail('Could not establish connection to the stove sensor.');
      }
    } catch (e) {
      _connectionCompleter = null;
      debugPrint('[SafeCook BT]\n'
          'eventId=$eventId\n'
          'recognized="connect sensor"\n'
          'intent=connectBluetooth\n'
          'tool=connectBluetooth\n'
          'nativeOperationStarted=true\n'
          'targetDevice=${matchedDevice.name}\n'
          'targetAddress=${matchedDevice.address}\n'
          'pairedDeviceFound=true\n'
          'connectionEvent=error\n'
          'actualConnected=false\n'
          'failureStage=exception');
      return ToolResult.fail('Connection error: $e');
    }
  }

  Future<ToolResult> disconnectBluetoothFromVoice() async {
    if (_connectedDevice == null) {
      return const ToolResult.fail('Not connected');
    }
    try {
      await _disconnect();
      return const ToolResult.ok('Disconnected');
    } catch (e) {
      return ToolResult.fail('Error disconnecting: $e');
    }
  }

  ToolResult bluetoothStatusResult() {
    if (_connectedDevice != null) {
      return ToolResult.ok('Connected to ${_connectedDeviceName ?? "HC-05"}');
    }
    return const ToolResult.fail('Not connected');
  }
  
  // Sensor Parsing State Variables
  int? _gasValue;
  String? _distanceValue;
  String _gasStatus = 'Unknown';
  String _distanceStatus = 'Unknown';
  String _incomingAccumulator = '';
  String _lastSafetyState = 'STANDBY';
  final List<SafetyEvent> _safetyHistory = [];
  final List<SensorDataPoint> _gasChartData = [];
  final List<SensorDataPoint> _distChartData = [];
  
  // Cooking Session State Variables
  bool _isCookingActive = false;
  bool _showSessionSummary = false;
  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;
  int? _sessionMaxGas;
  double? _sessionMinDistance;
  int _sessionCautionCount = 0;
  int _sessionGasAlertCount = 0;
  int _sessionDistanceAlertCount = 0;
  int _sessionCriticalCount = 0;
  String _sessionFinalSafetyState = 'STANDBY';
  final List<SafetyEvent> _sessionSafetyHistory = [];

  Duration get sessionDuration => _sessionDuration;
  int? get sessionMaxGas => _sessionMaxGas;
  double? get sessionMinDistance => _sessionMinDistance;
  int get sessionCautionCount => _sessionCautionCount;
  int get sessionGasAlertCount => _sessionGasAlertCount;
  int get sessionDistanceAlertCount => _sessionDistanceAlertCount;
  int get sessionCriticalCount => _sessionCriticalCount;
  String get sessionFinalState => _sessionFinalSafetyState;
  List<SafetyEvent> get sessionSafetyHistory => _sessionSafetyHistory;

  // Voice Assistant variables for Home Screen
  String _assistantState = 'idle'; // 'idle', 'listening', 'processing'
  String _userSpokenText = '';
  String _assistantReplyText = '';
  int _consecutiveSilenceTurns = 0;
  final SpeechService _speechService = SpeechService();
  final VoiceAssistantService _assistantService = VoiceAssistantService();
  final VoiceService _voiceService = VoiceService();
  
  // Custom colors for status UI
  static const Color _greenAccent = Color(0xFF10B981);
  static const Color _greenBg = Color(0x2610B981); // 15% opacity
  static const Color _greenBorder = Color(0x8010B981); // 50% opacity
  
  static const Color _redAccent = Color(0xFFEF4444);
  static const Color _redBg = Color(0x26EF4444); // 15% opacity
  static const Color _redBorder = Color(0x80EF4444); // 50% opacity

  static const Color _amberAccent = Color(0xFFF59E0B);
  static const Color _amberBg = Color(0x26F59E0B); // 15% opacity
  static const Color _amberBorder = Color(0x80F59E0B); // 50% opacity
  
  Color _gasStatusColor = Colors.white54;
  Color _distanceStatusColor = Colors.white54;
  
  @override
  void initState() {
    super.initState();
    _resetDashboard();
    if (!BluetoothTestPage.isTesting) {
      _initBluetooth();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _voiceService.speak("Welcome to SafeCook. Say Hello SafeCook when you're ready.");
        _startWakeWordDetection();
      });
    }
  }
  
  void _resetDashboard() {
    _gasValue = null;
    _distanceValue = null;
    _gasStatus = 'Unknown';
    _distanceStatus = 'Unknown';
    _gasStatusColor = Colors.white54;
    _distanceStatusColor = Colors.white54;
    _incomingAccumulator = '';
    _lastSafetyState = 'STANDBY';
    _gasChartData.clear();
    _distChartData.clear();
    // Do NOT clear or reset session variables on Bluetooth reconnect,
    // only when a new cooking session starts.
  }

  String _getCombinedStatus() {
    if (_gasValue == null || _distanceValue == null) {
      return 'STANDBY';
    }

    final isGasCritical = _gasStatus == 'Critical';
    final isGasWarning = _gasStatus == 'Warning';
    final isDistVeryClose = _distanceStatus == 'Very Close';
    final isDistClose = _distanceStatus == 'Close';

    if (isGasCritical && isDistVeryClose) {
      return 'CRITICAL';
    } else if (isGasCritical) {
      return 'GAS ALERT';
    } else if (isDistVeryClose) {
      return 'DISTANCE ALERT';
    } else if (isGasWarning || isDistClose) {
      return 'CAUTION';
    } else {
      return 'SAFE';
    }
  }

  Color _getCombinedStatusColor() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redAccent;
      case 'CAUTION':
        return _amberAccent;
      case 'SAFE':
        return _greenAccent;
      default:
        return Colors.white38;
    }
  }

  Color _getCombinedStatusBgColor() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBg;
      case 'CAUTION':
        return _amberBg;
      case 'SAFE':
        return _greenBg;
      default:
        return Colors.white10;
    }
  }

  Color _getCombinedStatusBorderColor() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBorder;
      case 'CAUTION':
        return _amberBorder;
      case 'SAFE':
        return _greenBorder;
      default:
        return Colors.white24;
    }
  }

  IconData _getCombinedStatusIcon() {
    final status = _getCombinedStatus();
    switch (status) {
      case 'CRITICAL':
        return Icons.gpp_bad;
      case 'GAS ALERT':
        return Icons.gas_meter;
      case 'DISTANCE ALERT':
        return Icons.warning_amber;
      case 'CAUTION':
        return Icons.shield;
      case 'SAFE':
        return Icons.verified_user;
      default:
        return Icons.security;
    }
  }

  void _checkSafetyTransitions(String newState) {
    if (newState != _lastSafetyState) {
      _log("Safety state changed from $_lastSafetyState to $newState");
      
      final newEvent = SafetyEvent(
        timestamp: DateTime.now(),
        state: newState,
        gasValue: _gasValue,
        distanceValue: _distanceValue,
      );
      setState(() {
        _safetyHistory.insert(0, newEvent);
        if (_safetyHistory.length > 50) {
          _safetyHistory.removeLast();
        }
        if (_isCookingActive) {
          _sessionSafetyHistory.add(newEvent);
          if (newState == 'CAUTION') _sessionCautionCount++;
          if (newState == 'GAS ALERT') _sessionGasAlertCount++;
          if (newState == 'DISTANCE ALERT') _sessionDistanceAlertCount++;
          if (newState == 'CRITICAL') _sessionCriticalCount++;
        }
      });

      if (newState == 'CAUTION' || newState == 'GAS ALERT' || newState == 'DISTANCE ALERT' || newState == 'CRITICAL') {
        _triggerVibrationAndSound(newState);
      }
      _lastSafetyState = newState;
    }
  }

  Future<void> _triggerVibrationAndSound(String state) async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      if (state == 'CRITICAL') {
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 200));
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 200));
        await HapticFeedback.vibrate();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (e) {
      _log("Error triggering alert cues: $e");
    }
  }

  String _getSafetyMessage(String state) {
    switch (state) {
      case 'GAS ALERT':
        return 'High gas level detected; check for possible gas leakage.';
      case 'DISTANCE ALERT':
        return 'Unsafe proximity detected.';
      case 'CRITICAL':
        return 'Both gas and distance conditions are unsafe.';
      case 'CAUTION':
        return 'Elevated risk detected.';
      default:
        return '';
    }
  }

  Widget _buildAlertBanner() {
    final status = _getCombinedStatus();
    if (status == 'SAFE' || status == 'STANDBY') {
      return const SizedBox.shrink();
    }

    final message = _getSafetyMessage(status);
    final color = _getCombinedStatusColor();
    final bgColor = _getCombinedStatusBgColor();
    final borderColor = _getCombinedStatusBorderColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SAFETY ALERT: $status',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearSafetyHistory() {
    setState(() {
      _safetyHistory.clear();
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Color _getHistoryStateColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redAccent;
      case 'CAUTION':
        return _amberAccent;
      case 'SAFE':
        return _greenAccent;
      default:
        return Colors.white54;
    }
  }

  Color _getHistoryStateBgColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBg;
      case 'CAUTION':
        return _amberBg;
      case 'SAFE':
        return _greenBg;
      default:
        return Colors.white10;
    }
  }

  Color _getHistoryStateBorderColor(String state) {
    switch (state) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        return _redBorder;
      case 'CAUTION':
        return _amberBorder;
      case 'SAFE':
        return _greenBorder;
      default:
        return Colors.white24;
    }
  }

  Widget _buildSafetyHistory() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SAFETY EVENT HISTORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                  letterSpacing: 1,
                ),
              ),
              if (_safetyHistory.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearSafetyHistory,
                  icon: const Icon(Icons.clear_all, size: 16, color: Colors.white54),
                  label: const Text('Clear History', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: _safetyHistory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'No events logged yet.',
                        style: TextStyle(color: Colors.white30, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _safetyHistory.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final event = _safetyHistory[index];
                      final stateColor = _getHistoryStateColor(event.state);
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                        child: Row(
                          children: [
                            Text(
                              _formatTime(event.timestamp),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getHistoryStateBgColor(event.state),
                                border: Border.all(color: _getHistoryStateBorderColor(event.state)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                event.state,
                                style: TextStyle(
                                  color: stateColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Gas: ${event.gasValue ?? '--'} | Dist: ${event.distanceValue ?? '--'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _startCookingSession() {
    _sessionTimer?.cancel();
    setState(() {
      _isCookingActive = true;
      _showSessionSummary = false;
      _sessionDuration = Duration.zero;
      _sessionMaxGas = null;
      _sessionMinDistance = null;
      _sessionCautionCount = 0;
      _sessionGasAlertCount = 0;
      _sessionDistanceAlertCount = 0;
      _sessionCriticalCount = 0;
      _sessionFinalSafetyState = 'STANDBY';
      _sessionSafetyHistory.clear();
    });

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _sessionDuration = Duration(seconds: timer.tick);
        });
      }
    });
  }

  void _endCookingSession() {
    _sessionTimer?.cancel();
    setState(() {
      _isCookingActive = false;
      _showSessionSummary = true;
      _sessionFinalSafetyState = _getCombinedStatus();
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _buildCookingSessionControl() {
    final formatDuration = _formatDuration(_sessionDuration);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'COOKING SESSION MODE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_isCookingActive) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.restaurant, color: Color(0xFF38BDF8), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'COOKING SESSION ACTIVE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formatDuration,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _endCookingSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.stop),
                      label: const Text('END SESSION', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: _startCookingSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('START COOKING', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                  if (_showSessionSummary) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(Icons.assessment, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'SESSION SUMMARY',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryItem('Duration', formatDuration),
                    _buildSummaryItem('Maximum Gas', _sessionMaxGas != null ? '$_sessionMaxGas' : 'N/A'),
                    _buildSummaryItem('Minimum Distance', _sessionMinDistance != null ? '${_sessionMinDistance!.toStringAsFixed(2)} cm' : 'N/A'),
                    _buildSummaryItem('Total Alerts', '${_sessionCautionCount + _sessionGasAlertCount + _sessionDistanceAlertCount}'),
                    _buildSummaryItem('Critical Events', '$_sessionCriticalCount'),
                    _buildSummaryItem('Final Safety State', _sessionFinalSafetyState, color: _getHistoryStateColor(_sessionFinalSafetyState)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _addGasChartData(double value) {
    setState(() {
      _gasChartData.add(SensorDataPoint(timestamp: DateTime.now(), value: value));
      if (_gasChartData.length > 60) {
        _gasChartData.removeAt(0);
      }
    });
  }

  void _addDistChartData(double value) {
    setState(() {
      _distChartData.add(SensorDataPoint(timestamp: DateTime.now(), value: value));
      if (_distChartData.length > 60) {
        _distChartData.removeAt(0);
      }
    });
  }

  Widget _buildLiveTrends() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE SENSOR TRENDS (LAST 60S)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gas Trend (Raw)',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          width: double.infinity,
                          child: _gasChartData.isEmpty
                              ? const Center(
                                  child: Text('No data yet', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                )
                              : CustomPaint(
                                  painter: MiniLineChartPainter(
                                    data: _gasChartData,
                                    lineColor: const Color(0xFF38BDF8),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Distance Trend (cm)',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          width: double.infinity,
                          child: _distChartData.isEmpty
                              ? const Center(
                                  child: Text('No data yet', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                )
                              : CustomPaint(
                                  painter: MiniLineChartPainter(
                                    data: _distChartData,
                                    lineColor: const Color(0xFF10B981),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _log(String message) {
    debugPrint("[SafeCook Classic Debug] $message");
    if (mounted) {
      setState(() {
        _consoleText += "[DEBUG] $message\n";
        if (_consoleText.length > 8000) {
          _consoleText = _consoleText.substring(_consoleText.length - 4000);
        }
      });
      // Scroll to bottom when logging diagnostic messages
      Timer(const Duration(milliseconds: 50), _scrollToBottom);
    }
  }
  
  void _startEventChannelListener() {
    _eventChannelSub = _eventChannel.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        final event = data['event'] as String?;
        final value = data['value'];
        
        switch (event) {
          case 'status':
            final statusVal = value as String?;
            _log('[SafeCook BLE] status: $statusVal');
            if (statusVal == 'connecting') {
              setState(() {
                _connectionStatus = 'Connecting...';
                _isConnecting = true;
              });
            } else if (statusVal == 'connected') {
              setState(() {
                _connectionStatus = 'Connected';
                _isConnecting = false;
                _connectedDevice = _bondedDevices.firstWhere(
                  (d) => d.address == _connectedDeviceAddress,
                  orElse: () => BluetoothDevice(name: _connectedDeviceName ?? 'HC-05', address: _connectedDeviceAddress ?? '', bondState: 'bonded'),
                );
              });
            } else if (statusVal == 'services_discovered') {
              setState(() {
                _connectionStatus = 'Connected';
              });
            } else if (statusVal == 'notifications_enabled') {
              setState(() {
                _connectionStatus = 'Connected';
              });
              if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
                _connectionCompleter!.complete(true);
              }
            } else if (statusVal == 'disconnected') {
              _handleDisconnect();
              if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
                _connectionCompleter!.complete(false);
              }
            }
            break;
            
          case 'read':
            final bytes = value as Uint8List?;
            if (bytes != null) {
              debugPrint('[SafeCook BLE] RX bytes: ${bytes.length}');
              
              final text = utf8.decode(bytes, allowMalformed: true);
              // Phase 0 perf fix: accumulate data without triggering setState
              // on every BLE packet.  Only setState when sensor parsing changes
              // meaningful display state (_parseSensorData already calls setState).
              if (mounted) {
                _consoleText += text;
                if (_consoleText.length > 8000) {
                  _consoleText = _consoleText.substring(_consoleText.length - 4000);
                }
                _incomingAccumulator += text;
                if (_incomingAccumulator.length > 4096) {
                  _incomingAccumulator = _incomingAccumulator.substring(_incomingAccumulator.length - 1024);
                }
                
                while (_incomingAccumulator.contains('\n')) {
                  final index = _incomingAccumulator.indexOf('\n');
                  final line = _incomingAccumulator.substring(0, index).trim();
                  _incomingAccumulator = _incomingAccumulator.substring(index + 1);
                  if (line.isNotEmpty) {
                    _parseSensorData(line);
                  }
                }
              }
            }
            break;
            
          case 'error':
            final errorMsg = value as String?;
            _log('[SafeCook BLE] Error: $errorMsg');
            if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
              _connectionCompleter!.complete(false);
            }
            break;
        }
      }
    }, onError: (err) {
      _log("[SafeCook Native BT] Stream error: $err");
    });
  }

  Future<void> _initBluetooth() async {
    _log("Initializing native Bluetooth channels...");
    try {
      final isEnabled = await _methodChannel.invokeMethod<bool>('getBluetoothState') ?? false;
      if (mounted) {
        setState(() {
          _adapterState = isEnabled ? ClassicAdapterState.on : ClassicAdapterState.off;
        });
      }
      _startEventChannelListener();
    } catch (e) {
      _log("Error during Bluetooth initialization: $e");
    }
    
    // Fetch bonded list
    _getBondedDevices();
  }
  
  Future<void> _getBondedDevices() async {
    try {
      final isEnabled = await _methodChannel.invokeMethod<bool>('getBluetoothState') ?? false;
      _log("[SafeCook BT DEBUG] Bluetooth enabled: $isEnabled");
      
      final List? devicesList = await _methodChannel.invokeMethod<List>('getBondedDevices');
      final devices = (devicesList ?? [])
          .map((d) => BluetoothDevice.fromMap(d as Map))
          .toList();
      
      _log("[SafeCook BT DEBUG] getPairedDevices returned: ${devices.length}");
      
      for (var device in devices) {
        _log("[SafeCook BT DEBUG] name=${device.name}");
        _log("[SafeCook BT DEBUG] displayName=${device.name}");
        _log("[SafeCook BT DEBUG] address=${device.address}");
        _log("[SafeCook BT DEBUG] bondState=${device.bondState}");
      }
      
      if (mounted) {
        setState(() {
          _bondedDevices = devices;
        });
      }
    } catch (e) {
      _log("[SafeCook BT DEBUG] Error fetching paired devices: $e");
    }
  }
  
  void _startScan() {
    setState(() {
      _isScanning = true;
    });
    // Classic scanning/discovery is not utilized; we guide the user to system settings
    _showSnackBar("Please pair your HC-05 device in system settings first.");
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    });
  }
  
  void _stopScan() {
    setState(() {
      _isScanning = false;
    });
  }
  
  void _parseSensorData(String line) {
    try {
      // Expected formats:
      // GAS:263,DIST:78.50
      // GAS:263,DIST:NO_ECHO
      final regExp = RegExp(r'GAS:(\d+),DIST:(NO_ECHO|[\d\.]+)');
      final match = regExp.firstMatch(line);
      
      if (match != null) {
        _sensorFreshnessTimer?.cancel();
        _sensorFreshnessTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _gasValue = null;
              _distanceValue = null;
              _gasStatus = 'Unknown';
              _distanceStatus = 'Unknown';
            });
            _notifySensorListeners();
          }
        });
        
        final gasStr = match.group(1);
        final distStr = match.group(2);
        
        if (gasStr != null) {
          final val = int.tryParse(gasStr);
          if (val != null) {
            _gasValue = val;
            if (val < kGasNormalMax) {
              _gasStatus = 'Normal';
              _gasStatusColor = _greenAccent;
            } else if (val < kGasWarningMax) {
              _gasStatus = 'Warning';
              _gasStatusColor = _amberAccent;
            } else {
              _gasStatus = 'Critical';
              _gasStatusColor = _redAccent;
            }
            _addGasChartData(val.toDouble());
            if (_isCookingActive) {
              if (_sessionMaxGas == null || val > _sessionMaxGas!) {
                _sessionMaxGas = val;
              }
            }
          }
        }
        
        if (distStr != null) {
          if (distStr == 'NO_ECHO') {
            _distanceValue = 'No Echo';
            _distanceStatus = 'No Echo';
            _distanceStatusColor = Colors.white54;
          } else {
            final val = double.tryParse(distStr);
            if (val != null) {
              _distanceValue = '${val.toStringAsFixed(2)} cm';
              if (val > kDistanceSafeMin) {
                _distanceStatus = 'Safe';
                _distanceStatusColor = _greenAccent;
              } else if (val >= kDistanceWarningMin) {
                _distanceStatus = 'Close';
                _distanceStatusColor = _amberAccent;
              } else {
                _distanceStatus = 'Very Close';
                _distanceStatusColor = _redAccent;
              }
              _addDistChartData(val);
              if (_isCookingActive) {
                if (_sessionMinDistance == null || val < _sessionMinDistance!) {
                  _sessionMinDistance = val;
                }
              }
            }
          }
        }
        setState(() {});
        _checkSafetyTransitions(_getCombinedStatus());
        _notifySensorListeners();
      }
    } catch (e) {
      debugPrint("Parsing error: $e");
    }
  }

  @visibleForTesting
  void simulateSensorData(String line) {
    _parseSensorData(line);
  }
  
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) {
      _log("Connection attempt ignored: another connection is already in progress.");
      return;
    }
    
    _stopScan();
    
    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
      _connectedDeviceAddress = device.address;
      _connectedDeviceName = device.name;
      _resetDashboard();
    });
    
    _log("[SafeCook Native BT]");
    _log("Connecting to HC-05");
    
    try {
      await _disconnect();
      await _methodChannel.invokeMethod('connect', {'address': device.address});
    } catch (e) {
      _log("[SafeCook Native BT] Connection error: $e");
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Failed';
          _connectedDevice = null;
          _resetDashboard();
        });
      }
    }
  }
  
  void _handleDisconnect() {
    if (mounted) {
      _sensorFreshnessTimer?.cancel();
      // Phase 0 fix: if a cooking session is active when BT disconnects,
      // end it so the agent state stays consistent.
      if (_isCookingActive) {
        _endCookingSession();
        SafeCookAgent().reset();
      }
      setState(() {
        _isConnecting = false;
        _connectedDevice = null;
        _connectionStatus = 'Disconnected';
        _resetDashboard();
      });
      _notifySensorListeners();
    }
  }
  
  Future<void> _disconnect() async {
    _log('Closing BLE GATT connection...');
    try {
      await _methodChannel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint("Error closing connection: $e");
    }
    
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _connectedDevice = null;
        _connectionStatus = 'Disconnected';
        _resetDashboard();
      });
      _notifySensorListeners();
    }
  }
  
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }
  

  
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
  
  @override
  void dispose() {
    _sensorFreshnessTimer?.cancel();
    _eventChannelSub?.cancel();
    _scrollController.dispose();
    _sessionTimer?.cancel();
    _voiceService.stop();
    _speechService.stopListening();
    super.dispose();
  }

  final WakeWordService _wakeWordService = WakeWordService();

  Future<void> _startWakeWordDetection() async {
    await _speechService.initialize();
    await _wakeWordService.startWakeWordDetection(
      onWakeDetected: () async {
        if (mounted) {
          setState(() {
            _assistantState = 'processing';
            _assistantReplyText = 'Hello! What would you like to do?';
          });
        }
        
        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          _startVoiceCommandListening();
        });
        
        await _voiceService.speak("Hello! What would you like to do?");
      },
    );
  }

  Future<void> _startVoiceCommandListening() async {
    if (mounted) {
      setState(() {
        _assistantState = 'listening';
        _userSpokenText = '';
      });
    }

    await _speechService.startListening(
      onResult: (text) {
        if (mounted) {
          setState(() {
            _userSpokenText = text;
          });
        }
      },
      onError: (err) async {
        _consecutiveSilenceTurns++;
        final maxSilence = _isCookingActive ? 3 : 1;
        if (_consecutiveSilenceTurns >= maxSilence) {
          _consecutiveSilenceTurns = 0;
          if (mounted) {
            setState(() {
              _assistantState = 'idle';
              _assistantReplyText = "I'll wait here. Say Hello SafeCook when you need me.";
            });
          }
          await _voiceService.speak("I'll wait here. Say Hello SafeCook when you need me.");
          _startWakeWordDetection();
        } else {
          _startVoiceCommandListening();
        }
      },
      onDoneListening: () async {
        final query = _userSpokenText.trim();
        _userSpokenText = ''; // Clear immediately to prevent duplicate execution

        if (query.isEmpty) {
          final maxSilence = _isCookingActive ? 3 : 1;
          _consecutiveSilenceTurns++;
          if (_consecutiveSilenceTurns >= maxSilence) {
            _consecutiveSilenceTurns = 0;
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
                _assistantReplyText = "I'll wait here. Say Hello SafeCook when you need me.";
              });
            }
            await _voiceService.speak("I'll wait here. Say Hello SafeCook when you need me.");
            _startWakeWordDetection();
          } else {
            _startVoiceCommandListening();
          }
          return;
        }

        _consecutiveSilenceTurns = 0; // Reset silence turns on valid user speech

        if (mounted) {
          setState(() {
            _assistantState = 'processing';
          });
        }

        final eventId = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[SafeCook VOICE]\n'
            'eventId=$eventId\n'
            'recognized="$query"\n'
            'processingStarted=true');

        final voiceContext = VoiceAssistantContext(
          recipe: null,
          currentStepIndex: 0,
          totalSteps: 0,
          gasValue: _gasValue,
          distanceValue: _distanceValue,
          safetyState: _getCombinedStatus(),
          sessionDuration: _sessionDuration,
          isCookingActive: _isCookingActive,
          isBluetoothConnected: _connectedDevice != null,
        );

        final actions = VoiceAssistantActions(
          onNextStep: () async => const ToolResult.fail('Not in cooking mode'),
          onPreviousStep: () async => const ToolResult.fail('Not in cooking mode'),
          onRepeatStep: () async => const ToolResult.fail('Not in cooking mode'),
          onGoToStep: (_) async => const ToolResult.fail('Not in cooking mode'),
          onEndCooking: () async {
            _endCookingSession();
            return const ToolResult.ok('Session ended');
          },
          onStartCooking: (recipe) async {
            if (!mounted) return const ToolResult.fail('Widget not mounted');
            final selected = SafeCookAgent().selectedRecipe ?? recipe;
            _wakeWordService.stopWakeWordDetection();
            _speechService.stopListening();
            _startCookingSession();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CookingGuidanceScreen(
                  recipe: selected,
                  homeState: this,
                  startSilently: true,
                ),
              ),
            ).then((_) {
              if (mounted) _startWakeWordDetection();
            });
            return const ToolResult.ok('Navigation to cooking screen initiated');
          },
          onConnectBluetooth: connectBluetoothFromVoice,
          onDisconnectBluetooth: disconnectBluetoothFromVoice,
          onBluetoothStatus: bluetoothStatusResult,
        );

        final reply = await _assistantService.processVoiceCommand(
          query,
          voiceContext,
          actions,
        );

        if (mounted) {
          setState(() {
            _assistantReplyText = reply;
          });
        }

        final csNow = SafeCookAgent().conversationState;
        final isSelectingOrCooking = csNow == ConversationState.selectingRecipe ||
                                     csNow == ConversationState.confirmingStart ||
                                     csNow == ConversationState.confirmingEnd ||
                                     csNow == ConversationState.awaitingReadyConfirm ||
                                     csNow == ConversationState.cooking;
        
        _voiceService.setCompletionCallback(() {
          _voiceService.setCompletionCallback(null);
          if (SafeCookAgent().conversationState == ConversationState.idle) {
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
              });
            }
            _startWakeWordDetection();
          } else if (isSelectingOrCooking && mounted) {
            _startVoiceCommandListening();
          } else {
            if (mounted) {
              setState(() {
                _assistantState = 'idle';
              });
            }
            _startWakeWordDetection();
          }
        });

        await _voiceService.speak(reply);
      },
    );
  }

  Future<void> _startVoiceListening() async {
    await _wakeWordService.stopWakeWordDetection();
    await _startVoiceCommandListening();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectedDevice != null;
    
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text(
              'SafeCook',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          if (!_showPaired)
            IconButton(
              icon: Icon(_isScanning ? Icons.stop : Icons.search),
              onPressed: _isScanning ? _stopScan : _startScan,
              tooltip: _isScanning ? 'Stop Scan' : 'Scan for Devices',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _getBondedDevices,
              tooltip: 'Refresh Paired List',
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          if (_assistantState == 'listening') {
            _speechService.stopListening();
          } else {
            _startVoiceListening();
          }
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildAlertBanner(),
  
               // 0. Highly Accessible Conversational UI Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Semantics(
                  button: true,
                  label: 'Double tap anywhere to talk to SafeCook, or tap here to start voice assistant.',
                  child: Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: _assistantState == 'listening'
                            ? Colors.redAccent
                            : const Color(0xFF38BDF8),
                        width: 1.5,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        if (_assistantState == 'listening') {
                          _speechService.stopListening();
                        } else {
                          _startVoiceListening();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            const Icon(Icons.shield, color: Color(0xFF10B981), size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'SAFECOOK',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 28,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                            const Text(
                              'Smart Cooking Safety Assistant',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Double tap screen or say "Hello SafeCook" to speak.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 20),
                            
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _assistantState == 'listening'
                                        ? Icons.mic
                                        : _assistantState == 'processing'
                                            ? Icons.query_stats
                                            : Icons.mic_none,
                                    color: _assistantState == 'listening'
                                        ? Colors.redAccent
                                        : _assistantState == 'processing'
                                            ? const Color(0xFF38BDF8)
                                            : Colors.white70,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _assistantState == 'listening'
                                        ? 'LISTENING...'
                                        : _assistantState == 'processing'
                                            ? 'UNDERSTANDING...'
                                            : 'TAP TO TALK',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _assistantState == 'listening'
                                          ? Colors.redAccent
                                          : _assistantState == 'processing'
                                              ? const Color(0xFF38BDF8)
                                              : Colors.white70,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            if (_userSpokenText.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'YOU: ',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF38BDF8), fontSize: 14),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '"$_userSpokenText"',
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_assistantReplyText.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SAFECOOK: ',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 14),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _assistantReplyText,
                                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            
                            const SizedBox(height: 20),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 20),
                            
                            Semantics(
                              button: true,
                              label: 'Start cooking, touch route list',
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final selectedRecipe = await Navigator.push<Recipe>(
                                    context,
                                    MaterialPageRoute(builder: (context) => const RecipeListScreen()),
                                  );
                                  
                                  if (selectedRecipe != null && mounted) {
                                    _startCookingSession();
                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CookingGuidanceScreen(
                                          recipe: selectedRecipe,
                                          homeState: this,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                ),
                                icon: const Icon(Icons.restaurant_menu, size: 22),
                                label: const Text(
                                  'START COOKING (TOUCH)',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
  
              // Bluetooth Settings Expandable Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings_bluetooth, color: Color(0xFF38BDF8)),
                        title: const Text(
                          'Sensor Connection Settings',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        trailing: Icon(
                          _showBluetoothSettings ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white54,
                        ),
                        onTap: () {
                          setState(() {
                            _showBluetoothSettings = !_showBluetoothSettings;
                          });
                          if (_showBluetoothSettings) {
                            _getBondedDevices();
                          }
                        },
                      ),
                      if (_showBluetoothSettings) ...[
                        const Divider(color: Colors.white10, height: 1),
                        // 1. Adapter & Connection Status
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Bluetooth Adapter:',
                                      style: TextStyle(fontSize: 14, color: Colors.white70),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _adapterState == ClassicAdapterState.on ? _greenBg : _redBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _adapterState == ClassicAdapterState.on ? _greenBorder : _redBorder,
                                      ),
                                    ),
                                    child: Text(
                                      _adapterState.name.toUpperCase(),
                                      style: TextStyle(
                                        color: _adapterState == ClassicAdapterState.on ? _greenAccent : _redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Connection Status:',
                                      style: TextStyle(fontSize: 14, color: Colors.white70),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (_connectionStatus == 'Connected' ||
                                              _connectionStatus == 'GATT Connected' ||
                                              _connectionStatus == 'Receiving Data')
                                          ? _greenBg
                                          : (_connectionStatus.startsWith('Connecting') ||
                                                  _connectionStatus == 'Services Discovered' ||
                                                  _connectionStatus == 'Notifications Enabled')
                                              ? _amberBg
                                              : _redBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: (_connectionStatus == 'Connected' ||
                                                _connectionStatus == 'GATT Connected' ||
                                                _connectionStatus == 'Receiving Data')
                                            ? _greenBorder
                                            : _connectionStatus.startsWith('Connecting') ||
                                                _connectionStatus == 'Services Discovered' ||
                                                _connectionStatus == 'Notifications Enabled'
                                                ? _amberBorder
                                                : _redBorder,
                                      ),
                                    ),
                                    child: Text(
                                      _connectionStatus,
                                      style: TextStyle(
                                        color: _connectionStatus == 'Connected' ||
                                                _connectionStatus == 'GATT Connected' ||
                                                _connectionStatus == 'Receiving Data'
                                            ? _greenAccent
                                            : _connectionStatus.startsWith('Connecting') ||
                                                _connectionStatus == 'Services Discovered' ||
                                                _connectionStatus == 'Notifications Enabled'
                                                ? _amberAccent
                                                : _redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isConnected) ...[
                                const SizedBox(height: 16),
                                const Divider(color: Colors.white10, height: 1),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _connectedDeviceName ?? 'HC-05',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _connectedDeviceAddress ?? '',
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _disconnect,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade900,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      icon: const Icon(Icons.link_off, size: 16),
                                      label: const Text('Disconnect'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        // 2. Custom Tabs
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _showPaired = true;
                                  });
                                  _getBondedDevices();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: _showPaired ? const Color(0xFF38BDF8) : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'PAIRED (${_bondedDevices.length})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: _showPaired ? FontWeight.bold : FontWeight.normal,
                                        color: _showPaired ? const Color(0xFF38BDF8) : Colors.white60,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _showPaired = false;
                                  });
                                  _startScan();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: !_showPaired ? const Color(0xFF38BDF8) : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'SCANNED (${_discoveredDevices.length})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: !_showPaired ? FontWeight.bold : FontWeight.normal,
                                        color: !_showPaired ? const Color(0xFF38BDF8) : Colors.white60,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        // 3. Device List
                        _showPaired ? _buildPairedList() : _buildScannedList(),
                      ],
                    ],
                  ),
                ),
              ),
              
              _buildCookingSessionControl(),
              
              // 4. Sensor Dashboard
              _buildDashboard(),
              
              _buildLiveTrends(),
              
              _buildSafetyHistory(),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildDashboard() {
    final status = _getCombinedStatus();
    String explanation;
    switch (status) {
      case 'SAFE':
        explanation = "Cooking conditions look safe.";
        break;
      case 'CAUTION':
        explanation = "Please pay attention to the cooking area.";
        break;
      case 'GAS ALERT':
        explanation = "Gas level is high. Check the cooking area.";
        break;
      case 'DISTANCE ALERT':
        explanation = "The vessel is too close.";
        break;
      case 'CRITICAL':
        explanation = "Immediate attention required.";
        break;
      default:
        explanation = "Sensor standby.";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SAFETY MONITORING DASHBOARD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getCombinedStatusBgColor(),
                      shape: BoxShape.circle,
                      border: Border.all(color: _getCombinedStatusBorderColor()),
                    ),
                    child: Icon(
                      _getCombinedStatusIcon(),
                      color: _getCombinedStatusColor(),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SAFECOOK SAFETY STATUS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _getCombinedStatusColor(),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          explanation,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Gas Card
              Expanded(
                child: Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Gas Level', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            Icon(Icons.gas_meter_outlined, color: Colors.white30, size: 16),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _gasValue != null ? '$_gasValue' : '--',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _gasStatusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _gasStatus,
                              style: TextStyle(color: _gasStatusColor, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Distance Card
              Expanded(
                child: Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Distance', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            Icon(Icons.settings_input_antenna_outlined, color: Colors.white30, size: 16),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _distanceValue ?? '--',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _distanceStatusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                             const SizedBox(width: 6),
                             Flexible(
                               child: Text(
                                 _distanceStatus,
                                 style: TextStyle(color: _distanceStatusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPairedList() {
    if (_bondedDevices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              const Text(
                'No paired devices found',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              const Text(
                'Make sure the HC-05 is paired in your system settings, or switch to "Scanned Devices" to search for it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _getBondedDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Paired List'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _bondedDevices.length,
      itemBuilder: (context, index) {
        final device = _bondedDevices[index];
        return _buildDeviceItem(device);
      },
    );
  }

  Widget _buildScannedList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_searching, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text(
              'BLE Mode',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'HC-05 V2.3 LE is a BLE device. Use the Paired Devices tab to connect.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceItem(BluetoothDevice device) {
    final isConnecting = _connectionStatus == 'Connecting...' && _connectedDeviceAddress == device.address;
    final isConnected = _connectedDevice != null && _connectedDeviceAddress == device.address;
    
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x260EA5E9), // 15% opacity
          child: Icon(Icons.bluetooth, color: Color(0xFF38BDF8)),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                device.address,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'PAIRED',
                style: TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        trailing: isConnected
            ? const Icon(Icons.check_circle, color: _greenAccent)
            : isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                  )
                : ElevatedButton(
                    onPressed: _isConnecting ? null : () => _connectToDevice(device),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
      ),
    );
  }


}

class SLocationSizeBox extends StatelessWidget {
  final String title;
  const SLocationSizeBox({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
          letterSpacing: 1,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
