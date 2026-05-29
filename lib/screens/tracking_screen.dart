import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_state.dart';
import '../recording/live_recitation_controller.dart';
import 'widgets/mic_bar.dart';
import 'widgets/verse_row.dart';
import 'widgets/surah_picker.dart';
import 'widgets/settings_dialog.dart';

import '../tajweed/providers/muaalem_provider.dart';
import '../tajweed/ui/widgets/tajweed_toolbar.dart';
import '../tajweed/ui/screens/tajweed_settings_screen.dart';
import '../tajweed/ui/widgets/interactive_verse.dart'; import '../tajweed/models/word_model.dart';
import '../tajweed/ui/widgets/ayah_player.dart';

class TrackingScreen extends ConsumerStatefulWidget {
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
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  int? _lastAyah;
  bool _isAutoScrolling = false;
  Timer? _autoScrollTimer;
  Ticker? _scrollTicker;

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
        state == AppLifecycleState.inactive) {
      ref.read(muaalemControllerProvider.notifier).cancelAll();
      if (widget.isRecording) {
        widget.onToggleRecord();
      }
      // Ensure the mic is stopped and DIO requests are cancelled
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerUpdate);
    _scroll.dispose();
    _scrollTicker?.dispose();
    WakelockPlus.disable(); // Always disable wakelock when exiting the screen
    ref
        .read(audioServiceProvider)
        .dispose(); // Force release the record instance
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
        _scrollToAyah(ayah);
      }
    }
  }

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
          final estimated = idx * 100.0;
          _scroll.animateTo(
            estimated.clamp(0.0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
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

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsDialog(),
    );
  }

  void _showTajweedSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TajweedSettingsScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🛠️ [TrackingScreen] build() triggered');
    final top = MediaQuery.of(context).padding.top;
    final app = AppState.instance;
    final muaalemState = ref.watch(muaalemControllerProvider);

    return ListenableBuilder(
      listenable: app,
      builder: (_, _) {
        debugPrint(
          '🛠️ [TrackingScreen] ListenableBuilder triggered, mode: ${app.currentMode}',
        );
        final c = app.colors;
        final isTajweed = app.currentMode == AppMode.tajweed;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: c.bg,
            body: Stack(
              fit: StackFit.expand,
              children: [
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
                    child: _buildHeader(c, app, top, isTajweed),
                  ),
                ),

                // Main Content
                Positioned.fill(
                  top: top + 60,
                  bottom: 120, // space for bottom bars
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: isTajweed
                        ? _buildTajweedContent(c, app, muaalemState)
                        : _buildWordCheckerContent(c, app),
                  ),
                ),

                // Bottom Action Bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
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
                      child: isTajweed
                          ? _buildTajweedToolbar(c, muaalemState)
                          : BottomActionBar(
                              key: const ValueKey('word_checker_bar'),
                              isRecording: widget.isRecording,
                              isLoadingEngine: widget.isLoadingEngine,
                              isAutoScrolling: _isAutoScrolling,
                              c: c,
                              onMic: widget.onToggleRecord,
                              onToggleAutoScroll: _toggleAutoScroll,
                              onSettingsTap: _showSettingsDialog,
                              onTajweedTap: () {
                                if (widget.isRecording) {
                                  widget.onToggleRecord();
                                }
                                app.setMode(AppMode.tajweed);
                                widget.controller.unloadEngine();
                              },
                            ),
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

  Widget _buildHeader(ThemeColors c, AppState app, double top, bool isTajweed) {
    if (widget.isRecording || _isAutoScrolling) {
      return const SizedBox.shrink(key: ValueKey('empty_header'));
    }

    return Container(
      key: ValueKey('header_$isTajweed'),
      margin: EdgeInsets.only(top: top + 4, left: 24, right: 24, bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
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
        border: Border.all(color: c.border.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _showSurahPicker,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final displayVerses = widget.controller.repository
                          .getSurah(widget.controller.targetSurah);
                      return Text(
                        app.isArabic
                            ? displayVerses.first.surahName
                            : displayVerses.first.surahNameEn,
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
          const SizedBox(width: 8),
          GestureDetector(
            onTap: isTajweed ? _showTajweedSettings : _showSettingsDialog,
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
    );
  }

  Widget _buildTajweedContent(
    ThemeColors c,
    AppState app,
    MuaalemState muaalemState,
  ) {
    return ListenableBuilder(
      key: const ValueKey('tajweed_content_root'),
      listenable: widget.controller,
      builder: (context, _) {
        debugPrint(
          '🛠️ [TrackingScreen] _buildTajweedContent ListenableBuilder triggered',
        );
        final match = widget.controller.currentMatchedVerse;
        final surahVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );
        final v =
            match?.verse ?? (surahVerses.isNotEmpty ? surahVerses.first : null);

        if (v == null) {
          debugPrint(
            '🛠️ [TrackingScreen] _buildTajweedContent returning SizedBox.shrink because v is null',
          );
          return const SizedBox.shrink();
        }

        debugPrint(
          '🛠️ [TrackingScreen] _buildTajweedContent rendering InteractiveVerse',
        );
        return GestureDetector(
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 300) return; // Ignore small swipes

            final surah = widget.controller.targetSurah;
            final currentAyah = v.ayah;

            if (velocity > 300) {
              // Swiped Right -> Previous Ayah
              if (currentAyah > 1) {
                final prevVerse = widget.controller.repository.getVerse(
                  surah,
                  currentAyah - 1,
                );
                if (prevVerse != null)
                  widget.controller.forceActiveAyah(prevVerse);
              }
            } else if (velocity < -300) {
              // Swiped Left -> Next Ayah
              final nextVerse = widget.controller.repository.getVerse(
                surah,
                currentAyah + 1,
              );
              if (nextVerse != null)
                widget.controller.forceActiveAyah(nextVerse);
            }
          },
          child: Container(
            key: const ValueKey('tajweed_content'),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (muaalemState is MuaalemError)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: c.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          muaalemState.message,
                          style: TextStyle(color: c.red),
                        ),
                      ),
                    ),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        AyahPlayer(
                          sura: widget.controller.targetSurah,
                          aya: v.ayah,
                        ),
                        const SizedBox(height: 16),
                        InteractiveVerse(
                          words: WordModel.buildFrom(
                            v,
                            muaalemState is MuaalemSuccess
                                ? muaalemState.result
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (muaalemState is MuaalemSuccess)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: c.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "النتيجة",
                              style: TextStyle(
                                color: c.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "تم التقييم بنجاح. أخطاء التجويد: ${muaalemState.result.sifatErrors?.length ?? 0}",
                              style: TextStyle(color: c.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWordCheckerContent(ThemeColors c, AppState app) {
    return Builder(
      key: const ValueKey('word_checker_content'),
      builder: (context) {
        debugPrint('🛠️ [TrackingScreen] _buildWordCheckerContent triggered');
        final displayVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );
        debugPrint(
          '🛠️ [TrackingScreen] _buildWordCheckerContent displayVerses length: ${displayVerses.length}',
        );

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
                widget.controller.setManualAyah(v.surah, v.ayah);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTajweedToolbar(ThemeColors c, MuaalemState state) {
    final match = widget.controller.currentMatchedVerse;
    final surahVerses = widget.controller.repository.getSurah(
      widget.controller.targetSurah,
    );
    final v =
        match?.verse ?? (surahVerses.isNotEmpty ? surahVerses.first : null);
    final isRecording = state is MuaalemRecording;
    final isAnalyzing = state is MuaalemProcessing;
    final progress = state is MuaalemProcessing ? state.progress : 0.0;

    return TajweedToolbar(
      key: const ValueKey('tajweed_toolbar'),
      isRecording: isRecording,
      isAnalyzing: isAnalyzing,
      uploadProgress: progress,
      c: c,
      currentAyah: v?.ayah ?? 1,
      currentSurahName: v?.surahName ?? '',
      onExit: () {
        ref.read(muaalemControllerProvider.notifier).cancelAll();
        AppState.instance.setMode(AppMode.wordChecker);
        widget.controller.reloadEngine();
      },
      onSelectAyah: () => _showSurahPicker(),
      onRecord: () async {
        if (isRecording) {
          if (v != null) {
            await ref
                .read(muaalemControllerProvider.notifier)
                .stopAndAnalyze(sura: v.surah, aya: v.ayah);
          }
        } else {
          // Hardware Microphone Contention Fix:
          // If Sherpa ASR is actively holding the microphone, force it to stop
          // before Muaalem attempts to claim it.
          if (widget.isRecording) {
            widget.onToggleRecord();
          }
          widget.controller.finalize();

          ref.read(muaalemControllerProvider.notifier).reset();
          await ref.read(muaalemControllerProvider.notifier).startRecording();
        }
      },
    );
  }
}
