import 'package:flutter/material.dart';
import '../../state/app_state.dart';

class BottomActionBar extends StatefulWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final bool isAutoScrolling;
  final ThemeColors c;
  final VoidCallback onMic;
  final VoidCallback? onMicLongPressStart;
  final VoidCallback? onMicLongPressEnd;
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
    this.onMicLongPressStart,
    this.onMicLongPressEnd,
    required this.onToggleAutoScroll,
    required this.onSettingsTap, // Kept for signature compatibility, unused here as settings moved
    this.isVoiceSearching = false,
  });

  @override
  State<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<BottomActionBar> {
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
                onTap: widget.onMic,
                onLongPressStart: (_) => widget.onMicLongPressStart?.call(),
                onLongPressEnd: (_) => widget.onMicLongPressEnd?.call(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: widget.isVoiceSearching
                        ? LinearGradient(
                            colors: [c.gold, Colors.deepPurpleAccent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : widget.isRecording
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
                            .withValues(alpha: 0.3),
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
              )
            else
              // Stop button for AutoScroll
              GestureDetector(
                onTap: widget.onToggleAutoScroll,
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
