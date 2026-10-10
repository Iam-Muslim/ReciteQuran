// lib/tracking/tajweed/tajweed_error_sheet.dart

import 'package:flutter/material.dart';

import 'error_explainer.dart';

/// Displays an optional, pre-styled Islamic modal bottom sheet presenting
/// detailed Tajweed, Tashkeel, or Pronunciation feedback for a word.
Future<void> showTajweedErrorSheet(
  BuildContext context, {
  required List<ReciterError> errors,
  String? wordText,
  bool isArabic = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => TajweedErrorSheet(
      errors: errors,
      wordText: wordText,
      isArabic: isArabic,
    ),
  );
}

/// An optional, pre-built elegant bottom sheet widget presenting recitation feedback.
class TajweedErrorSheet extends StatelessWidget {
  final List<ReciterError> errors;
  final String? wordText;
  final bool isArabic;

  const TajweedErrorSheet({
    super.key,
    required this.errors,
    this.wordText,
    this.isArabic = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final primaryColor =
        isDark ? const Color(0xFFD4AF37) : const Color(0xFFB8860B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  color: primaryColor,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    wordText != null
                        ? (isArabic
                            ? 'تنبيه على كلمة: $wordText'
                            : 'Notice on Word: $wordText')
                        : (isArabic
                            ? 'ملاحظات التجويد والنطق'
                            : 'Recitation Feedback'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Errors List
            ...errors.map((error) => _buildErrorCard(context, error)),

            const SizedBox(height: 12),

            // Close button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                isArabic ? 'فهمت (إغلاق)' : 'Got it (Close)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, ReciterError error) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF282830) : const Color(0xFFF9F9FB);

    final title = isArabic ? error.messageAr : error.messageEn;
    final advice = isArabic ? error.adviceAr : error.adviceEn;

    IconData icon;
    Color iconColor;

    if (error.errorType == ErrorCategory.tajweed) {
      icon = Icons.timer_outlined;
      iconColor = Colors.amber.shade700;
    } else if (error.errorType == ErrorCategory.tashkeel) {
      icon = Icons.spellcheck_rounded;
      iconColor = Colors.orange.shade700;
    } else {
      icon = Icons.cancel_outlined;
      iconColor = Colors.redAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  advice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
