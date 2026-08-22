/// بسم الله الرحمن الرحيم
///
/// ReciteQuran — Real-time Quran recitation tracking app.
///
/// Architecture:
///   main.dart → _Orchestrator (manages engine + audio + controller)
///            → TrackingScreen (UI)
///
/// The _Orchestrator initializes:
///   1. Microphone permissions
///   2. Sherpa-ONNX ASR engine (in a background Isolate)
///   3. Quran metadata (quran.json)
///   4. HighlightingController (bridges ASR → UI)
///
/// Recording flow:
///   AudioProcessor captures mic → feeds chunks to Controller →
///   Controller sends to SherpaEngine (Isolate) → gets transcription →
///   matches words against expected Quran text → updates highlighting
library;

import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'package:recite_quran/recite_quran.dart';
import 'state/app_state.dart';
import 'ui/tracking_screen.dart';
import 'ui/widgets/dialogs/theme_selection_dialog.dart';
import 'ui/widgets/dialogs/permission_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

// //logs
List<String> globalSessionLogs = [];

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize iOS audio session to disable VPIO processing for accurate ASR
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final session = await AudioSession.instance;
          await session.configure(
            AudioSessionConfiguration(
              avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
              avAudioSessionCategoryOptions:
                  AVAudioSessionCategoryOptions.defaultToSpeaker |
                  AVAudioSessionCategoryOptions.allowBluetooth,
              avAudioSessionMode: AVAudioSessionMode.measurement,
            ),
          );
        } catch (e) {
          DebugLogger.logSimple(
            'AudioSession',
            'Failed to configure AudioSession: $e',
          );
        }
      }

      if (kReleaseMode) {
        debugPrint = (String? message, {int? wrapWidth}) {
          // //logs: Send debugPrint into our custom print zone instead of the void!
          if (message != null) print(message);
        };
      }

      if (!kIsWeb) {
        // Transparent system bars for immersive experience
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }

      await AppState.instance.load();
      runApp(const QuranApp());
    },
    (error, stack) {
      DebugLogger.logSimple('Error', 'Uncaught Error: $error');
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        // //logs
        globalSessionLogs.add('[${DateTime.now().toIso8601String()}] $line');
        if (globalSessionLogs.length > 5000) {
          globalSessionLogs.removeRange(0, 1000);
        }

        if (!kReleaseMode || kIsWeb) {
          parent.print(zone, line);
        }
      },
    ),
  );
}

/// Root widget — rebuilds MaterialApp when theme/language changes.
class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final ThemeColors c = AppState.instance.colors;
        final isDark = AppState.instance.isDarkMode;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Recite Quran - اتلو القران',
          theme: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: c.bg,
            colorScheme: isDark
                ? ColorScheme.dark(primary: c.gold, surface: c.surface)
                : ColorScheme.light(primary: c.gold, surface: c.surface),
          ),
          builder: (context, child) {
            if (!kIsWeb) return child!;
            return Scaffold(
              backgroundColor: isDark ? Colors.black : const Color(0xFFE5E7EB),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: c.bg,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 25,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
          home: const _Orchestrator(),
        );
      },
    );
  }
}

/// The conductor — owns the ASR engine, audio processor, and controller.
/// Manages the full lifecycle of a recording session.
class _Orchestrator extends StatefulWidget {
  const _Orchestrator();
  @override
  State<_Orchestrator> createState() => _OrchestratorState();
}

class _OrchestratorState extends State<_Orchestrator> {
  final SherpaEngine _engine = SherpaEngine();
  final AudioProcessor _audio = AudioProcessor();
  late final VoiceSearchController _voiceSearchCtrl;

  QuranRepository? _repo;
  HighlightingController? _ctrl;

  bool _isInit = true;
  bool _isRecording = false;
  String _initStatus = 'Starting…';
  bool _isToggling = false; // Prevents double-tap hardware crashes
  bool _isEngineLoading =
      false; // Tracks if ASR is compiling/extracting when user presses record
  bool _isVoiceSearching = false;
  String _voiceSearchAsrText = '';

  // Timer logic removed, we now rely on Sherpa's VAD endpoint with 4s silence

