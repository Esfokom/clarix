import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/clarix_logger.dart';
import '../domain/live_conversation.dart';

class GeminiLiveConfiguration {
  const GeminiLiveConfiguration({
    required this.apiKey,
    required this.documentTitle,
  });
  final String apiKey;
  final String documentTitle;
  Map<String, Object?> get setupPayload => <String, Object?>{
    'setup': <String, Object?>{
      'model': 'models/gemini-3.1-flash-live-preview',
      'generationConfig': <String, Object?>{
        'responseModalities': <String>['AUDIO'],
      },
      'inputAudioTranscription': <String, Object?>{},
      'outputAudioTranscription': <String, Object?>{},
      'realtimeInputConfig': <String, Object?>{
        'activityHandling': 'START_OF_ACTIVITY_INTERRUPTS',
        'automaticActivityDetection': <String, Object?>{'disabled': false},
      },
      'tools': <Object>[
        <String, Object?>{'googleSearch': <String, Object?>{}},
        <String, Object?>{
          'functionDeclarations': <Object>[
            <String, Object?>{
              'name': 'query_active_document',
              'description':
                  'Search relevant passages in the active PDF before making document-specific claims.',
              'parameters': <String, Object?>{
                'type': 'OBJECT',
                'properties': <String, Object?>{
                  'query': <String, Object?>{'type': 'STRING'},
                },
                'required': <String>['query'],
              },
            },
          ],
        },
      ],
      'systemInstruction': <String, Object?>{
        'parts': <Object>[
          <String, String>{
            'text':
                'You are discussing $documentTitle. Use query_active_document for questions about this document. Use Google Search for current external information.',
          },
        ],
      },
    },
  };
}

abstract interface class GeminiLiveSession {
  Stream<GeminiLiveEvent> get events;
  Future<void> sendAudio(Uint8List pcm16k);
  Future<void> sendToolResponse({
    required String id,
    required String name,
    required Map<String, Object?> response,
  });
  Future<void> close();
}

abstract interface class GeminiLiveGateway {
  Future<GeminiLiveSession> connect({
    required GeminiLiveConfiguration configuration,
  });
}

class WebSocketGeminiLiveGateway implements GeminiLiveGateway {
  @override
  Future<GeminiLiveSession> connect({
    required GeminiLiveConfiguration configuration,
  }) async {
    if (configuration.apiKey.trim().isEmpty) {
      clarixLog.w('Gemini Live connection rejected: GEMINI_API_KEY is empty.');
      throw StateError(
        'Voice conversation is unavailable. Start Clarix with GEMINI_API_KEY.',
      );
    }
    clarixLog.i(
      'Gemini Live opening WebSocket for model gemini-3.1-flash-live-preview.',
    );
    final socket = await WebSocket.connect(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${Uri.encodeQueryComponent(configuration.apiKey)}',
    );
    clarixLog.i('Gemini Live WebSocket opened; sending setup message.');
    final session = _WebSocketGeminiLiveSession(socket);
    socket.add(jsonEncode(configuration.setupPayload));
    return session;
  }
}

class _WebSocketGeminiLiveSession implements GeminiLiveSession {
  _WebSocketGeminiLiveSession(this._socket) {
    _socket.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) {
        clarixLog.w(
          'Gemini Live WebSocket failed.',
          error: error,
          stackTrace: stackTrace,
        );
        _events.add(
          const GeminiLiveErrorEvent('The Gemini Live connection failed.'),
        );
      },
      onDone: () {
        clarixLog.w(
          'Gemini Live WebSocket closed (code=${_socket.closeCode}, reason=${_socket.closeReason ?? 'none'}).',
        );
        _events.close();
      },
    );
  }
  final WebSocket _socket;
  final StreamController<GeminiLiveEvent> _events =
      StreamController<GeminiLiveEvent>.broadcast();
  @override
  Stream<GeminiLiveEvent> get events => _events.stream;
  @override
  Future<void> sendAudio(Uint8List bytes) async => _socket.add(
    jsonEncode(<String, Object?>{
      'realtimeInput': <String, Object?>{
        'mediaChunks': <Object>[
          <String, String>{
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Encode(bytes),
          },
        ],
      },
    }),
  );
  @override
  Future<void> sendToolResponse({
    required String id,
    required String name,
    required Map<String, Object?> response,
  }) async => _socket.add(
    jsonEncode(<String, Object?>{
      'toolResponse': <String, Object?>{
        'functionResponses': <Object>[
          <String, Object?>{'id': id, 'name': name, 'response': response},
        ],
      },
    }),
  );
  void _onMessage(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final error = map['error'] as Map?;
      if (error != null) {
        final message =
            error['message'] as String? ?? 'Gemini Live rejected the session.';
        clarixLog.w('Gemini Live server error: $message');
        _events.add(GeminiLiveErrorEvent(message));
        return;
      }
      if (map.containsKey('setupComplete')) {
        clarixLog.i('Gemini Live setup completed.');
        _events.add(const GeminiLiveReadyEvent());
        return;
      }
      final content = map['serverContent'] as Map?;
      if (content == null) return;
      if (content['interrupted'] == true) {
        _events.add(const GeminiLiveActivityStartEvent());
      }
      if (content['turnComplete'] == true) {
        _events.add(const GeminiLiveTurnCompleteEvent());
      }
      final input = content['inputTranscription'] as Map?;
      if (input?['text'] is String) {
        _events.add(GeminiLiveInputTranscriptEvent(input!['text'] as String));
      }
      final output = content['outputTranscription'] as Map?;
      if (output?['text'] is String) {
        _events.add(GeminiLiveOutputTranscriptEvent(output!['text'] as String));
      }
      final turn = content['modelTurn'] as Map?;
      for (final part
          in (turn?['parts'] as List? ?? const <Object>[]).whereType<Map>()) {
        final data = part['inlineData'] as Map?;
        if (data?['data'] is String) {
          _events.add(
            GeminiLiveAudioEvent(base64Decode(data!['data'] as String)),
          );
        }
      }
      final calls = map['toolCall'] as Map?;
      for (final call
          in (calls?['functionCalls'] as List? ?? const <Object>[])
              .whereType<Map>()) {
        _events.add(
          GeminiLiveFunctionCallEvent(
            id: call['id'] as String,
            name: call['name'] as String,
            arguments: Map<String, Object?>.from(
              call['args'] as Map? ?? const <String, Object?>{},
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      clarixLog.w(
        'Gemini Live event parsing failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _events.add(
        const GeminiLiveErrorEvent('Gemini Live sent an unreadable event.'),
      );
    }
  }

  @override
  Future<void> close() async {
    await _socket.close();
    await _events.close();
  }
}
