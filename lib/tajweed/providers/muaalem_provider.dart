import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/muaalem_result.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../../data/models/quran_repository.dart';

// --- Tajweed Settings ---

class TajweedSettings {
  final String rewaya;
  final int maddMonfaselLen;
  final int maddMottaselLen;
  final int maddMottaselWaqf;
  final int maddAaredLen;

  TajweedSettings({
    this.rewaya = 'hafs',
    this.maddMonfaselLen = 2,
    this.maddMottaselLen = 4,
    this.maddMottaselWaqf = 4,
    this.maddAaredLen = 2,
  });

  TajweedSettings copyWith({
    String? rewaya,
    int? maddMonfaselLen,
    int? maddMottaselLen,
    int? maddMottaselWaqf,
    int? maddAaredLen,
  }) {
    return TajweedSettings(
      rewaya: rewaya ?? this.rewaya,
      maddMonfaselLen: maddMonfaselLen ?? this.maddMonfaselLen,
      maddMottaselLen: maddMottaselLen ?? this.maddMottaselLen,
      maddMottaselWaqf: maddMottaselWaqf ?? this.maddMottaselWaqf,
      maddAaredLen: maddAaredLen ?? this.maddAaredLen,
    );
  }
}

class TajweedSettingsNotifier extends Notifier<TajweedSettings> {
  late SharedPreferences _prefs;

  @override
  TajweedSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return TajweedSettings(
      rewaya: _prefs.getString('rewaya') ?? 'hafs',
      maddMonfaselLen: _prefs.getInt('madd_monfasel_len') ?? 2,
      maddMottaselLen: _prefs.getInt('madd_mottasel_len') ?? 4,
      maddMottaselWaqf: _prefs.getInt('madd_mottasel_waqf') ?? 4,
      maddAaredLen: _prefs.getInt('madd_aared_len') ?? 2,
    );
  }

  void updateSettings(TajweedSettings settings) {
    state = settings;
    _prefs.setString('rewaya', settings.rewaya);
    _prefs.setInt('madd_monfasel_len', settings.maddMonfaselLen);
    _prefs.setInt('madd_mottasel_len', settings.maddMottaselLen);
    _prefs.setInt('madd_mottasel_waqf', settings.maddMottaselWaqf);
    _prefs.setInt('madd_aared_len', settings.maddAaredLen);
  }

  void resetToDefaults() {
    updateSettings(TajweedSettings());
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'Initialize provider with SharedPreferences.getInstance()',
  );
});

final tajweedSettingsProvider =
    NotifierProvider<TajweedSettingsNotifier, TajweedSettings>(() {
      return TajweedSettingsNotifier();
    });

// Service providers
final audioServiceProvider = Provider<AudioService>((ref) => AudioService());
final muaalemApiServiceProvider = Provider<MuaalemApiService>(
  (ref) => MuaalemApiService(),
);

final tajweedQuranRepoProvider = Provider<QuranRepository>((ref) {
  // We don't have load() in global QuranRepository, it's injected from main or handled elsewhere.
  // Actually, we can just throw UnimplementedError and override it in ProviderScope or use the global one.
  throw UnimplementedError(
    'Global QuranRepository should be passed or we just access it from app context',
  );
});

// State
sealed class MuaalemState {}

class MuaalemInitial extends MuaalemState {}

class MuaalemRecording extends MuaalemState {}

class MuaalemProcessing extends MuaalemState {
  final double progress;
  MuaalemProcessing({this.progress = 0.0});
}

class MuaalemSuccess extends MuaalemState {
  final MuaalemResponse result;
  MuaalemSuccess(this.result);
}

class MuaalemError extends MuaalemState {
  final String message;
  MuaalemError(this.message);
}

// Controller
final muaalemControllerProvider =
    NotifierProvider<MuaalemController, MuaalemState>(() {
      return MuaalemController();
    });

