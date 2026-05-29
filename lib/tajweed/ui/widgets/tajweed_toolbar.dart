import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/app_state.dart';

class TajweedToolbar extends StatelessWidget {
  final bool isRecording;
  final bool isAnalyzing;
  final double uploadProgress;
  final ThemeColors c;
  final VoidCallback onExit;
  final VoidCallback onRecord;
  final VoidCallback onSelectAyah;
  final int currentAyah;
  final String currentSurahName;

  const TajweedToolbar({
    super.key,
    required this.isRecording,
    required this.isAnalyzing,
    required this.uploadProgress,
    required this.c,
    required this.onExit,
    required this.onRecord,
    required this.onSelectAyah,
    required this.currentAyah,
    required this.currentSurahName,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dynamic status text
          if (isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                app.isArabic ? 'جاري التسجيل...' : 'Recording...',
                style: TextStyle(color: c.red, fontWeight: FontWeight.bold),
              ),
            ),
          if (isAnalyzing)
            Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 32, right: 32),
              child: Column(
                children: [
                  Text(
                    app.isArabic
                        ? (uploadProgress >= 1.0
                              ? 'جاري تقييم التلاوة...'
                              : 'جاري التحليل (${(uploadProgress * 100).toInt()}%)')
                        : (uploadProgress >= 1.0
                              ? 'Evaluating recitation...'
                              : 'Analyzing (${(uploadProgress * 100).toInt()}%)'),
                    style: TextStyle(
                      color: c.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: uploadProgress >= 1.0
                          ? null
                          : uploadProgress, // Indeterminate if >= 1.0
                      backgroundColor: c.gold.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(c.gold),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Exit Button
              GestureDetector(
                onTap: onExit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.border.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.close_rounded, color: c.muted, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        app.isArabic ? 'خروج' : 'Exit',
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Record Button
              GestureDetector(
                onTapDown: (_) => HapticFeedback.mediumImpact(),
                onTap: isAnalyzing ? null : onRecord,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  width: isRecording ? 80 : 70,
                  height: isRecording ? 80 : 70,
                  decoration: BoxDecoration(
                    color: isAnalyzing
                        ? c.muted
                        : (isRecording ? c.red : c.gold),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isAnalyzing
                                    ? c.muted
                                    : (isRecording ? c.red : c.gold))
                                .withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: isAnalyzing
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Icon(
                          isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                ),
              ),

              // Replaced Ayah Selector with an invisible dummy box to keep Record button centered
              Container(
                width: 80, // Approximate width of the exit button to balance
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