  @override
  void initState() {
    super.initState();
    _voiceSearchCtrl = VoiceSearchController(engine: _engine);

    // Global subscription for Voice Search text and Endpoint auto-stopping
    _engine.transcriptionStream.listen((res) {
      if (_isVoiceSearching && mounted) {
        setState(() {
          _voiceSearchAsrText = res.text;
        });

        // REAL-TIME SEARCH EVALUATION
        _voiceSearchCtrl.processRealtime(res.text).then((rtResult) {
          if (rtResult != null) {
            // Unique match found! Bypass VAD and jump immediately.
            _stopVoiceSearch(precalculatedResult: rtResult);
          } else if (res.isFinal) {
            // Sherpa's VAD detected 4s of silence
            DebugLogger.log(
              'VoiceSearch',
              'Auto-stopping on VAD endpoint (4s silence)',
            );
            _stopVoiceSearch();
          }
        });
      }
    });

    _init();
    // Defer update check by 5s so Play Core native code doesn't compete
    // with XNNPACK/ONNX initialization for memory and IPC resources
    // during the critical startup window.
    Future.delayed(const Duration(seconds: 5), _checkForUpdates);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await FlutterDisplayMode.setHighRefreshRate();
        } catch (e) {
          DebugLogger.logSimple(
            'DisplayMode',
            'Failed to set high refresh rate: $e',
          );
        }
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      const platform = MethodChannel('com.recitequran.app/playstore');
      final bool hasPlayStore = await platform.invokeMethod('isPlayStoreInstalled');
      
