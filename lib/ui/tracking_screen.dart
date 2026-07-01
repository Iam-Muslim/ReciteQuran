import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../state/app_state.dart';
import '../tracking/word/highlighting_controller.dart';
import 'widgets/mic_bar.dart';
import 'widgets/verse_row.dart';
import 'widgets/surah_picker.dart';
import 'widgets/settings_dialog.dart';

class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final String voiceSearchText;
  final bool isLoadingEngine;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    this.voiceSearchText = '',
    required this.isLoadingEngine,
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final AutoScrollController _scroll = AutoScrollController();
  final Map<int, GlobalKey> _keys = {};
  final ValueNotifier<String> _voiceSearchNotifier = ValueNotifier('');

  int? _lastAyah;
  int? _lastSurah;
  bool _isAutoScrolling = false;
  Ticker? _autoScrollTicker;

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
        widget.onVoiceSearchToggle();
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
    _autoScrollTicker?.dispose();
    _scroll.dispose();
    _voiceSearchNotifier.dispose();
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

    if (widget.voiceSearchText != oldWidget.voiceSearchText) {
      _voiceSearchNotifier.value = widget.voiceSearchText;
    }

    if (widget.isVoiceSearching && !oldWidget.isVoiceSearching) {
      _voiceSearchNotifier.value = widget.voiceSearchText;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showVoiceSearchDialog();
      });
    } else if (!widget.isVoiceSearching && oldWidget.isVoiceSearching) {
      // Close dialog and SurahPicker if open by popping until first route
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _showVoiceSearchDialog() {
    final app = AppState.instance;
    final c = app.colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(
        alpha: 0.1,
      ), // very subtle dark tint
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: c.gold.withValues(alpha: 0.4),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.gold.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing Stop Button
                  GestureDetector(
                    onTap: widget.onVoiceSearchToggle,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.redAccent.withValues(alpha: 0.15),
                                Colors.transparent,
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.surfaceHigh,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.redAccent.withValues(alpha: 0.3),
                                blurRadius: 15,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.stop_rounded,
                            color: Colors.redAccent,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    app.isArabic
                        ? 'جاري الاستماع...'
                        : 'Listening...',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.isArabic
                        ? 'اقرأ آية ليتم الانتقال إليها مباشرة'
                        : 'Read an Ayah to jump to it',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onControllerUpdate() {
    if (widget.controller.targetSurah != _lastSurah) {
      _lastSurah = widget.controller.targetSurah;
      _keys.clear();
      _lastAyah = null;

      // Jump to top immediately when Surah changes so the new Surah
      // doesn't inherit the previous Surah's scroll offset (which causes
      // it to animate wildly from the bottom).
      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    }

    final match = widget.controller.currentMatchedVerse;
    if (match != null) {
      final ayah = match.verse.ayah;
      if (ayah != _lastAyah) {
        _lastAyah = ayah;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _forceScrollToAyah(ayah);
          }
        });
      }
    }
  }

  void _forceScrollToAyah(int ayah) {
    if (!_scroll.hasClients) return;
    
    // If the scroll is a massive jump (e.g. loading a new Surah), make it incredibly fast
    // to prevent Flutter from trying to render hundreds of verses in 500ms, which causes lag.
    _scroll.scrollToIndex(
      ayah,
      duration: const Duration(milliseconds: 150),
      preferPosition: AutoScrollPosition.middle,
    );
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      if (_scroll.hasClients) {
        // Jumping to the current position cancels the ongoing animation
        _scroll.jumpTo(_scroll.position.pixels);
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

    double baseSpeed = ((AppState.instance.fontSize / 24.0) * 1.5) * (16.0 / 50.0);
    double speedPerFrame = baseSpeed * AppState.instance.autoScrollSpeed;
    final double pixelsPerSec = speedPerFrame * 60;

    final position = _scroll.position;
    final distance = position.maxScrollExtent - position.pixels;

    if (distance <= 0) {
      setState(() => _isAutoScrolling = false);
      WakelockPlus.disable();
      return;
    }

    final durationSeconds = distance / pixelsPerSec;

    // Use native Flutter ScrollActivity for perfectly smooth, tear-free linear scrolling.
    _scroll.animateTo(
      position.maxScrollExtent,
      duration: Duration(milliseconds: (durationSeconds * 1000).toInt()),
      curve: Curves.linear,
    ).then((_) {
      if (mounted && _isAutoScrolling) {
        setState(() => _isAutoScrolling = false);
        WakelockPlus.disable();
      }
    });
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
        isVoiceSearching: widget.isVoiceSearching,
        onToggleRecord: widget.onToggleRecord,
        onVoiceSearchToggle: widget.onVoiceSearchToggle,
        onPick: (n, {ayah}) async {
          if (widget.isRecording) {
            widget
                .onToggleRecord(); // Ensure main recording stops on manual navigate
          }
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
                      onMic: widget.isVoiceSearching
                          ? widget.onVoiceSearchToggle
                          : widget.onToggleRecord,
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
                final newMode = app.currentMode == AppMode.tajweed
                    ? AppMode.wordChecker
                    : AppMode.tajweed;
                app.setMode(newMode);
                widget.controller.setTajweedMode(newMode == AppMode.tajweed);

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
          physics: _isAutoScrolling
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
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

            return AutoScrollTag(
              key: ValueKey(v.ayah),
              controller: _scroll,
              index: v.ayah,
              child: VerseRow(
                key: ValueKey('verse_${v.surah}_${v.ayah}'),
                verse: v,
                controller: widget.controller,
                isAutoScrolling: _isAutoScrolling,
                onTap: () {
                  widget.controller.setManualAyah(v.surah, v.ayah);
                },
              ),
            );
          },
        );
      },
    );
  }
}
