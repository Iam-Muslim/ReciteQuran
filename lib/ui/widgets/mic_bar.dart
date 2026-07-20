import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';

/// Bottom floating action bar — the primary interaction point.
///
/// Design principles:
/// - Large, obvious button (64px) — easy for elderly users
/// - Single primary action visible at a time (Record or Pause)
/// - Pulsing glow when recording — clear visual feedback
/// - Floating pill shape — modern & non-intrusive
class BottomActionBar extends StatefulWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final bool isAutoScrolling;
  final ThemeColors c;
  final VoidCallback onMic;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onSettingsTap;
  final bool isVoiceSearching;

  const BottomActionBar({
    super.key,
    required this.isRecording,
    required this.isLoadingEngine,
    required this.isAutoScrolling,
    required this.c,
    required this.onMic,
    required this.onToggleAutoScroll,
    required this.onSettingsTap, // Kept for signature compatibility, unused here as settings moved
    this.isVoiceSearching = false,
  });

  @override
  State<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<BottomActionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  // _pulseAnimation is currently unused
  // late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    /*
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    */

    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BottomActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = AppState.instance;

    // Choose the correct button based on current state
    Widget actionButton;
    if (widget.isAutoScrolling) {
      // ── AutoScroll Pause Button ──
      actionButton = _buildFloatingButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onToggleAutoScroll();
        },
        gradient: LinearGradient(
          colors: [c.gold, c.gold.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shadowColor: c.gold.withValues(alpha: 0.3),
        icon: Icons.pause_rounded,
        label: app.isArabic ? 'إيقاف' : 'Pause',
      );
    } else {
      // ── Record / Stop Button ──
      final Color buttonColor = widget.isRecording ? c.red : c.green;
      actionButton = _buildFloatingButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onMic();
        },
        gradient: LinearGradient(
          colors: [buttonColor, buttonColor.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shadowColor: buttonColor.withValues(alpha: 0.25),
        shadowBlur: 16,
        shadowSpread: 2,
        icon: widget.isLoadingEngine
            ? null
            : (widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded),
        isLoading: widget.isLoadingEngine,
        label: widget.isRecording
            ? (app.isArabic ? 'انتهي' : 'End')
            : (app.isArabic ? 'اتلو' : 'Recite'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, right: 24, left: 24),
      child: Align(alignment: Alignment.bottomLeft, child: actionButton),
    );
  }

  /// Builds a consistent floating action button with label underneath.
  Widget _buildFloatingButton({
    required VoidCallback onTap,
    required Gradient gradient,
    required Color shadowColor,
    double shadowBlur = 16,
    double shadowSpread = 2,
    IconData? icon,
    bool isLoading = false,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: shadowBlur,
              spreadRadius: shadowSpread,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
