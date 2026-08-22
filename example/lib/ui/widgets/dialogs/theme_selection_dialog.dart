import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

class ThemeSelectionDialog extends StatefulWidget {
  final VoidCallback onThemeSelected;

  const ThemeSelectionDialog({super.key, required this.onThemeSelected});

  @override
  State<ThemeSelectionDialog> createState() => _ThemeSelectionDialogState();
}

class _ThemeSelectionDialogState extends State<ThemeSelectionDialog> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.colors;
        final isAr = app.isArabic;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: c.gold.withValues(alpha: 0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.gold.withValues(alpha: 0.15),
                    blurRadius: 40,
                    spreadRadius: -10,
                    offset: const Offset(0, 15),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAr ? 'اختر مظهر التطبيق' : 'Choose App Theme',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isAr
                          ? 'يمكنك تغيير المظهر لاحقاً من الإعدادات'
                          : 'You can change this later in settings',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ThemeSwatch(
                        title: isAr ? 'أبيض' : 'Light',
                        color: const Color(0xFFFAF6F0),
                        isSelected: _selectedIndex == 0,
                        c: c,
                        onTap: () {
                          setState(() => _selectedIndex = 0);
                          app.setTheme(AppTheme.light);
                          Future.delayed(const Duration(milliseconds: 300), widget.onThemeSelected);
                        },
                      ),
                      const SizedBox(width: 32),
                      _ThemeSwatch(
                        title: isAr ? 'أسود' : 'Dark',
                        color: const Color(0xFF1E1A16),
                        isSelected: _selectedIndex == 1,
                        c: c,
                        onTap: () {
                          setState(() => _selectedIndex = 1);
                          app.setTheme(AppTheme.dark);
                          Future.delayed(const Duration(milliseconds: 300), widget.onThemeSelected);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThemeSwatch extends StatefulWidget {
  final String title;
  final Color color;
  final bool isSelected;
  final ThemeColors c;
  final VoidCallback onTap;

  const _ThemeSwatch({
    required this.title,
    required this.color,
    required this.isSelected,
    required this.c,
    required this.onTap,
  });

  @override
  State<_ThemeSwatch> createState() => _ThemeSwatchState();
}

class _ThemeSwatchState extends State<_ThemeSwatch> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isSelected ? widget.c.gold : widget.c.border,
                  width: widget.isSelected ? 3 : 1.5,
                ),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: widget.c.gold.withValues(alpha: 0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: widget.isSelected
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: widget.c.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: TextStyle(
              color: widget.isSelected ? widget.c.gold : widget.c.muted,
              fontSize: 15,
              fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
