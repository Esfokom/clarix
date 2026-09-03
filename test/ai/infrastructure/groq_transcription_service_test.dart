import 'dart:io';

import 'package:clarix/src/features/ai/infrastructure/groq_transcription_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'submits recorded audio to Groq Whisper Turbo and returns its text',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'clarix-voice-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final File audio = File(
        '${directory.path}${Platform.pathSeparator}voice.m4a',
      );
      await audio.writeAsBytes(<int>[0, 1, 2, 3]);
      RequestOptions? request;
      final GroqTranscriptionService service = GroqTranscriptionService(
        apiKey: 'groq-test-key',
        dio: _dioResponding((RequestOptions captured) {
          request = captured;
          return <String, Object?>{'text': 'How many days are in a week?'};
        }),
      );

      final String transcript = await service.transcribe(audio.path);

      expect(transcript, 'How many days are in a week?');
      final RequestOptions capturedRequest = request!;
      expect(
        capturedRequest.uri,
        Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
      );
      expect(capturedRequest.headers['authorization'], 'Bearer groq-test-key');
      final FormData multipart = capturedRequest.data! as FormData;
      expect(
        Map<String, String>.fromEntries(multipart.fields),
        <String, String>{
          'model': 'whisper-large-v3-turbo',
          'temperature': '0',
          'response_format': 'verbose_json',
          'timestamp_granularities[]': 'segment',
        },
      );
      expect(multipart.files.single.key, 'file');
    },
  );

  test('reports an actionable error when Groq rejects the recording', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'clarix-voice-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File audio = File(
      '${directory.path}${Platform.pathSeparator}voice.m4a',
    );
    await audio.writeAsBytes(<int>[0]);
    final GroqTranscriptionService service = GroqTranscriptionService(
      apiKey: 'groq-test-key',
      dio: _dioFailing('Invalid audio'),
    );

    expect(
      () => service.transcribe(audio.path),
      throwsA(
        isA<GroqTranscriptionException>().having(
          (GroqTranscriptionException error) => error.message,
          'message',
          'Invalid audio',
        ),
      ),
    );
  });

  test(
    'rejects a Groq result whose segments report no detected speech',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'clarix-voice-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final File audio = File(
        '${directory.path}${Platform.pathSeparator}voice.m4a',
      );
      await audio.writeAsBytes(<int>[0]);
      final GroqTranscriptionService service = GroqTranscriptionService(
        apiKey: 'groq-test-key',
        dio: _dioResponding(
          (_) => <String, Object?>{
            'text': 'An unrelated transcription',
            'segments': <Map<String, Object>>[
              <String, Object>{'no_speech_prob': 0.94},
            ],
          },
        ),
      );

      expect(
        () => service.transcribe(audio.path),
        throwsA(isA<GroqNoSpeechDetectedException>()),
      );
    },
  );
}

Dio _dioResponding(Map<String, Object?> Function(RequestOptions) response) {
  final Dio dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: response(options),
          ),
        );
      },
    ),
  );
  return dio;
}

Dio _dioFailing(String message) {
  final Dio dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<Object?>(
              requestOptions: options,
              statusCode: 400,
              data: <String, Object?>{
                'error': <String, String>{'message': message},
              },
            ),
          ),
        );
      },
    ),
  );
  return dio;
}
