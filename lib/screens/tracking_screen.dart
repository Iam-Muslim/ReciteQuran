/// Main recitation screen — displays the verse list, top header, and bottom toolbar.
///
/// Responsibilities:
/// - Renders the scrollable verse list via [VerseRow] widgets
/// - Handles auto-scrolling (reading mode) with a [Ticker]-based smooth scroll
/// - Manages record → scroll navigation (two-phase: estimate → fine-tune)
/// - Coordinates the surah picker and settings bottom sheets
///
/// Performance: The verse list uses [ListView.builder] with [GlobalKey]s
/// for scroll targeting. The header and toolbar use [AnimatedSwitcher]
/// for smooth transitions.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_state.dart';
import '../recording/live_recitation_controller.dart';
import 'widgets/mic_bar.dart';
import 'widgets/verse_row.dart';
import 'widgets/surah_picker.dart';
import 'widgets/settings_dialog.dart';
import 'dart:async';

class TrackingScreen extends StatefulWidget {
  final LiveRecitationController controller;
  final bool isRecording;
  final bool isLoadingEngine;
  final VoidCallback onToggleRecord;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isLoadingEngine,
    required this.onToggleRecord,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  /// Tracks the last scrolled-to ayah to avoid duplicate scrolls.
  int? _lastAyah;

  /// Reading mode state.
  bool _isAutoScrolling = false;
  Timer? _autoScrollTimer;
  Ticker? _scrollTicker;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _scroll.dispose();
    _scrollTicker?.dispose();

