import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

class TajweedTooltipPainter extends CustomPainter {
  final List<String> words;
  final int ayah;
  final HighlightingController controller;
  final AppState app;
  final List<InlineSpan> cachedSpans;

  TajweedTooltipPainter({
    required this.words,
    required this.ayah,
    required this.controller,
    required this.app,
    required this.cachedSpans,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (app.hasClickedTajweedWord) return;

    // We must exactly replicate the RichText layout to get accurate coordinates
    // We MUST set minWidth to size.width so the TextPainter matches the full width of the
    // stretched RichText, otherwise the RTL text will be offset to the left!
    final painter = TextPainter(
      text: TextSpan(children: cachedSpans),
      textAlign: TextAlign.justify,
      textDirection: TextDirection.rtl,
    );
    painter.layout(minWidth: size.width, maxWidth: size.width);

    final String text = app.isArabic ? 'اضغط هنا' : 'Tap here';
    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 7, // Too small causes pixel-bleed; 7 is the absolute minimum for legibility
      fontWeight: FontWeight.w600, // Bold is too thick at this size and causes letters to smudge
      fontFamily: 'sans-serif',
    );
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
    )..layout();

    final bgPaint = Paint()
      ..color = app.colors.gold
      ..style = PaintingStyle.fill;
      
    final rrectRadius = const Radius.circular(4);

    int charOffset = 0;
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (controller.isWordYellow(ayah, i)) {
        final rects = painter.getBoxesForSelection(
          TextSelection(baseOffset: charOffset, extentOffset: charOffset + word.length),
        );
        if (rects.isNotEmpty) {
          double left = rects.first.left;
          double right = rects.first.right;
          double bottom = rects.first.bottom;
          for (final r in rects) {
            if (r.left < left) left = r.left;
            if (r.right > right) right = r.right;
            if (r.bottom > bottom) bottom = r.bottom;
          }
          final centerX = left + (right - left) / 2;

          // Draw the tooltip perfectly centered at the bottom of the bounding box.
          // Restore the 4px padding on each side (total 8) to match the original Container look
          final tooltipWidth = (textPainter.width + 8).roundToDouble(); 
          final tooltipHeight = (textPainter.height + 2).roundToDouble(); 
          
          final tooltipX = (centerX - tooltipWidth / 2).roundToDouble();
          final tooltipY = (bottom + 2).roundToDouble();
          
          final bgRect = RRect.fromLTRBR(
            tooltipX,
            tooltipY,
            tooltipX + tooltipWidth,
            tooltipY + tooltipHeight,
            rrectRadius,
          );
          
          canvas.drawRRect(bgRect, bgPaint);
          
          // Re-layout the text painter to perfectly match the box width,
          // so Flutter's internal TextAlign.center completely handles the text centering!
          textPainter.layout(minWidth: tooltipWidth, maxWidth: tooltipWidth);
          
          textPainter.paint(
            canvas,
            Offset(tooltipX, tooltipY + 1),
          );
          
          // Reset layout for the next word calculation
          textPainter.layout();
        }
      }
      charOffset += word.length + 1; // +1 for the space separator
    }
  }

  @override
  bool shouldRepaint(covariant TajweedTooltipPainter oldDelegate) {
    return oldDelegate.app.hasClickedTajweedWord != app.hasClickedTajweedWord ||
           oldDelegate.ayah != ayah || 
           oldDelegate.words.length != words.length;
  }
}