      if (!hasPlayStore) {
        DebugLogger.logSimple('Update', 'Play Store missing (LineageOS). Bypassing Play Core API.');
        return;
      }

      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      DebugLogger.logSimple('Update', "Play Core update check aborted safely: $e");
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  /// Sequential initialization pipeline in the background.
  /// Does not block the splash screen for the heavy model extraction.
  Future<void> _init() async {
    try {
      if (mounted) setState(() => _initStatus = 'Preparing ASR engine…');
      _engine.initialize(); // Fire-and-forget in background Isolate

      if (mounted) setState(() => _initStatus = 'Loading Quran database…');
      final service = QuranMetadataService();
      _repo = QuranRepository(service);
      await _repo!.loadSurahAsync(1);

      _voiceSearchCtrl.preloadIndex(); // Fire-and-forget in background

      _ctrl = HighlightingController(
        engine: _engine,
        repository: _repo!,
        isTajweed: AppState.instance.currentMode == AppMode.tajweed,
        // onAyahChanged is called on explicit user actions (manual tap, session start).
        // Automatic ayah-advance uses flushAndResetForNextAyah() inside
        // HighlightingController itself — that handles the flush-before-reset pattern.
        // We only clear the audio processor's frame buffer here (which is a no-op anyway).
        onAyahChanged: () {
          _audio.clearBuffer();
          // DO NOT call _engine.resetBuffer() here.
          // The correct reset path at ayah boundaries is flushAndResetForNextAyah()
          // which is triggered from _onIsolateWordMatched in HighlightingController.
          // Calling resetBuffer() here would wipe the live cache before the flush,
          // silently discarding the final word's right-context tail every ayah.
        },
      );
      if (!kIsWeb) {
        try {
          WakelockPlus.enable();
        } catch (_) {}
      }

      if (mounted) setState(() => _isInit = false);

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = await SharedPreferences.getInstance();
        final hasChosenTheme = prefs.getBool('has_chosen_theme') ?? false;
        if (!hasChosenTheme && mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => ThemeSelectionDialog(
              onThemeSelected: () {
                prefs.setBool('has_chosen_theme', true);
                Navigator.of(ctx).pop();
              },
            ),
          );
        }
      });
    } catch (e) {
      DebugLogger.logSimple('INIT', '❌ Error: $e');
      if (mounted) setState(() => _initStatus = 'Error: $e');
    }
  }

  /// Toggles recording on/off with hardware-safe locking.
  Future<void> _toggleRecord() async {
    if (_isToggling) return;
    _isToggling = true;

    try {
      if (_isRecording) {
        await _audio.stop();
        _engine.resetBuffer();
        _ctrl?.finalize();
        if (!kIsWeb) {
          try { await WakelockPlus.disable(); } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _isRecording = false;
          });
        }
      } else {
        if (!kIsWeb) {
          final status = await Permission.microphone.request();
          if (status != PermissionStatus.granted) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) =>
                    const PermissionDialog(reason: PermissionReason.tracking),
              );
            }
            _isToggling = false;
            return;
          }
        }

        // Ensure engine is ready (may still be initializing in background)
        if (!_engine.isInitialized) {
          if (mounted) setState(() => _isEngineLoading = true);
          try {
            await _engine.initialize();
          } finally {
            if (mounted) setState(() => _isEngineLoading = false);
          }
        }

        if (!kIsWeb) {
          try { await WakelockPlus.enable(); } catch (_) {}
        }
        _engine.resetBuffer();

        // Instant UI feedback before hardware mic starts
        if (mounted) setState(() => _isRecording = true);

        if (_ctrl != null) {
          _ctrl!.startRecordingSession();
          _audio
              .start(
                onChunk: (chunk, isFinal) =>
                    _ctrl?.feed(chunk, isFinal: isFinal),
              )
              .catchError((e) {
                DebugLogger.logSimple('AUDIO', '❌ ERROR: $e');
                if (mounted) setState(() => _isRecording = false);
              });
        }
      }
    } catch (e) {
      DebugLogger.logSimple('RECORD', '❌ ERROR: $e');
      if (mounted)
        setState(() {
          _isRecording = false;
        });
    } finally {
      _isToggling = false;
    }
  }

  /// Toggles global voice search across the Quran
  Future<void> _toggleVoiceSearch() async {
    if (_isToggling) return;

    if (_isVoiceSearching) {
      await _stopVoiceSearch();
    } else {
      if (_isRecording) {
        await _toggleRecord();
      }
      await _startVoiceSearch();
    }
  }

  Future<void> _startVoiceSearch() async {
    if (_isVoiceSearching || _isToggling) return;
    _isToggling = true;

    try {
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) =>
                  const PermissionDialog(reason: PermissionReason.voiceSearch),
            );
          }
          _isToggling = false;
          return;
        }
      }

      if (!_engine.isInitialized) {
        if (mounted) setState(() => _isEngineLoading = true);
        try {
          await _engine.initialize();
        } finally {
          if (mounted) setState(() => _isEngineLoading = false);
        }
      }

      // Suspend highlighting controller so it doesn't consume/reset the engine buffer!
      _ctrl?.finalize();

      // SHOW UI IMMEDIATELY!
      if (mounted) {
        setState(() {
          _isVoiceSearching = true;
          _voiceSearchAsrText = '';
        });
      }

      await _voiceSearchCtrl.startSearch();
      if (!kIsWeb) {
        try { await WakelockPlus.enable(); } catch (_) {}
      }

      _audio
          .start(
            onChunk: (chunk, isFinal) {
              _engine.transcribe(chunk, isFinal: isFinal);
            },
          )
          .catchError((e) {
            DebugLogger.logSimple('AUDIO', '❌ ERROR in Voice Search: $e');
            if (mounted) setState(() => _isVoiceSearching = false);
          });
    } catch (e) {
      DebugLogger.logSimple('VOICE_SEARCH', '❌ START ERROR: $e');
      if (mounted) setState(() => _isVoiceSearching = false);
    } finally {
      _isToggling = false;
    }
  }

  Future<void> _stopVoiceSearch({AnchorResult? precalculatedResult}) async {
    if (!_isVoiceSearching || _isToggling) return;
    _isToggling = true;

    try {
      await _audio.stop();
      _engine.resetBuffer();
      if (!kIsWeb) {
        try { await WakelockPlus.disable(); } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isVoiceSearching = false;
        });
      }

      AnchorResult? result = precalculatedResult;
      if (result == null) {
        result = await _voiceSearchCtrl.stopSearch(_voiceSearchAsrText);
      }
      if (result != null && _ctrl != null) {
        // Automatically navigate to the found Ayah!
        await _ctrl!.setTargetSurah(result.surah);
        _ctrl!.setManualAyah(result.surah, result.ayah);

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم الانتقال إلى سورة ${result.surah} آية ${result.ayah}',
              ),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppState.instance.colors.gold,
            ),
          );
        }
      } else {
        // Fallback: resume previous state if no Ayah was found
        _ctrl?.resumeTracking();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم العثور على الآية، حاول مرة أخرى'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      DebugLogger.logSimple('VOICE_SEARCH', '❌ STOP ERROR: $e');
    } finally {
      _isToggling = false;
    }
  }

  /// Warm, elegant splash screen with Quran ayah.
  Widget _loadingScreen() {
    final ThemeColors c = AppState.instance.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // ── Decorative top line ──
            Container(
              width: 60,
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    c.gold.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Quran Ayah ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'وَلَقَدْ يَسَّرْنَا الْقُرْآنَ لِلذِّكْرِ فَهَلْ مِن مُّدَّكِرٍ',
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    color: c.text.withValues(alpha: 0.7),
                    fontSize: 24,
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Decorative bottom line ──
            Container(
              width: 60,
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    c.gold.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            const Spacer(flex: 2),

            // ── Loading indicator ──
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(
                  c.gold.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _initStatus,
              style: TextStyle(
                color: c.muted.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInit) return _loadingScreen();
    return TrackingScreen(
      controller: _ctrl!,
      isRecording: _isRecording,
      isLoadingEngine: _isEngineLoading,
      isVoiceSearching: _isVoiceSearching,
      voiceSearchText: _voiceSearchAsrText,
      onToggleRecord: _toggleRecord,
      onVoiceSearchToggle: _toggleVoiceSearch,
      isVoiceSearchLoading: _voiceSearchCtrl.isIndexLoading,
      onClearBuffer: () {
        _engine.resetBuffer();
        _audio.clearBuffer();
      },
    );
  }
}
