import 'package:flutter/material.dart';
import '../../core/app_state.dart';

class BottomActionBar extends StatefulWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final bool isAutoScrolling;
  final AnimationController pulse;
  final ThemeColors c;
  final VoidCallback onMic;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onSettingsTap;

  const BottomActionBar({
    super.key,
    required this.isRecording,
    required this.isLoadingEngine,
    required this.isAutoScrolling,
    required this.pulse,
    required this.c,
    required this.onMic,
    required this.onToggleAutoScroll,
    required this.onSettingsTap,
  });

  @override
  State<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<BottomActionBar> {
  OverlayEntry? _sliderOverlay;

  void _removeSlider() {
    _sliderOverlay?.remove();
    _sliderOverlay = null;
  }

  @override
  void dispose() {
    _removeSlider();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = widget.c;
    Widget child;
    if (widget.isRecording) {
      child = Align(
        key: const ValueKey('recording'),
        alignment: Alignment.bottomRight,
        child: GestureDetector(
          onTap: widget.onMic,
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.red.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.stop_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      );
    } else if (widget.isAutoScrolling) {
      child = Align(
        key: const ValueKey('auto_scrolling'),
        alignment: Alignment.bottomRight,
        child: GestureDetector(
          onTap: widget.onToggleAutoScroll,
          child: Container(
            margin: const EdgeInsets.only(right: 16, bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.red,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: c.red.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stop_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Text(
                  app.isArabic ? 'إيقاف' : 'Stop',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = Container(
        key: const ValueKey('default'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: app.isDarkMode
              ? c.surface.withValues(alpha: 0.6)
              : c.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(40), // More pill-shaped
          border: Border.all(
            color: c.border.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: Container(
            color: app.isDarkMode
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.2),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Record Button (Rightmost in RTL)
                    if (!widget.isAutoScrolling)
                      GestureDetector(
                        onTap: widget.onMic,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [c.red, c.red.withValues(alpha: 0.7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: c.red.withValues(alpha: 0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: widget.isLoadingEngine
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(
                                Icons.mic_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                      ),
                    ),
                  if (widget.isAutoScrolling) const SizedBox(width: 40),

                  // Blur Mode Button (Immediately left of Record button in RTL)
                  if (!widget.isAutoScrolling)
                    GestureDetector(
                      onTap: () => app.toggleBlurMode(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: app.isBlurMode
                              ? c.gold.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              app.isBlurMode
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: c.gold.withValues(alpha: 0.85),
                              size: 18,
                            ),
                            Text(
                              app.isArabic ? 'حفظ' : 'Blur',
                              style: TextStyle(
                                color: c.gold.withValues(alpha: 0.85),
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Auto Scroll Button (Left of Surah Selector)
                  GestureDetector(
                    onTap: widget.onToggleAutoScroll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_stories_rounded,
                            color: c.gold.withValues(alpha: 0.85),
                            size: 18,
                          ),
                          Text(
                            app.isArabic ? 'اقرأ' : 'Read',
                            style: TextStyle(
                              fontSize: 8,
                              color: c.gold.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Font Size Button (Opens drop-up slider)
                  if (!widget.isAutoScrolling)
                    Builder(
                      builder: (buttonContext) {
                        return GestureDetector(
                          onTap: () {
                            if (_sliderOverlay != null) {
                              _removeSlider();
                              return;
                            }
                            final RenderBox button =
                                buttonContext.findRenderObject() as RenderBox;
                            final RenderBox overlay =
                                Navigator.of(context).overlay!.context.findRenderObject()
                                    as RenderBox;
                            final position = button.localToGlobal(
                              const Offset(0, -90),
                              ancestor: overlay,
                            );

                            _sliderOverlay = OverlayEntry(
                              builder: (context) {
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: position.dx - 12, // adjust for width
                                      top: position.dy,
                                      child: TapRegion(
                                        onTapOutside: (_) => _removeSlider(),
                                        child: Material(
                                          elevation: 8,
                                          borderRadius: BorderRadius.circular(16),
                                          color: app.isDarkMode
                                              ? c.surface
                                              : Colors.white,
                                          child: SizedBox(
                                            height: 90,
                                            width: 48,
                                            child: StatefulBuilder(
                                              builder: (context, setStateOverlay) {
                                                return RotatedBox(
                                                  quarterTurns: 3,
                                                  child: SliderTheme(
                                                    data: SliderThemeData(
                                                      thumbShape:
                                                          const RoundSliderThumbShape(
                                                        enabledThumbRadius: 8,
                                                      ),
                                                      overlayShape:
                                                          const RoundSliderOverlayShape(
                                                        overlayRadius: 16,
                                                      ),
                                                      trackHeight: 4,
                                                      activeTrackColor: c.gold,
                                                      inactiveTrackColor: c.border,
                                                      thumbColor: c.gold,
                                                    ),
                                                    child: Slider(
                                                      value: app.fontSize,
                                                      min: 16.0,
                                                      max: 42.0,
                                                      onChanged: (v) {
                                                        app.setFontSize(v);
                                                        setStateOverlay(() {});
                                                      },
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                            Overlay.of(context).insert(_sliderOverlay!);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            color: Colors.transparent,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.format_size_rounded,
                                  color: c.gold.withValues(alpha: 0.85),
                                  size: 18,
                                ),
                                Text(
                                  app.isArabic ? 'الخط' : 'Font',
                                  style: TextStyle(
                                    color: c.gold.withValues(alpha: 0.85),
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  // Settings Button removed (moved to top bar)
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.bottomRight,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation,
            alignment: Alignment.centerRight,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
