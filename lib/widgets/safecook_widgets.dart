import 'package:flutter/material.dart';
import '../theme/safecook_theme.dart';

/// Shared reusable widgets for the SafeCook UI.
/// All screens should consume these instead of reinventing layout primitives.

// ─────────────────────────────────────────────────────────────────────────────
// Section header with overline label
// ─────────────────────────────────────────────────────────────────────────────
class SCSection extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SCSection({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(), style: SafeCookTextStyles.label),
          ?trailing,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standard SafeCook Card wrapper
// ─────────────────────────────────────────────────────────────────────────────
class SCCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double borderRadius;
  final VoidCallback? onTap;

  const SCCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.borderRadius = SafeCookRadius.md,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? SafeCookColors.surfaceElevated;
    final effectiveBorder = borderColor ?? SafeCookColors.border;

    final container = Container(
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: effectiveBorder, width: 0.5),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: effectiveColor,
          child: InkWell(
            onTap: onTap,
            child: container,
          ),
        ),
      );
    }

    return container;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Safety status pill / badge
// ─────────────────────────────────────────────────────────────────────────────
class SafetyStatusBadge extends StatelessWidget {
  final String status;

  const SafetyStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    final Color border;

    switch (status) {
      case 'CRITICAL':
      case 'GAS ALERT':
      case 'DISTANCE ALERT':
        fg = SafeCookColors.danger;
        bg = SafeCookColors.dangerBg;
        border = SafeCookColors.dangerBorder;
      case 'CAUTION':
        fg = SafeCookColors.caution;
        bg = SafeCookColors.cautionBg;
        border = SafeCookColors.cautionBorder;
      case 'SAFE':
        fg = SafeCookColors.safe;
        bg = SafeCookColors.safeBg;
        border = SafeCookColors.safeBorder;
      default:
        fg = SafeCookColors.textSecondary;
        bg = SafeCookColors.surfaceHighest;
        border = SafeCookColors.border;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SafeCookRadius.full),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontFamily: 'Nunito',
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Large safety status card used on Home and CookingGuidance
// ─────────────────────────────────────────────────────────────────────────────
class SafetyStatusCard extends StatelessWidget {
  final String status;
  final String explanation;
  final bool compact;