class MuaalemController extends Notifier<MuaalemState> {
  late final AudioService _audioService;
  late final MuaalemApiService _apiService;

  @override
  MuaalemState build() {
    _audioService = ref.read(audioServiceProvider);
    _apiService = ref.read(muaalemApiServiceProvider);
    return MuaalemInitial();
  }

  void reset() {
    state = MuaalemInitial();
  }

  Future<void> startRecording() async {
    debugPrint("🎤 [MuaalemController] Starting recording...");
    await _audioService.startRecording();
    state = MuaalemRecording();
  }

  Future<void> cancelAll() async {
    debugPrint("🛑 [MuaalemController] Cancelling all active processes...");
    await _audioService.stopRecording();
    _apiService.cancelRequests();
    reset();
  }

  Future<void> stopAndAnalyze({
    required int sura,
    required int aya,
    int maddMottaselLen = 4,
    int maddMottaselWaqf = 4,
    int maddAaredLen = 2,
  }) async {
    state = MuaalemProcessing(progress: 0.1);
    debugPrint("🔍 [MuaalemController] stopAndAnalyze() sura=$sura aya=$aya");

    try {
      final path = await ref.read(audioServiceProvider).stopRecording();
      if (path == null) throw Exception("Recording failed");
      debugPrint("🔍 [MuaalemController] Audio path: $path");

      final tajweedSettings = ref.read(tajweedSettingsProvider);
      debugPrint(
        "🔍 [MuaalemController] Settings: rewaya=${tajweedSettings.rewaya} monfasel=${tajweedSettings.maddMonfaselLen} mottasel=${tajweedSettings.maddMottaselLen}",
      );

      final result = await ref
          .read(muaalemApiServiceProvider)
          .analyzeByVerse(
            audioFile: File(path),
            sura: sura,
            aya: aya,
            rewaya: tajweedSettings.rewaya,
            maddMonfaselLen: tajweedSettings.maddMonfaselLen,
            maddMottaselLen: tajweedSettings.maddMottaselLen,
            maddMottaselWaqf: tajweedSettings.maddMottaselWaqf,
            maddAaredLen: tajweedSettings.maddAaredLen,
            onSendProgress: (sent, total) {
              if (total > 0) {
                state = MuaalemProcessing(progress: sent / total);
              }
            },
          );

      // ── Debug: Print full result structure like iOS does ──────────────
      debugPrint("✅ [MuaalemController] API success!");
      debugPrint("   phonemes_text: ${result.phonemesText}");
      debugPrint("   wav2vec2_text: ${result.wav2vec2Text}");
      debugPrint(
        "   sifat_errors count: ${result.sifatErrors?.length ?? 'null'}",
      );
      debugPrint(
        "   phonemes_by_word count: ${result.phonemesByWord?.length ?? 'null'}",
      );
      debugPrint(
        "   phoneme_diff count: ${result.phonemeDiff?.length ?? 'null'}",
      );

      if (result.sifatErrors != null) {
        for (final err in result.sifatErrors!) {
          debugPrint(
            "   🔴 sifatError index=${err.index} phoneme='${err.phoneme}' expectedPhoneme='${err.expectedPhoneme}' errors=${err.errors.length}",
          );
          for (final a in err.errors) {
            debugPrint(
              "      attr='${a.attribute}' ar='${a.attributeAr}' expected='${a.expected}' actual='${a.actual}' prob=${a.prob.toStringAsFixed(2)}",
            );
          }
        }
      }

      if (result.phonemesByWord != null) {
        for (final w in result.phonemesByWord!) {
          debugPrint(
            "   📝 word[${w.wordIndex}]='${w.word}' sifat=${w.sifatStart}-${w.sifatEnd}",
          );
        }
      }
      // ─────────────────────────────────────────────────────────────────

      state = MuaalemSuccess(result);
    } catch (e) {
      debugPrint("❌ [MuaalemController] API call failed: $e");
      state = MuaalemError(e.toString());
    }
  }
}
