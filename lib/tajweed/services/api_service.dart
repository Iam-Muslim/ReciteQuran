import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import '../models/muaalem_result.dart';

class MuaalemApiService {
  // Configure your Modal API endpoint URL here
  // Option 1: Replace the URL below with your own Modal deployment URL
  // Option 2: Pass custom URL to constructor
  static const String _defaultBaseUrl =
      'https://iam-muslim--quran-muaalem-api-muaalemapi-serve.modal.run';

  final Dio _dio;
  CancelToken? _cancelToken;

  MuaalemApiService({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? _defaultBaseUrl,

          connectTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
          sendTimeout: const Duration(minutes: 2),
        ),
      );

  /// Analyzes the recorded verse audio against the reference text.
  ///
  /// The audio is uploaded as multipart/form-data. To guarantee absolutely zero UI
  /// lagging, the JSON deserialization and model mapping of the heavy response is
  /// offloaded entirely to a background Isolate.
  Future<MuaalemResponse> analyzeByVerse({
    required File audioFile,
    required int sura,
    required int aya,
    String rewaya = 'hafs',
    int maddMonfaselLen = 2,
    int maddMottaselLen = 4,
    int maddMottaselWaqf = 4,
    int maddAaredLen = 2,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    _cancelToken = CancelToken();
    FormData formData = FormData.fromMap({
      'sura': sura.toString(),
      'aya': aya.toString(),
      'rewaya': rewaya,
      'madd_monfasel_len': maddMonfaselLen.toString(),
      'madd_mottasel_len': maddMottaselLen.toString(),
      'madd_mottasel_waqf': maddMottaselWaqf.toString(),
      'madd_aared_len': maddAaredLen.toString(),
      'audio': await MultipartFile.fromFile(
        audioFile.path,
        filename: 'recitation.wav',
        contentType: MediaType('audio', 'wav'),
      ),
    });

    try {
      final response = await _dio.post(
        '/api/analyze-by-verse',
        data: formData,
        cancelToken: _cancelToken,
        options: Options(
          headers: {'Accept': 'application/json'},
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 120),
          validateStatus: (status) =>
              status != null &&
              status < 500, // Do not throw on 400 to parse the JSON detail
        ),
        onSendProgress: (int sent, int total) {
          if (onSendProgress != null) {
            onSendProgress(sent, total);
          }
        },
      );

      final String rawData = response.data.toString();

      if (response.statusCode != 200) {
        try {
          final errorData = jsonDecode(rawData);
          if (errorData is Map && errorData['detail'] != null) {
            throw APIError(detail: errorData['detail'].toString());
          }
        } catch (_) {}
        throw APIError(
          detail: 'Server returned ${response.statusCode}: $rawData',
        );
      }

      final Map<String, dynamic> jsonMap = jsonDecode(rawData);
      debugPrint("🔍 [DEBUG] RAW API JSON RESPONSE: $rawData");
      return MuaalemResponse.fromJson(jsonMap);
    } on DioException catch (e) {
      throw APIError(detail: 'Network error: ${e.message}');
    }
  }

  void cancelRequests() {
    _cancelToken?.cancel('Cancelled due to app backgrounding');
    _cancelToken = null;
  }

  /// Health check to see if the server is awake (cold starts can take 30-90s).
  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          return data['status'] == 'healthy';
        } else if (data is String) {
          return jsonDecode(data)['status'] == 'healthy';
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
