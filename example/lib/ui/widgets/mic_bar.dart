import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';

/// Bottom floating action bar — primary interaction point for Recite, Stop, and AutoScroll.
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
    this.isLoadingEngine = false,
    required this.isAutoScrolling,
    required this.c,
    required this.onMic,
    required this.onToggleAutoScroll,
    required this.onSettingsTap,
    this.isVoiceSearching = false,
  });

  @override
  State<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<BottomActionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

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

    Widget actionButton;
    if (widget.isAutoScrolling) {
      // ── AutoScroll Pause Button ──
      actionButton = _buildModernButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onToggleAutoScroll();
        },
        baseColor: c.gold,
        icon: Icons.pause_rounded,
        label: app.isArabic ? 'إيقاف' : 'Pause',
      );
    } else {
      // ── Record / Stop Button ──
      final Color buttonColor = widget.isRecording ? c.red : c.green;
      actionButton = _buildModernButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onMic();
        },
        baseColor: buttonColor,
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

  Widget _buildModernButton({
    required VoidCallback onTap,
    required Color baseColor,
    IconData? icon,
    bool isLoading = false,
    required String label,
  }) {
    final app = AppState.instance;
    final c = widget.c;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: baseColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(baseColor),
                    ),
                  )
                : (icon != null
                    ? Icon(icon, color: baseColor, size: 28)
                    : const SizedBox.shrink()),
            Positioned(
              bottom: 2,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: app.isArabic ? 'HafsSmart' : null,
                  color: c.text,
                  fontSize: app.isArabic ? 13 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
