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

  int? _lastAyah;

  bool _isAutoScrolling = false;
  Timer? _autoScrollTimer;
  Ticker? _scrollTicker;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

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
    _pulse.dispose();
    _scrollTicker?.dispose();

    // SAFETY CATCH: Force release the wakelock if screen is destroyed mid-session
    if (_isAutoScrolling || widget.isRecording) {
      WakelockPlus.disable();
    }

    super.dispose();
  }

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

  void _scrollToAyah(int ayah) {
    if (_isAutoScrolling) return; // Don't interrupt auto scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[ayah]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: 0.4,
        );
      }
    });
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      _autoScrollTimer?.cancel();
      WakelockPlus.disable();
    } else {
      setState(() => _isAutoScrolling = true);
      _startAutoScrollLoop();
      WakelockPlus.enable();
    }
  }

  void _startAutoScrollLoop() {
    _scrollTicker?.stop();
    _scrollTicker ??= createTicker((elapsed) {
      if (!_isAutoScrolling || !mounted) {
        _scrollTicker?.stop();
        return;
      }
      final position = _scroll.position;
      if (position.pixels < position.maxScrollExtent) {
        // Smooth hardware-synced scrolling (scale speed to frame time)
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
          _keys.clear();
          _lastAyah = null;
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scroll.hasClients) {
              _scroll.jumpTo(0);
            }
          });
        },
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(context: context, builder: (_) => const SettingsDialog());
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: app,
      builder: (_, __) {
        final c = app.colors;

        final allVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );

        final displayVerses = allVerses;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: c.bg,
            body: Column(
              children: [
                // ── Top Header Card ───────────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1.0,
                      child: FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.5),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: (!widget.isRecording && !_isAutoScrolling)
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            key: const ValueKey('header'),
                          margin: EdgeInsets.only(
                            top: top + 8,
                            left: 24,
                            right: 24,
                            bottom: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(
                              color: c.border.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _showSurahPicker,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListenableBuilder(
                                      listenable: widget.controller,
                                      builder: (context, _) {
                                        final displayVerses = widget
                                            .controller
                                            .repository
                                            .getSurah(
                                              widget.controller.targetSurah,
                                            );
                                        return Text(
                                          app.isArabic
                                              ? "${displayVerses.first.surahName} - ${displayVerses.first.surahNameEn}"
                                              : "${displayVerses.first.surahNameEn} - ${displayVerses.first.surahName}",
                                          style: TextStyle(
                                            color: c.gold,
                                            fontFamily: 'ScheherazadeNew-Bold',
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: c.muted,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),

                              // Settings Button
                              const SizedBox(width: 16),
                              GestureDetector(
                                onTap: _showSettingsDialog,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.settings_rounded,
                                    color: c.gold.withValues(alpha: 0.8),
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty_header')),
                ),
                // ── Main Recitation List ──────────────────────────────────────────
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final displayVerses = widget.controller.repository
                          .getSurah(widget.controller.targetSurah);
                      return ListView.builder(
                        controller: _scroll,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 140),
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
                              widget.controller.setManualAyah(v.surah, v.ayah);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                // ── Bottom Action Bar ──────────────────────────────────────────────
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: BottomActionBar(
                      isRecording: widget.isRecording,
                      isLoadingEngine: widget.isLoadingEngine,
                      isAutoScrolling: _isAutoScrolling,
                      pulse: _pulse,
                      c: c,
                      onMic: widget.onToggleRecord,
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
}
