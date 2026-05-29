// Bottom action bar — the main toolbar for the recitation screen.
//
// States:
// 1. **Default**: Shows mic, blur, read, and font buttons with captions
// 2. **Recording**: Single centered stop button
// 3. **Auto-scrolling**: Centered stop pill
//
// Transitions between states use [AnimatedSwitcher] with slide-up/fade
// for a modern feel. The toolbar itself is transparent (no background).
import 'package:flutter/material.dart';
import '../../core/app_state.dart';

class BottomActionBar extends StatefulWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final bool isAutoScrolling;
  final ThemeColors c;
  final VoidCallback onMic;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onSettingsTap;
  final VoidCallback onTajweedTap;

  const BottomActionBar({
    super.key,
    required this.isRecording,
    required this.isLoadingEngine,
    required this.isAutoScrolling,
    required this.c,
    required this.onMic,
    required this.onToggleAutoScroll,
    required this.onSettingsTap,
    required this.onTajweedTap,
  });

  @override
  State<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<BottomActionBar> {
  /// Whether the font size slider is expanded.
  bool _showFontSlider = false;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = widget.c;
    final isAr = app.isArabic;
    Widget child;

    if (widget.isRecording) {
      // ── Recording: compact centered stop button ────────────────────────
      child = Center(
        key: const ValueKey('recording'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: widget.onMic,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: c.red.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      );
    } else if (widget.isAutoScrolling) {
      // ── Auto-scrolling: centered stop pill ─────────────────────────────
      child = Center(
        key: const ValueKey('auto_scrolling'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: widget.onToggleAutoScroll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: c.red,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: c.red.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stop_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    isAr ? 'إيقاف' : 'Stop',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // ── Default toolbar (transparent background) ───────────────────────
      child = Column(
        key: const ValueKey('default'),
        mainAxisSize: MainAxisSize.min,
        children: [
          // Font slider — expands above toolbar with smooth animation
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _showFontSlider
                ? Container(
                    margin: const EdgeInsets.only(
                      bottom: 6,
                      left: 24,
                      right: 24,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: c.border.withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.text_decrease_rounded,
                          color: c.muted,
                          size: 13,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10,
                              ),
                              trackHeight: 2,
                              activeTrackColor: c.gold,
                              inactiveTrackColor: c.border.withValues(
                                alpha: 0.4,
                              ),
                              thumbColor: c.gold,
                            ),
                            child: Slider(
                              value: app.fontSize,
                              min: 16.0,
                              max: 42.0,
                              onChanged: (v) => app.setFontSize(v),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.text_increase_rounded,
                          color: c.muted,
                          size: 13,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Main toolbar buttons (transparent — no card/pill background)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Record button (larger, gradient)
                _LabeledButton(
                  label: isAr ? 'تسجيل' : 'Rec',
                  c: c,
                  child: GestureDetector(
                    onTap: widget.onMic,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.red, c.red.withValues(alpha: 0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.red.withValues(alpha: 0.25),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: widget.isLoadingEngine
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.mic_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                  ),
                ),

                // Tajweed mode switch button
                _ToolbarButton(
                  icon: Icons.menu_book_rounded,
                  label: isAr ? 'تجويد' : 'Tajweed',
                  isActive: false,
                  c: c,
                  onTap: widget.onTajweedTap,
                ),

                // Blur mode toggle
                _ToolbarButton(
                  icon: app.isBlurMode
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  label: isAr ? 'إخفاء' : 'Hide',
                  isActive: app.isBlurMode,
                  c: c,
                  onTap: () => app.toggleBlurMode(),
                ),

                // Read mode
                _ToolbarButton(
                  icon: Icons.auto_stories_rounded,
                  label: isAr ? 'قراءة' : 'Read',
                  isActive: false,
                  c: c,
                  onTap: widget.onToggleAutoScroll,
                ),

                // Font size toggle
                _ToolbarButton(
                  icon: Icons.format_size_rounded,
                  label: isAr ? 'الخط' : 'Font',
                  isActive: _showFontSlider,
                  c: c,
                  onTap: () {
                    setState(() => _showFontSlider = !_showFontSlider);
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.4),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// A toolbar icon button with an active state indicator and small caption.
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ThemeColors c;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive
                    ? c.gold.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isActive ? c.gold : c.muted.withValues(alpha: 0.45),
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? c.gold : c.muted.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Wrapper that adds a small caption label below any child widget.
class _LabeledButton extends StatelessWidget {
  final String label;
  final ThemeColors c;
  final Widget child;

  const _LabeledButton({
    required this.label,
    required this.c,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: c.muted.withValues(alpha: 0.4),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
