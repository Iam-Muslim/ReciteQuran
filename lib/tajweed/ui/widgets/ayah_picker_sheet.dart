import 'package:flutter/material.dart';
import '../../../core/app_state.dart';

class AyahPickerSheet extends StatefulWidget {
  final int maxAyah;
  final int current;
  final void Function(int) onPick;

  const AyahPickerSheet({
    super.key,
    required this.maxAyah,
    required this.current,
    required this.onPick,
  });

  @override
  State<AyahPickerSheet> createState() => _AyahPickerSheetState();
}

class _AyahPickerSheetState extends State<AyahPickerSheet> {
  bool _scrolled = false;

  String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((e) => digits[int.parse(e)])
        .join('');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final ThemeColors c = app.colors;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.6,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrolled && ctrl.hasClients) {
            _scrolled = true;
            double offset = (widget.current - 1) * 48.0;
            if (offset > ctrl.position.maxScrollExtent) {
              offset = ctrl.position.maxScrollExtent;
            }
            ctrl.jumpTo(offset);
          }
        });

        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Directionality(
            textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  app.isArabic ? 'اختر الآية' : 'Select Ayah',
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Ayah list ───────────────────────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.maxAyah,
                    itemBuilder: (_, i) {
                      final int aNum = i + 1;
                      final bool sel = widget.current == aNum;

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? c.gold.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: sel
                                ? c.gold.withValues(alpha: 0.5)
                                : c.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: app.isArabic
                              ? (sel
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: c.gold,
                                        size: 24,
                                      )
                                    : const SizedBox(width: 24))
                              : Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: sel ? c.gold : c.surfaceHigh,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    app.isArabic
                                        ? _toArabicDigits(aNum)
                                        : '$aNum',
                                    style: TextStyle(
                                      color: sel ? Colors.white : c.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                          title: Text(
                            app.isArabic
                                ? 'الآية ${_toArabicDigits(aNum)}'
                                : 'Ayah $aNum',
                            textAlign: app.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
                            style: TextStyle(
                              color: sel ? c.gold : c.text,
                              fontSize: 20,
                              fontWeight: sel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: app.isArabic
                              ? Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: sel ? c.gold : c.surfaceHigh,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    app.isArabic
                                        ? _toArabicDigits(aNum)
                                        : '$aNum',
                                    style: TextStyle(
                                      color: sel ? Colors.white : c.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : (sel
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: c.gold,
                                        size: 24,
                                      )
                                    : const SizedBox(width: 24)),
                          onTap: () => widget.onPick(aNum),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
