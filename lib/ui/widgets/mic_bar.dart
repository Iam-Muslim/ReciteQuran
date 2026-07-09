import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';

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
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, right: 24, left: 24),
      child: Align(
        alignment:
            Alignment.bottomLeft, // Force physical left regardless of RTL
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Record / Stop Button ──────────────────────────────────────────────
            if (!widget.isAutoScrolling) // Show record button if not reading
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onMic();
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final double pulseValue = widget.isRecording ? _pulseAnimation.value : 0.0;
                    final double scale = 1.0 + (pulseValue * 0.08);
                    final double glowSpread = 2 + (pulseValue * 6);
                    final double glowBlur = 16 + (pulseValue * 12);
                    final double glowAlpha = 0.3 + (pulseValue * 0.2);

                    return Transform.scale(
                      scale: scale,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: widget.isRecording
                              ? LinearGradient(
                                      colors: [c.red, c.red.withValues(alpha: 0.8)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : LinearGradient(
                                      colors: [c.green, c.green.withValues(alpha: 0.8)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: (widget.isRecording ? c.red : c.green)
                                  .withValues(alpha: glowAlpha),
                              blurRadius: glowBlur,
                              spreadRadius: glowSpread,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: widget.isLoadingEngine
                            ? const Padding(
                                padding: EdgeInsets.all(18.0),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                widget.isRecording
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    );
                  },
                ),
              )
            else
              // Stop button for AutoScroll
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onToggleAutoScroll();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.gold, c.gold.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: c.gold.withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.pause_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

