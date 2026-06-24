import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/app_state.dart';
import '../tracking/highlighting_controller.dart';
import 'widgets/mic_bar.dart';
import 'widgets/verse_row.dart';
import 'widgets/surah_picker.dart';
import 'widgets/settings_dialog.dart';

class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final bool isLoadingEngine;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchStart;
  final VoidCallback onVoiceSearchStop;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    required this.isLoadingEngine,
    required this.onToggleRecord,
    required this.onVoiceSearchStart,
    required this.onVoiceSearchStop,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  int? _lastAyah;
  bool _isAutoScrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // Prevent screen sleep during reading/recitation
    widget.controller.addListener(_onControllerUpdate);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (widget.isRecording) {
        widget.onToggleRecord();
      }
      if (widget.isVoiceSearching) {
        widget.onVoiceSearchStop();
      }
      if (_isAutoScrolling) {
        _toggleAutoScroll();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerUpdate);
    _scroll.dispose();
    WakelockPlus.disable(); // Always disable wakelock when exiting the screen
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _lastAyah = null;
      final match = widget.controller.currentMatchedVerse;
      if (match != null) {
        _forceScrollToAyah(match.verse.ayah);
      }
    }
  }

  void _onControllerUpdate() {
    final match = widget.controller.currentMatchedVerse;
    if (match != null) {
      final ayah = match.verse.ayah;
      if (ayah != _lastAyah) {
        _lastAyah = ayah;
        _forceScrollToAyah(ayah);
      }
    }
  }

  void _forceScrollToAyah(int ayah) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[ayah]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: 0.35,
        );
      } else {
        final displayVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );
        final idx = displayVerses.indexWhere((v) => v.ayah == ayah);
        if (idx >= 0 && _scroll.hasClients) {
          // Estimate height dynamically based on character count
          double estimated = 0;
          for (int i = 0; i < idx; i++) {
            estimated += 120.0 + (displayVerses[i].textUthmani.length * 1.5);
          }
          _scroll.jumpTo(estimated);
        }
      }
    });
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          _scroll.position.pixels,
        ); // Immediately halt the animation
      }
      WakelockPlus.disable();
    } else {
      widget.controller.clearHighlights();
      widget.controller.finalize();
      setState(() => _isAutoScrolling = true);
      _startAutoScrollLoop();
      WakelockPlus.enable();
    }
  }

  void _startAutoScrollLoop() {
    if (!_isAutoScrolling || !mounted || !_scroll.hasClients) return;

    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent) {
      double baseSpeed =
          ((AppState.instance.fontSize / 24.0) * 1.5) * (16.0 / 50.0);
      double speedPerFrame = baseSpeed * AppState.instance.autoScrollSpeed;

      // Calculate duration in milliseconds. 60 frames = 1 second.
      // Pixels per second = speedPerFrame * 60
      final double pixelsPerSec = speedPerFrame * 60;
      final double remainingScroll = position.maxScrollExtent - position.pixels;
      final double durationSec = remainingScroll / pixelsPerSec;

      _scroll
          .animateTo(
            position.maxScrollExtent,
            duration: Duration(milliseconds: (durationSec * 1000).toInt()),
            curve: Curves.linear,
          )
          .then((_) {
            if (mounted && _isAutoScrolling) {
              setState(() => _isAutoScrolling = false);
              WakelockPlus.disable();
            }
          });
    } else {
      setState(() => _isAutoScrolling = false);
      WakelockPlus.disable();
    }
  }

  void _showSurahPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SurahPickerSheet(
        current: widget.controller.targetSurah,
        controller: widget.controller,
        isRecording: widget.isRecording,
        onToggleRecord: widget.onToggleRecord,
        onPick: (n, {ayah}) async {
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
          // Jump to top BEFORE swapping data so ListView doesn't try to
          // maintain the old offset in the new Surah.
          if (_scroll.hasClients) {
            _scroll.jumpTo(0);
          }

          await widget.controller.setTargetSurah(n);
          if (ayah != null) {
            widget.controller.setManualAyah(n, ayah);
          }

          setState(() {
            _keys.clear();
            _lastAyah = null;
          });
        },
      ),
    );
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: app,
      builder: (_, _) {
        final c = app.colors;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: c.bg,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Main Content
                Positioned.fill(child: _buildWordCheckerContent(c, app, top)),

                // Top Header (AnimatedSwitcher for mode change)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, -1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      );
                    },
                    child: _buildHeader(c, app, top),
                  ),
                ),

                // Bottom Action Bar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  bottom: MediaQuery.of(context).viewPadding.bottom,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      );
                    },
                    child: BottomActionBar(
                      key: const ValueKey('word_checker_bar'),
                      isRecording: widget.isRecording,
                      isVoiceSearching: widget.isVoiceSearching,
                      isLoadingEngine: widget.isLoadingEngine,
                      isAutoScrolling: _isAutoScrolling,
                      c: c,
                      onMic: widget.onToggleRecord,
                      onMicLongPressStart: widget.onVoiceSearchStart,
                      onMicLongPressEnd: widget.onVoiceSearchStop,
                      onToggleAutoScroll: _toggleAutoScroll,
                      onSettingsTap: _showSettingsDialog,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeColors c, AppState app, double top) {
    if (widget.isVoiceSearching) {
      return Padding(
        key: const ValueKey('header_voice_search'),
        padding: EdgeInsets.only(top: top + 12, left: 16, right: 16, bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.deepPurpleAccent.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                app.isArabic ? 'جاري الاستماع للبحث عن الآية...' : 'Listening to navigate...',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.isRecording || _isAutoScrolling) {
      return const SizedBox.shrink(key: ValueKey('empty_header'));
    }

    return Padding(
      key: const ValueKey('header_main'),
      padding: EdgeInsets.only(top: top + 12, left: 16, right: 16, bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            // ── Surah Selector (Soft Button) ──
            Expanded(
              child: GestureDetector(
                onTap: _showSurahPicker,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.menu_book_rounded, color: c.gold, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final displayVerses = widget.controller.repository
                                .getSurah(widget.controller.targetSurah);
                            return FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: app.isArabic
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Text(
                                app.isArabic
                                    ? displayVerses.first.surahName
                                    : displayVerses.first.surahNameEn,
                                style: TextStyle(
                                  fontFamily: app.isArabic
                                      ? 'HafsSmart'
                                      : 'Inter',
                                  color: c.gold,
                                  fontSize: app.isArabic ? 18 : 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: c.gold,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 6),

            // ── Toolbar Actions ──
            _buildActionBtn(
              icon: _isAutoScrolling
                  ? Icons.pause_rounded
                  : Icons.auto_stories_rounded,
              label: _isAutoScrolling
                  ? (app.isArabic ? 'إيقاف' : 'Pause')
                  : (app.isArabic ? 'قراءة' : 'Read'),
              color: c.text,
              onTap: _toggleAutoScroll,
            ),
            _buildActionBtn(
              icon: app.isBlurMode
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              label: app.isArabic ? 'إخفاء' : 'Hide',
              color: app.isBlurMode ? c.green : c.text,
              onTap: app.toggleBlurMode,
            ),
            _buildActionBtn(
              icon: Icons.format_color_text_rounded,
              label: app.isArabic ? 'تجويد' : 'Tajweed',
              color: app.currentMode == AppMode.tajweed ? c.green : c.text,
              onTap: () {
                app.setMode(
                  app.currentMode == AppMode.tajweed
                      ? AppMode.wordChecker
                      : AppMode.tajweed,
                );
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      app.currentMode == AppMode.tajweed
                          ? (app.isArabic
                                ? 'تم تفعيل وضع التجويد'
                                : 'Tajweed Mode Enabled')
                          : (app.isArabic
                                ? 'تم إيقاف وضع التجويد'
                                : 'Tajweed Mode Disabled'),
                    ),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            _buildActionBtn(
              icon: Icons.settings_rounded,
              label: app.isArabic ? 'إعدادات' : 'Settings',
              color: c.text,
              onTap: _showSettingsDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordCheckerContent(ThemeColors c, AppState app, double top) {
    return Builder(
      key: const ValueKey('word_checker_content'),
      builder: (context) {
        final displayVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );

        final bool isMainRec = widget.isRecording;
        final topPadding = (isMainRec || _isAutoScrolling)
            ? top + 16
            : top + 70;
        final bottomPadding = (isMainRec || _isAutoScrolling) ? 140.0 : 220.0;

        return ListView.builder(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero, // Padding is 0, list is truly full-screen
          itemCount:
              displayVerses.length + 2, // +2 for top and bottom padding items
          itemBuilder: (_, i) {
            // Top Padding Item (Animates based on header visibility)
            if (i == 0) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                height: topPadding,
              );
            }

            // Bottom Padding Item
            if (i == displayVerses.length + 1) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                height: bottomPadding,
              );
            }

            final v = displayVerses[i - 1];
            _keys.putIfAbsent(v.ayah, () => GlobalKey());

            return VerseRow(
              key: _keys[v.ayah],
              verse: v,
              controller: widget.controller,
              isAutoScrolling: _isAutoScrolling,
              onTap: () {
                widget.controller.setManualAyah(v.surah, v.ayah);
              },
            );
          },
        );
      },
    );
  }
}