  const SafetyStatusCard({
    super.key,
    required this.status,
    required this.explanation,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    final Color border;
    final IconData icon;

    switch (status) {
      case 'CRITICAL':
        fg = SafeCookColors.danger;
        bg = SafeCookColors.dangerBg;
        border = SafeCookColors.dangerBorder;
        icon = Icons.gpp_bad_rounded;
      case 'GAS ALERT':
        fg = SafeCookColors.danger;
        bg = SafeCookColors.dangerBg;
        border = SafeCookColors.dangerBorder;
        icon = Icons.gas_meter_rounded;
      case 'DISTANCE ALERT':
        fg = SafeCookColors.danger;
        bg = SafeCookColors.dangerBg;
        border = SafeCookColors.dangerBorder;
        icon = Icons.warning_amber_rounded;
      case 'CAUTION':
        fg = SafeCookColors.caution;
        bg = SafeCookColors.cautionBg;
        border = SafeCookColors.cautionBorder;
        icon = Icons.shield_outlined;
      case 'SAFE':
        fg = SafeCookColors.safe;
        bg = SafeCookColors.safeBg;
        border = SafeCookColors.safeBorder;
        icon = Icons.verified_user_rounded;
      default:
        fg = SafeCookColors.textSecondary;
        bg = SafeCookColors.surfaceHighest;
        border = SafeCookColors.border;
        icon = Icons.sensors_off_rounded;
    }

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SafeCookRadius.sm),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 6),
            Text(
              status,
              style: TextStyle(
                fontFamily: 'Nunito',
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SafeCookRadius.md),
        border: Border.all(color: border, width: 1.0),
      ),
      padding: const EdgeInsets.all(SafeCookSpacing.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fg, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SAFETY STATUS',
                  style: SafeCookTextStyles.label,
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: fg,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(explanation, style: SafeCookTextStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor reading mini-card (Gas / Distance)
// ─────────────────────────────────────────────────────────────────────────────
class SensorTile extends StatelessWidget {
  final String label;
  final String value;
  final String statusLabel;
  final Color statusColor;
  final IconData icon;

  const SensorTile({
    super.key,
    required this.label,
    required this.value,
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SCCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: SafeCookTextStyles.label),
              Icon(icon, color: SafeCookColors.textMuted, size: 16),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: SafeCookTextStyles.sensorValue),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice assistant status widget
// ─────────────────────────────────────────────────────────────────────────────
class VoiceStatusBar extends StatelessWidget {
  final String assistantState; // 'idle' | 'listening' | 'processing'
  final VoidCallback onTap;

  const VoiceStatusBar({
    super.key,
    required this.assistantState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isListening = assistantState == 'listening';
    final bool isProcessing = assistantState == 'processing';

    final Color fg = isListening
        ? SafeCookColors.danger
        : isProcessing
        ? SafeCookColors.primaryLight
        : SafeCookColors.textSecondary;

    final String label = isListening
        ? 'Listening…'
        : isProcessing
        ? 'Understanding…'
        : 'Tap to talk';

    final IconData icon = isListening
        ? Icons.mic_rounded
        : isProcessing
        ? Icons.auto_fix_high_rounded
        : Icons.mic_none_rounded;

    return Semantics(
      button: true,
      label: isListening
          ? 'Stop listening'
          : 'Tap to ask SafeCook a question by voice',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isListening
                ? SafeCookColors.dangerBg
                : SafeCookColors.surfaceElevated,
            borderRadius: BorderRadius.circular(SafeCookRadius.sm),
            border: Border.all(
              color: isListening
                  ? SafeCookColors.dangerBorder
                  : isProcessing
                  ? SafeCookColors.primaryLight.withValues(alpha: 0.4)
                  : SafeCookColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: fg,
                  letterSpacing: 0.3,
                ),
              ),
              if (isListening || isProcessing) ...[
                const SizedBox(width: 10),
                _PulsingDot(color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversation bubble row (YOU / SAFECOOK)
// ─────────────────────────────────────────────────────────────────────────────
class ConversationLine extends StatelessWidget {
  final String speaker; // 'YOU' or 'SAFECOOK'
  final String text;

  const ConversationLine({
    super.key,
    required this.speaker,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUser = speaker == 'YOU';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$speaker: ',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              color: isUser
                  ? SafeCookColors.primaryLight
                  : SafeCookColors.safe,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              isUser ? '"$text"' : text,
              style: TextStyle(
                fontFamily: 'Nunito',
                color: isUser
                    ? SafeCookColors.textPrimary
                    : SafeCookColors.textSecondary,
                fontSize: 13,
                fontStyle: isUser ? FontStyle.italic : FontStyle.normal,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alert banner for safety states (non-safe)
// ─────────────────────────────────────────────────────────────────────────────
class SafetyAlertBanner extends StatelessWidget {
  final String status;
  final String message;

  const SafetyAlertBanner({
    super.key,
    required this.status,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCritical = status == 'CRITICAL';
    final Color fg = isCritical ? SafeCookColors.danger : SafeCookColors.caution;
    final Color bg = isCritical ? SafeCookColors.dangerBg : SafeCookColors.cautionBg;
    final Color border = isCritical ? SafeCookColors.dangerBorder : SafeCookColors.cautionBorder;
    final IconData icon = isCritical ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠ SAFETY ALERT: $status',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    color: SafeCookColors.textPrimary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state widget
// ─────────────────────────────────────────────────────────────────────────────
class SCEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const SCEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SafeCookSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SafeCookColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: SafeCookColors.border),
              ),
              child: Icon(icon, size: 36, color: SafeCookColors.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: SafeCookTextStyles.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: SafeCookTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row stat item for summary/report screens
// ─────────────────────────────────────────────────────────────────────────────
class StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: SafeCookTextStyles.bodyMedium),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              color: valueColor ?? SafeCookColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connectivity pill for Bluetooth status
// ─────────────────────────────────────────────────────────────────────────────
class ConnectivityPill extends StatelessWidget {
  final bool connected;
  final String? deviceName;

  const ConnectivityPill({super.key, required this.connected, this.deviceName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: connected ? SafeCookColors.safeBg : SafeCookColors.surfaceHighest,
        borderRadius: BorderRadius.circular(SafeCookRadius.full),
        border: Border.all(
          color: connected ? SafeCookColors.safeBorder : SafeCookColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: connected
                ? SafeCookColors.safe
                : SafeCookColors.textSecondary,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            connected ? (deviceName ?? 'Sensor') : 'Not Connected',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: connected
                  ? SafeCookColors.safe
                  : SafeCookColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
