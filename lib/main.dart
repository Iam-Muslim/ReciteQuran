/// Application entry point.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/app_state.dart';
import 'engine/sherpa_engine.dart';
import 'recording/live_recitation_controller.dart';
import 'recording/audio_processor.dart';
import 'data/models/quran_repository.dart';
import 'data/quran_metadata_service.dart';
import 'screens/tracking_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (_, __) {
        final ThemeColors c = AppState.instance.colors;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: c.bg,
            colorScheme: ColorScheme.light(primary: c.gold, surface: c.surface),
            fontFamily: 'ScheherazadeNew-Bold',
          ),
          home: const _Orchestrator(),
        );
      },
    );
  }
}

class _Orchestrator extends StatefulWidget {
  const _Orchestrator();
  @override
  State<_Orchestrator> createState() => _OrchestratorState();
}

class _OrchestratorState extends State<_Orchestrator> {
  final SherpaEngine _engine = SherpaEngine();
  final AudioProcessor _audio = AudioProcessor();

  QuranRepository? _repo;
  LiveRecitationController? _ctrl;

  bool _isInit = true;
  bool _isRecording = false;
  String _initStatus = 'Starting…';
  bool _isToggling = false; // Hardware Lock Flag to prevent double tapping
  bool _isLoadingEngine = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      if (mounted) setState(() => _initStatus = 'Requesting permissions…');
      await Permission.microphone.request();

      if (mounted) setState(() => _initStatus = 'Preparing ASR engine…');
      await _engine.preExtractAssets();
      _engine.initialize(); // Fire and forget in the background

      if (mounted) setState(() => _initStatus = 'Loading Quran database…');
      final service = QuranMetadataService();
      _repo = QuranRepository(service);
      await _repo!.loadSurahAsync(1);

      _ctrl = LiveRecitationController(
        engine: _engine,
        repository: _repo!,
        // Flush old audio on ayah transitions to prevent cross-ayah
        // ghosting (old words matching new ayah's words).
        // Reference: server.py line 572-575 trims the audio window.
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

  Future<void> _toggleRecord() async {
    if (_isToggling) return; // Prevent double-tap hardware crashes
    _isToggling = true;

    try {
      if (_isRecording) {
        // 1. Get the final leftover audio (the tail)
        final tail = await _audio.stopAndGetAudio();
        if (tail.isNotEmpty) {
          _ctrl?.feed(tail, isFinal: true);
          // Give the background Isolate half a second to finish the math
          // before we shut down the tracking state.
          await Future.delayed(const Duration(milliseconds: 500));
        }

        _engine.resetBuffer();
        _ctrl?.finalize();
        await WakelockPlus.disable();
        if (mounted) setState(() => _isRecording = false);
      } else {
        if (!_engine.isInitialized) {
          if (mounted) setState(() => _isLoadingEngine = true);
          await _engine.initialize(); // Wait if background init is still running
          if (mounted) setState(() => _isLoadingEngine = false);
        }
        
        await WakelockPlus.enable();
        _engine.resetBuffer();

        // Instant UI feedback before hardware mic starts
        if (mounted) setState(() => _isRecording = true);

        if (_ctrl != null) {
          _ctrl!.resumeTracking(); 
          // Start audio stream without blocking the UI
          _audio.start(
            onChunk: (chunk, isFinal) => _ctrl?.feed(chunk, isFinal: isFinal),
          ).catchError((e) {
            debugPrint('❌ AUDIO ERROR: $e');
            if (mounted) setState(() => _isRecording = false);
          });
        }
      }
    } catch (e) {
      debugPrint('❌ RECORD ERROR: $e');
      if (mounted) setState(() => _isRecording = false);
    } finally {
      _isToggling = false; // Unlock hardware
    }
  }

  Widget _loadingScreen() {
    final ThemeColors c = AppState.instance.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(c.gold),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'القرآن العظيم',
              style: TextStyle(
                color: c.gold,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFamily: 'ScheherazadeNew-Bold',
              ),
            ),
            const SizedBox(height: 8),
            Text(_initStatus, style: TextStyle(color: c.muted, fontSize: 13)),
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
      isLoadingEngine: _isLoadingEngine,
      onToggleRecord: _toggleRecord,
      onClearBuffer: () {
        _engine.resetBuffer();
        _audio.clearBuffer();
      },
    );
  }
}
