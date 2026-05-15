import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'local_model_path.dart';

const String _defaultModelPath = 'assets/models/gemma-4-E2B-it.litertlm';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.autoLoadModel = true,
    this.modelPath = _defaultModelPath,
  });

  final bool autoLoadModel;
  final String modelPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clarix Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B7CFA)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B7CFA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: ChatHomePage(autoLoadModel: autoLoadModel, modelPath: modelPath),
    );
  }
}

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({
    super.key,
    required this.autoLoadModel,
    required this.modelPath,
  });

  final bool autoLoadModel;
  final String modelPath;

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];

  InferenceModel? _model;
  InferenceChat? _chat;

  bool _loadingModel = false;
  bool _sendingMessage = false;
  String _status = 'Model not loaded yet.';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoadModel) {
      unawaited(_loadModel());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    unawaited(_chat?.close());
    unawaited(_model?.close());
    super.dispose();
  }

  Future<void> _loadModel() async {
    if (_loadingModel) {
      return;
    }

    if (kIsWeb) {
      setState(() {
        _status = 'Local file loading is not supported on web.';
        _error =
            'This screen expects a file path and uses `fromFile`, which is not available on web.';
      });
      return;
    }

    setState(() {
      _loadingModel = true;
      _error = null;
      _status = 'Preparing local model...';
    });

    try {
      final modelPath = resolveLocalModelPath(widget.modelPath);

      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
      ).fromFile(modelPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        enableSpeculativeDecoding: true,
      );

      final chat = await model.createChat(
        systemInstruction:
            'You are a helpful, concise assistant. Respond naturally and keep answers short unless the user asks for details.',
      );

      if (!mounted) {
        await chat.close();
        await model.close();
        return;
      }

      setState(() {
        _model = model;
        _chat = chat;
        _status = 'Model ready • speculative decoding enabled';
        _error = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
        _status = 'Failed to load the model.';
        _chat = null;
        _model = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingModel = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty || _chat == null || _sendingMessage) {
      return;
    }

    _textController.clear();

    final assistantMessage = _ChatMessage(isUser: false, text: '');

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: prompt));
      _messages.add(assistantMessage);
      _sendingMessage = true;
      _error = null;
      _status = 'Generating response...';
    });

    _scrollToBottom();

    try {
      await _chat!.addQueryChunk(Message.text(text: prompt, isUser: true));

      await for (final response in _chat!.generateChatResponseAsync()) {
        if (!mounted) {
          return;
        }

        if (response is TextResponse) {
          setState(() {
            assistantMessage.text += response.token;
          });
          _scrollToBottom();
        }
      }

      if (mounted) {
        setState(() {
          _status = 'Model ready • speculative decoding enabled';
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        assistantMessage.text = 'Sorry, I could not generate a reply.\n\n$e';
        _error = e.toString();
        _status = 'Generation failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sendingMessage = false;
        });
      }
      _scrollToBottom();
    }
  }

  Future<void> _stopGeneration() async {
    if (_chat == null) {
      return;
    }

    await _chat!.stopGeneration();

    if (!mounted) {
      return;
    }

    setState(() {
      _sendingMessage = false;
      _status = 'Generation stopped.';
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canSend = _chat != null && !_sendingMessage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clarix Chat'),
        actions: [
          IconButton(
            tooltip: 'Reload model',
            onPressed: _loadingModel ? null : _loadModel,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Stop generation',
            onPressed: _sendingMessage ? _stopGeneration : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _loadingModel
                                ? Icons.hourglass_top
                                : Icons.smart_toy_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _status,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Model file: ${widget.modelPath}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Loaded from disk with `fromFile(...)` and Gemma 4 speculative decoding enabled.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _loadingModel ? null : _loadModel,
                            icon: _loadingModel
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded),
                            label: Text(
                              _chat == null ? 'Load model' : 'Reload model',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _messages.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      _messages.clear();
                                      _status = _chat == null
                                          ? 'Model not loaded yet.'
                                          : 'Conversation cleared.';
                                      _error = null;
                                    });
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Clear chat'),
                          ),
                          if (!_loadingModel && _chat != null)
                            Chip(
                              label: const Text('Speculative decoding on'),
                              avatar: Icon(
                                Icons.auto_awesome,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _chat == null
                              ? 'Load the model to start chatting.'
                              : 'Send a message below and the model will reply here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return _MessageBubble(message: message);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: canSend,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: _chat == null
                            ? 'Load the model first'
                            : 'Ask anything about your local Gemma model...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: canSend ? _sendMessage : null,
                    child: _sendingMessage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.isUser;

    final backgroundColor = isUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final textColor = isUser
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                message.text.isEmpty && !isUser ? '…' : message.text,
                style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  _ChatMessage({required this.isUser, required this.text});

  final bool isUser;
  String text;
}
