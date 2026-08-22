import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

class SpeedSelectionDialog extends StatefulWidget {
  final VoidCallback onSpeedSelected;

  const SpeedSelectionDialog({super.key, required this.onSpeedSelected});

  @override
  State<SpeedSelectionDialog> createState() => _SpeedSelectionDialogState();
}

class _SpeedSelectionDialogState extends State<SpeedSelectionDialog> {
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
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
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: c.gold.withValues(alpha: 0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.gold.withValues(alpha: 0.15),
                    blurRadius: 50,
                    spreadRadius: -10,
                    offset: const Offset(0, 20),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAr ? 'سرعة التلاوة' : 'Recitation Speed',
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
                        ? 'يمكنك تغيير السرعة لاحقاً من الإعدادات'
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
                  const SizedBox(height: 20),
                  
                  _SpeedOption(
                    title: isAr ? 'بطيء' : 'Slow',
                    subtitle: isAr 
                        ? 'مناسب للمبتدئين وللتلاوة الهادئة.'
                        : 'Perfect for beginners and calm reading.',
                    isRecommended: false,
                    isSelected: _selectedIndex == 0,
                    c: c,
                    isAr: isAr,
                    onTap: () {
                      setState(() => _selectedIndex = 0);
                      app.setAutoScrollSpeed(1); // 0.5x
                      Future.delayed(const Duration(milliseconds: 300), widget.onSpeedSelected);
                    },
                  ),
                  const SizedBox(height: 10),
                  _SpeedOption(
                    title: isAr ? 'عادي' : 'Normal',
                    subtitle: isAr 
                        ? 'السرعة القياسية للتلاوة.'
                        : 'The standard reading speed.',
                    isRecommended: true,
                    isSelected: _selectedIndex == 1,
                    c: c,
                    isAr: isAr,
                    onTap: () {
                      setState(() => _selectedIndex = 1);
                      app.setAutoScrollSpeed(2); // 1.0x
                      Future.delayed(const Duration(milliseconds: 300), widget.onSpeedSelected);
                    },
                  ),
                  const SizedBox(height: 10),
                  _SpeedOption(
                    title: isAr ? 'سريع' : 'Fast',
                    subtitle: isAr 
                        ? 'للمراجعة والقراءة السريعة (الحدر).'
                        : 'For quick review and Hadr recitation.',
                    isRecommended: false,
                    isSelected: _selectedIndex == 2,
                    c: c,
                    isAr: isAr,
                    onTap: () {
                      setState(() => _selectedIndex = 2);
                      app.setAutoScrollSpeed(4); // 2.0x
                      Future.delayed(const Duration(milliseconds: 300), widget.onSpeedSelected);
                    },
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

class _SpeedOption extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool isRecommended;
  final bool isSelected;
  final ThemeColors c;
  final bool isAr;
  final VoidCallback onTap;

  const _SpeedOption({
    required this.title,
    required this.subtitle,
    required this.isRecommended,
    required this.isSelected,
    required this.c,
    required this.isAr,
    required this.onTap,
  });

  @override
  State<_SpeedOption> createState() => _SpeedOptionState();
}

class _SpeedOptionState extends State<_SpeedOption> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
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
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected ? widget.c.gold.withValues(alpha: 0.08) : widget.c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected ? widget.c.gold : widget.c.border,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.c.gold.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: widget.isSelected ? widget.c.gold : widget.c.text,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.isRecommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.c.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.isAr ? 'موصى به' : 'Recommended',
                        style: TextStyle(
                          color: widget.c.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: widget.c.muted,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