    // Safety: release wakelock if screen is destroyed mid-session
    if (_isAutoScrolling || widget.isRecording) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When recording starts → force-scroll to the active ayah
    if (widget.isRecording && !oldWidget.isRecording) {
      _lastAyah = null;
      final match = widget.controller.currentMatchedVerse;
      if (match != null) {
        _forceScrollToAyah(match.verse.ayah);
      }
    }
  }

  /// Called on every controller notification — scrolls to the active ayah
  /// when it changes.
  void _onControllerUpdate() {
    final match = widget.controller.currentMatchedVerse;
    if (match != null) {
      final ayah = match.verse.ayah;
      if (ayah != _lastAyah) {
        _lastAyah = ayah;
        _scrollToAyah(ayah);
      }
    }
  }

  /// Smooth scroll to a verse. Skips if in auto-scroll (reading) mode.
  void _scrollToAyah(int ayah) {
    if (_isAutoScrolling) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[ayah]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: 0.35,
        );
      }
    });
  }

  /// Two-phase scroll: first estimate pixel offset (for off-screen items
  /// whose GlobalKey context is null due to ListView recycling), then
  /// fine-tune with ensureVisible after the item is built.
  void _forceScrollToAyah(int ayah) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[ayah]?.currentContext;
      if (ctx != null) {
        // Item is on-screen — direct scroll
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: 0.35,
        );
      } else {
        // Item is off-screen — estimate position, scroll there,
        // then fine-tune once the item is built
        final displayVerses = widget.controller.repository
            .getSurah(widget.controller.targetSurah);
        final idx = displayVerses.indexWhere((v) => v.ayah == ayah);
        if (idx >= 0 && _scroll.hasClients) {
          // Rough estimate: ~100px per verse row (varies with word count)
          final estimated = idx * 100.0;
          _scroll.animateTo(
            estimated.clamp(0.0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
          // After scroll completes, the item should be built — fine-tune
          Future.delayed(const Duration(milliseconds: 500), () {
            final ctx2 = _keys[ayah]?.currentContext;
            if (ctx2 != null && mounted) {
              Scrollable.ensureVisible(
                ctx2,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: 0.35,
              );
            }
          });
        }
      }
    });
  }

  /// Toggles reading mode (auto-scroll).
  /// Entering reading mode clears all highlights and stops tracking.
  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      _autoScrollTimer?.cancel();
      WakelockPlus.disable();
    } else {
      widget.controller.clearHighlights();
      widget.controller.finalize();
      setState(() => _isAutoScrolling = true);
      _startAutoScrollLoop();
      WakelockPlus.enable();
    }
  }

  /// Starts the ticker-based smooth auto-scroll.
  /// Speed scales with font size for consistent reading pace.
  void _startAutoScrollLoop() {
    _scrollTicker?.stop();
    _scrollTicker ??= createTicker((elapsed) {
      if (!_isAutoScrolling || !mounted) {
        _scrollTicker?.stop();
        return;
      }
      final position = _scroll.position;
      if (position.pixels < position.maxScrollExtent) {
        double speed =
            ((AppState.instance.fontSize / 24.0) * 1.5) * (16.0 / 50.0);
        _scroll.jumpTo(position.pixels + speed);
      } else {
        setState(() => _isAutoScrolling = false);
        _scrollTicker?.stop();
        WakelockPlus.disable();
      }
    });
    _scrollTicker?.start();
  }

  /// Opens the surah selection bottom sheet.
  void _showSurahPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SurahPickerSheet(
        current: widget.controller.targetSurah,
        onPick: (n) async {
          Navigator.pop(context);
          await widget.controller.setTargetSurah(n);
          widget.onClearBuffer();
          setState(() {
            _keys.clear();
            _lastAyah = null;
          });
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scroll.hasClients) _scroll.jumpTo(0);
          });
        },
      ),
    );
  }

  /// Opens the settings bottom sheet.
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
      builder: (_, __) {
        final c = app.colors;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: c.bg,
            body: Column(
              children: [
                // ── Top Header (compact pill) ────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.3),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: child,
                      ),
                    );
                  },
                  child: (!widget.isRecording && !_isAutoScrolling)
                      ? Container(
                          key: const ValueKey('header'),
                          margin: EdgeInsets.only(
                            top: top + 4,
                            left: 24,
                            right: 24,
                            bottom: 2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(
                              color: c.border.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Surah name tap area
                              GestureDetector(
                                onTap: _showSurahPicker,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListenableBuilder(
                                        listenable: widget.controller,
                                        builder: (context, _) {
                                          final displayVerses = widget
                                              .controller
                                              .repository
                                              .getSurah(widget
                                                  .controller.targetSurah);
                                          return Text(
                                            app.isArabic
                                                ? displayVerses
                                                    .first.surahName
                                                : displayVerses
                                                    .first.surahNameEn,
                                            style: TextStyle(
                                              color: c.gold,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: c.muted.withValues(alpha: 0.4),
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Settings button — generous tap target
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _showSettingsDialog,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    color: c.gold.withValues(alpha: 0.6),
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty_header')),
                ),

                // ── Verse List ───────────────────────────────────────────
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final displayVerses = widget.controller.repository
                          .getSurah(widget.controller.targetSurah);
                      return ListView.builder(
                        controller: _scroll,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 6, 0, 140),
                        itemCount: displayVerses.length,
                        itemBuilder: (_, i) {
                          final v = displayVerses[i];
                          _keys.putIfAbsent(v.ayah, () => GlobalKey());

                          return VerseRow(
                            key: _keys[v.ayah],
                            verse: v,
                            controller: widget.controller,
                            isAutoScrolling: _isAutoScrolling,
                            onTap: () {
                              widget.controller
                                  .setManualAyah(v.surah, v.ayah);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

                // ── Bottom Action Bar ────────────────────────────────────
                SafeArea(
                  top: false,
                  child: BottomActionBar(
                    isRecording: widget.isRecording,
                    isLoadingEngine: widget.isLoadingEngine,
                    isAutoScrolling: _isAutoScrolling,
                    c: c,
                    onMic: widget.onToggleRecord,
                    onToggleAutoScroll: _toggleAutoScroll,
                    onSettingsTap: _showSettingsDialog,
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
