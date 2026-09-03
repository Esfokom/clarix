import 'dart:io';

import 'package:dio/dio.dart';

class GroqTranscriptionException implements Exception {
  const GroqTranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GroqNoSpeechDetectedException extends GroqTranscriptionException {
  const GroqNoSpeechDetectedException()
    : super(
        'No speech was detected. Check the selected microphone and try again.',
      );
}

class GroqTranscriptionService {
  factory GroqTranscriptionService({required String apiKey, Dio? dio}) =>
      GroqTranscriptionService._(apiKey, dio ?? Dio());

  GroqTranscriptionService._(this._apiKey, this._dio);

  static const String apiKey = String.fromEnvironment('GROQ_API_KEY');

  final String _apiKey;
  final Dio _dio;

  Future<String> transcribe(String audioPath) async {
    if (_apiKey.trim().isEmpty) {
      throw const GroqTranscriptionException(
        'Voice input is unavailable. Start Clarix with GROQ_API_KEY.',
      );
    }

    try {
      final Response<Map<String, dynamic>> response = await _dio.post(
        'https://api.groq.com/openai/v1/audio/transcriptions',
        data: FormData.fromMap(<String, Object>{
          'file': await MultipartFile.fromFile(audioPath),
          'model': 'whisper-large-v3-turbo',
          'temperature': '0',
          'response_format': 'verbose_json',
          'timestamp_granularities[]': 'segment',
        }),
        options: Options(
          headers: <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
          },
          responseType: ResponseType.json,
        ),
      );
      final String? text = response.data?['text'] as String?;
      if (_containsOnlyNoSpeechSegments(response.data?['segments'])) {
        throw const GroqNoSpeechDetectedException();
      }
      if (text == null) {
        throw const GroqTranscriptionException(
          'Groq returned a transcription without text.',
        );
      }
      return text.trim();
    } on GroqTranscriptionException {
      rethrow;
    } on DioException catch (error) {
      final Object? errorData = error.response?.data;
      final String? message = errorData is Map
          ? (errorData['error'] is Map
                ? (errorData['error'] as Map)['message'] as String?
                : errorData['message'] as String?)
          : null;
      throw GroqTranscriptionException(
        message ?? 'Could not transcribe the recording. Please try again.',
      );
    }
  }

  bool _containsOnlyNoSpeechSegments(Object? value) {
    if (value is! List || value.isEmpty) return false;
    final List<double> probabilities = value
        .whereType<Map>()
        .map((Map segment) => (segment['no_speech_prob'] as num?)?.toDouble())
        .whereType<double>()
        .toList(growable: false);
    return probabilities.isNotEmpty &&
        probabilities.length == value.length &&
        probabilities.every((double probability) => probability >= 0.7);
  }
}
