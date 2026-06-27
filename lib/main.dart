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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'state/app_state.dart';
import 'engine/sherpa_engine.dart';
import 'tracking/highlighting_controller.dart';
import 'audio/audio_processor.dart';
import 'data/quran_data.dart';
import 'ui/tracking_screen.dart';
import 'tracking/voice_search_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Transparent system bars for immersive experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await AppState.instance.load();
  runApp(const QuranApp());
}

/// Root widget — rebuilds MaterialApp when theme/language changes.
class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (_, _) {
        final ThemeColors c = AppState.instance.colors;
        final isDark = AppState.instance.isDarkMode;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: c.bg,
            colorScheme: isDark
                ? ColorScheme.dark(primary: c.gold, surface: c.surface)
                : ColorScheme.light(primary: c.gold, surface: c.surface),
          ),
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
  bool _isLoadingEngine = false;
  bool _isVoiceSearching = false;
  String _voiceSearchAsrText = '';

  @override
  void initState() {
    super.initState();
    _voiceSearchCtrl = VoiceSearchController(engine: _engine);
    
    // Global subscription for Voice Search text
    _engine.transcriptionStream.listen((res) {
      if (_isVoiceSearching && mounted) {
        setState(() {
          _voiceSearchAsrText = res.text;
        });

        // REAL-TIME SEARCH EVALUATION
        final rtResult = _voiceSearchCtrl.processRealtime(res.text);
        if (rtResult != null) {
          // Unique match found! Bypass VAD and jump immediately.
          _stopVoiceSearch(precalculatedResult: rtResult);
        }
      }
    });

    _init();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  /// Sequential initialization pipeline.
  /// Each step updates the splash screen status text.
  Future<void> _init() async {
    try {
      if (mounted) setState(() => _initStatus = 'Requesting permissions…');
      await Permission.microphone.request();

      if (mounted) setState(() => _initStatus = 'Preparing ASR engine…');
      await _engine.preExtractAssets();
      _engine.initialize(); // Fire-and-forget in background Isolate

      if (mounted) setState(() => _initStatus = 'Loading Quran database…');
      final service = QuranMetadataService();
      _repo = QuranRepository(service);
      await _repo!.loadSurahAsync(1);

      _ctrl = HighlightingController(
        engine: _engine,
        repository: _repo!,
        // Flush stale audio on ayah transitions to prevent cross-ayah
        // ghosting (old words matching new ayah's text).
        onAyahChanged: () {
          _audio.clearBuffer();
          _engine.resetBuffer();
        },
      );
      await WakelockPlus.enable();

      if (mounted) setState(() => _isInit = false);
    } catch (e) {
      debugPrint('❌ INIT: $e');
      if (mounted) setState(() => _initStatus = 'Error: $e');
    }
  }

  /// Toggles recording on/off with hardware-safe locking.
  Future<void> _toggleRecord() async {
    if (_isToggling) return;
    _isToggling = true;

    try {
      if (_isRecording) {
        // Get any remaining audio in the pipeline
        await _audio.stopAndGetAudio();
        // if (tail.isNotEmpty) {
        //   _ctrl?.feed(tail, isFinal: true);
        //   // Allow the background Isolate time to finish inference
        //   await Future.delayed(const Duration(milliseconds: 500));
        // }

        _engine.resetBuffer();
        _ctrl?.finalize();
        await WakelockPlus.disable();
        if (mounted)
          setState(() {
            _isRecording = false;
          });
      } else {
        // Ensure engine is ready (may still be initializing in background)
        if (!_engine.isInitialized) {
          // Trigger initialize just in case, but DON'T await
          _engine.initialize(); 
        }

        await WakelockPlus.enable();
        _engine.resetBuffer();

        // Instant UI feedback before hardware mic starts
        if (mounted) setState(() => _isRecording = true);

        if (_ctrl != null) {
          _ctrl!.startRecordingSession();
          // Start audio stream without blocking the UI
          _audio
              .start(
                onChunk: (chunk, isFinal) =>
                    _ctrl?.feed(chunk, isFinal: isFinal),
              )
              .catchError((e) {
                debugPrint('❌ AUDIO ERROR: $e');
                if (mounted) setState(() => _isRecording = false);
              });
        }
      }
    } catch (e) {
      debugPrint('❌ RECORD ERROR: $e');
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
      if (!_engine.isInitialized) {
        _engine.initialize(); 
      }

      // Suspend highlighting controller so it doesn't consume/reset the engine buffer!
      _ctrl?.finalize();

      await _voiceSearchCtrl.startSearch();
      await WakelockPlus.enable();
      
      if (mounted) {
        setState(() {
          _isVoiceSearching = true;
          _voiceSearchAsrText = '';
        });
      }

      _audio.start(
        onChunk: (chunk, isFinal) => _engine.transcribe(chunk, isFinal: isFinal),
        onVadOff: () {
          if (_isVoiceSearching && mounted && _voiceSearchAsrText.trim().isNotEmpty) {
            debugPrint('[VoiceSearch] Auto-stopping search due to VAD OFF (silence detected)');
            _stopVoiceSearch();
          }
        },
      ).catchError((e) {
        debugPrint('❌ AUDIO ERROR in Voice Search: $e');
        if (mounted) setState(() => _isVoiceSearching = false);
      });
      
      // Note: transcriptionStream listen is now handled in initState to prevent duplicates.

    } catch (e) {
      debugPrint('❌ VOICE SEARCH START ERROR: $e');
      if (mounted) setState(() => _isVoiceSearching = false);
    } finally {
      _isToggling = false;
    }
  }

  Future<void> _stopVoiceSearch({AnchorResult? precalculatedResult}) async {
    if (!_isVoiceSearching || _isToggling) return;
    _isToggling = true;

    try {
      await _audio.stopAndGetAudio();
      _engine.resetBuffer();
      await WakelockPlus.disable();

      if (mounted) {
        setState(() {
          _isVoiceSearching = false;
        });
      }

      final result = precalculatedResult ?? _voiceSearchCtrl.stopSearch(_voiceSearchAsrText);
      if (result != null && _ctrl != null) {
        // Automatically navigate to the found Ayah!
        await _ctrl!.setTargetSurah(result.surah);
        _ctrl!.setManualAyah(result.surah, result.ayah);
        
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم الانتقال إلى سورة ${result.surah} آية ${result.ayah}'),
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
      debugPrint('❌ VOICE SEARCH STOP ERROR: $e');
    } finally {
      _isToggling = false;
    }
  }

  /// Modern splash screen with Quran ayah.
  Widget _loadingScreen() {
    final ThemeColors c = AppState.instance.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // Quran ayah — وَلَقَدْ يَسَّرْنَا الْقُرْآنَ لِلذِّكْرِ فَهَلْ مِن مُّدَّكِرٍ
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'وَلَقَدْ يَسَّرْنَا الْقُرْآنَ لِلذِّكْرِ فَهَلْ مِن مُّدَّكِرٍ',
                style: TextStyle(
                  fontFamily: 'QPC_Hafs',
                  color: c.text.withValues(alpha: 0.6),
                  fontSize: 22,
                  height: 2.0,
                ),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'القمر ١٧',
              style: TextStyle(
                color: c.muted.withValues(alpha: 0.4),
                fontSize: 11,
              ),
              textDirection: TextDirection.rtl,
            ),

            const Spacer(flex: 2),

            // Subtle loading indicator
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(
                  c.gold.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _initStatus,
              style: TextStyle(
                color: c.muted.withValues(alpha: 0.4),
                fontSize: 11,
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
      isVoiceSearching: _isVoiceSearching,
      voiceSearchText: _voiceSearchAsrText,
      isLoadingEngine: _isLoadingEngine,
      onToggleRecord: _toggleRecord,
      onVoiceSearchToggle: _toggleVoiceSearch,
      onClearBuffer: () {
        _engine.resetBuffer();
        _audio.clearBuffer();
      },
    );
  }
}
