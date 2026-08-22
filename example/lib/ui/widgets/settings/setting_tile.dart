import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

/// Thin flush separator line for grouped lists.
class PremiumSettingDivider extends StatelessWidget {
  final ThemeColors c;
  const PremiumSettingDivider({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 56, right: 16), // Flush with text, not icon
      color: c.border.withValues(alpha: 0.15),
    );
  }
}

/// A unified minimalist setting tile that handles both row-based and column-based layouts.
class SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final ThemeColors c;
  final Widget? trailing;
  final Widget? bottom;

  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.c,
    this.trailing,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: c.gold, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: trailing != null ? 2 : 1,
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Expanded(flex: 3, child: trailing!),
              ],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 14),
            bottom!,
          ],
        ],
      ),
    );
  }
}

/// Ultra-smooth premium segmented selector with drop shadows.
class PremiumPillSelector extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ThemeColors c;
  final ValueChanged<int> onSelected;

  const PremiumPillSelector({
    super.key,
    required this.labels,
    required this.selected,
    required this.c,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.border.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = constraints.maxWidth / labels.length;
          
          return Stack(
            children: [
              // Animated Background Pill
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                left: Directionality.of(context) == TextDirection.ltr
                    ? selected * pillWidth
                    : (labels.length - 1 - selected) * pillWidth,
                top: 0,
                bottom: 0,
                width: pillWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Text Labels
              Row(
                children: List.generate(labels.length, (i) {
                  final isSel = i == selected;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onSelected(i),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: isSel ? c.text : c.text.withValues(alpha: 0.5),
                            fontSize: 14,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                            fontFamily: 'sans-serif',
                          ),
                          child: Text(labels[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        }
      ),
    );
  }
}
