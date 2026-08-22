import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:recite_quran/recite_quran.dart';
import '../main.dart';
import '../state/app_state.dart';
import 'widgets/dialogs/voice_search_dialog.dart';
import 'widgets/mic_bar.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/surah_picker.dart';
import 'widgets/verse_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/dialogs/speed_selection_dialog.dart';

/// Main interactive screen for real-time recitation tracking and reading.
/// Manages scrolling, distraction-free reading headers, and mode switches.
class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final String voiceSearchText;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;
  final bool isLoadingEngine;
  final ValueNotifier<bool>? isVoiceSearchLoading;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    this.voiceSearchText = '',
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
    this.isLoadingEngine = false,
    this.isVoiceSearchLoading,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final ListController _listController = ListController();
  final Map<int, GlobalKey> _keys = {};
  final ValueNotifier<String> _voiceSearchNotifier = ValueNotifier('');

  int? _lastAyah;
  int? _lastSurah;
  bool _isAutoScrolling = false;
  
  bool _showTajweedBanner = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      try { WakelockPlus.enable(); } catch (_) {}
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;

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
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      try { WakelockPlus.disable(); } catch (_) {}
    }
    widget.controller.removeListener(_onControllerUpdate);
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    _scroll.dispose();
    _voiceSearchNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _lastAyah = null;
      final match = widget.controller.currentMatchedVerse;
      if (match != null && match.verse.surah == widget.controller.targetSurah) {
        _forceScrollToAyah(match.verse.ayah);
      }
    }

    if (widget.voiceSearchText != oldWidget.voiceSearchText) {
      _voiceSearchNotifier.value = widget.voiceSearchText;
    }

    if (widget.isVoiceSearching && !oldWidget.isVoiceSearching) {
      _voiceSearchNotifier.value = widget.voiceSearchText;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          VoiceSearchDialog.show(
            context, 
            onStop: widget.onVoiceSearchToggle,
            isLoading: widget.isVoiceSearchLoading,
          );
        }
      });
    } else if (!widget.isVoiceSearching && oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _onControllerUpdate() {
    if (widget.controller.targetSurah != _lastSurah) {
      if (mounted) {
        setState(() {
          _lastSurah = widget.controller.targetSurah;
          _keys.clear();
          _lastAyah = null;
        });
      } else {
        _lastSurah = widget.controller.targetSurah;
        _keys.clear();
        _lastAyah = null;
      }

      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    }
  }

  void _onActiveAyahChanged() {
    final active = widget.controller.activeAyah.value;
    final match = widget.controller.currentMatchedVerse;
    if (active != null &&
        active != _lastAyah &&
        match != null &&
        match.verse.surah == widget.controller.targetSurah) {
      _lastAyah = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _forceScrollToAyah(active);
        }
      });
    }
  }

  void _forceScrollToAyah(int ayah) {
    if (!_scroll.hasClients) return;

    if (ayah == 1) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _listController.jumpToItem(
      index: ayah,
      scrollController: _scroll,
      alignment: 0.5,
    );
  }

  void _toggleAutoScroll() async {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.pixels);
      }
      if (!kIsWeb) {
        try { WakelockPlus.disable(); } catch (_) {}
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final hasChosenSpeed = prefs.getBool('has_chosen_speed') ?? false;
      if (!hasChosenSpeed && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => SpeedSelectionDialog(
            onSpeedSelected: () {
              prefs.setBool('has_chosen_speed', true);
              Navigator.of(ctx).pop();
              _toggleAutoScroll();
            },
          ),
        );
        return;
      }

      widget.controller.clearHighlights();
      widget.controller.finalize();
      setState(() => _isAutoScrolling = true);
      _startAutoScrollLoop();
      if (!kIsWeb) {
        try { WakelockPlus.enable(); } catch (_) {}
      }
    }
  }

  void _startAutoScrollLoop() {
    if (!_isAutoScrolling || !mounted || !_scroll.hasClients) return;

    double baseSpeed =
        ((AppState.instance.fontSize / 24.0) * 1.5) * (16.0 / 50.0);
    const speedMultipliers = [0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0];
    int speedIndex = AppState.instance.autoScrollSpeed.clamp(
      0,
      speedMultipliers.length - 1,
    );
    double speedPerFrame = baseSpeed * speedMultipliers[speedIndex];
    final double pixelsPerSec = speedPerFrame * 60;

    final position = _scroll.position;
    final distance = position.maxScrollExtent - position.pixels;

    if (distance <= 0.5) {
      setState(() => _isAutoScrolling = false);
      if (!kIsWeb) {
        try { WakelockPlus.disable(); } catch (_) {}
      }
      return;
    }

    final durationSeconds = distance / pixelsPerSec;

    _scroll
        .animateTo(
          position.maxScrollExtent,
          duration: Duration(milliseconds: (durationSeconds * 1000).toInt()),
          curve: Curves.linear,
        )
        .then((_) {
          if (mounted && _isAutoScrolling) {
            if (_scroll.hasClients &&
                (_scroll.position.maxScrollExtent - _scroll.position.pixels) >
                    2.0) {
              _startAutoScrollLoop();
            } else {
              setState(() => _isAutoScrolling = false);
              if (!kIsWeb) {
                try { WakelockPlus.disable(); } catch (_) {}
              }
            }
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
            widget.onToggleRecord();
          }
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
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
      builder: (context, _) {
        final c = app.colors;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: c.bg,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Main Verse Content
                Positioned.fill(child: _buildVerseContent(c, app, top)),

                // Top Floating Header
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
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
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
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
                      isLoadingEngine: widget.isLoadingEngine,
                      isVoiceSearching: widget.isVoiceSearching,
                      isAutoScrolling: _isAutoScrolling,
                      c: c,
                      onMic: () {
                        if (_showTajweedBanner) setState(() => _showTajweedBanner = false);
                        if (widget.isVoiceSearching) {
                          widget.onVoiceSearchToggle();
                        } else {
                          widget.onToggleRecord();
                        }
                      },
                      onToggleAutoScroll: () {
                        if (_showTajweedBanner) setState(() => _showTajweedBanner = false);
                        _toggleAutoScroll();
                      },
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
      padding: EdgeInsets.only(top: top + 10, left: 14, right: 14, bottom: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Dropdown Banner
          AnimatedPositioned(
            duration: Duration(milliseconds: _showTajweedBanner ? 600 : 300),
            curve: _showTajweedBanner ? Curves.elasticOut : Curves.easeOutCubic,
            top: _showTajweedBanner ? 50 : 0, // Slides out from beneath the 56px container
            left: 16,
            right: 16,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showTajweedBanner ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.only(top: 16, bottom: 8, left: 12, right: 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                  border: Border(
                    bottom: BorderSide(color: c.gold.withValues(alpha: 0.3)),
                    left: BorderSide(color: c.gold.withValues(alpha: 0.3)),
                    right: BorderSide(color: c.gold.withValues(alpha: 0.3)),
                  ),
                ),
                child: Text(
                  app.isArabic
                      ? 'تم تفعيل التجويد و يمكنك الضغط على الكلمات باللون الاصفر لمعرفة نوع الخطأ'
                      : 'Tajweed Enabled. Tap on yellow words to see error details.',
                  style: TextStyle(color: c.text, height: 1.4, fontWeight: FontWeight.w600, fontSize: 12),
                  textAlign: TextAlign.center,
                  textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
                ),
              ),
            ),
          ),
          
          // The Actual Header Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.border.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Surah Selector
            Flexible(
              flex: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: GestureDetector(
                  onTap: _showSurahPicker,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Row(
                          children: [
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
                                        fontFamily: app.isArabic ? 'HafsSmart' : null,
                                        color: c.gold,
                                        fontSize: app.isArabic ? 18 : 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (constraints.maxWidth > 40) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: c.gold,
                                size: 20,
                              ),
                            ],
                          ],
                        );
                      }
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Action Buttons
            Expanded(
              flex: 6,
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionBtn(
                      icon: Icons.auto_stories_rounded,
                      label: app.isArabic ? 'قراءة' : 'Read',
                      color: c.text,
                      onTap: _toggleAutoScroll,
                    ),
                  ),
                  Expanded(
                    child: _buildActionBtn(
                      icon: app.isBlurMode
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      label: app.isArabic ? 'إخفاء' : 'Hide',
                      color: app.isBlurMode ? c.green : c.text,
                      onTap: app.toggleBlurMode,
                    ),
                  ),
                  Expanded(
                    child: _buildActionBtn(
                      icon: Icons.format_color_text_rounded,
                      label: app.isArabic ? 'تجويد' : 'Tajweed',
                      color: app.currentMode == AppMode.tajweed
                          ? c.green
                          : c.text,
                      onTap: () {
                        final newMode = app.currentMode == AppMode.tajweed
                            ? AppMode.wordChecker
                            : AppMode.tajweed;
                        app.setMode(newMode);
                        widget.controller.setTajweedMode(
                          newMode == AppMode.tajweed,
                        );

                        if (newMode == AppMode.tajweed) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          setState(() => _showTajweedBanner = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) setState(() => _showTajweedBanner = false);
                          });
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildActionBtn(
                      icon: Icons.settings_rounded,
                      label: app.isArabic ? 'إعدادات' : 'Settings',
                      color: c.text,
                      onTap: _showSettingsDialog,
                      onLongPress: () async {
                        try {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Preparing logs...',
                                textDirection: TextDirection.ltr,
                              ),
                            ),
                          );
                          final String allLogs = globalSessionLogs.join('\n');
                          await SharePlus.instance.share(
                            ShareParams(
                              text: allLogs.isNotEmpty
                                  ? allLogs
                                  : 'No logs recorded.',
                              subject: 'ReciteQuran Logs',
                            ),
                          );
                        } catch (e) {
                          DebugLogger.logSimple(
                            'TrackingScreen',
                            "Error preparing logs: $e",
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ],
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerseContent(ThemeColors c, AppState app, double top) {
    return Builder(
      key: const ValueKey('verse_list_content'),
      builder: (context) {
        final displayVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );

        final bool isMainRec = widget.isRecording;
        final topPadding = (isMainRec || _isAutoScrolling)
            ? top + 16
            : top + 72;
        final bottomPadding = (isMainRec || _isAutoScrolling) ? 140.0 : 200.0;

        return CustomScrollView(
          controller: _scroll,
          physics: _isAutoScrolling
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          slivers: [
            SuperSliverList(
              listController: _listController,
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  if (i == 0) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      height: topPadding,
                    );
                  }

                  if (i == displayVerses.length + 1) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      height: bottomPadding,
                    );
                  }

                  final v = displayVerses[i - 1];

                  return VerseRow(
                    key: ValueKey('verse_${v.surah}_${v.ayah}'),
                    verse: v,
                    controller: widget.controller,
                    isAutoScrolling: _isAutoScrolling,
                    onTap: () {
                      widget.controller.setManualAyah(v.surah, v.ayah);
                    },
                    onWordErrorTap: null,
                  );
                },
                childCount: displayVerses.length + 2,
              ),
            ),
          ],
        );
      },
    );
  }
}
