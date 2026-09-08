import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clarix_logger.dart';
import '../domain/ai_feature_state.dart';
import '../domain/ai_models.dart';
import '../domain/ai_provider.dart';
import '../domain/conversation.dart';
import '../infrastructure/native_conversation_migrator.dart';
import 'ai_document_context.dart';
import 'ai_providers.dart';
import '../../pdf_editor/application/markdown_pdf_compiler.dart';
import '../../workspace/application/workspace_providers.dart';

/// Owns persisted AI preferences and the active document conversation.
///
/// Workspace supplies a document context at the call boundary; this controller
/// never reads workspace state or constructs editor sessions.
class AiNotifier extends AsyncNotifier<AiFeatureState> {
  @override
  Future<AiFeatureState> build() async {
    final preferences = ref.read(aiPreferencesStoreProvider);
    final profiles = ref.read(providerProfileStoreProvider);
    final saved = await preferences.readState();
    final available = await profiles.readProfiles();
    final defaultId = await profiles.readDefaultProfileId();
    final selected =
        _profileById(available, defaultId) ??
        (available.isEmpty ? null : available.first);
    final ready =
        selected != null &&
        (await profiles.readApiKey(selected.id))?.isNotEmpty == true;
    return AiFeatureState(
      chat: saved.copyWith(
        chatBusy: false,
        selectedProviderId: selected?.id,
        clearSelectedProviderId: selected == null,
        providerReady: ready,
        statusMessage: ready
            ? '${selected.label} is ready.'
            : 'Add a provider to start a remote AI chat.',
      ),
      providerProfiles: available,
    );
  }

  Future<void> loadLatestConversation(String documentId) async {
    final store = await ref.read(conversationStoreProvider.future);
    final threads = await store.listThreads(documentId);
    if (threads.isEmpty) {
      await _commit(
        _current.copyWith(
          chat: _current.chat.copyWith(
            messages: const <ComposerMessage>[],
            lastRetrievalSnippets: const <CitationSnippet>[],
          ),
        ),
      );
      return;
    }
    await selectConversation(threads.first.id);
  }

  Future<void> selectConversation(String threadId) async {
    final store = await ref.read(conversationStoreProvider.future);
    final messages = await store.readMessages(threadId);
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          messages: messages
              .map(
                (message) => ComposerMessage(
                  id: message.id,
                  role: message.role,
                  text: message.content,
                  createdAt: message.createdAt,
                  citations: message.citations,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  Future<void> deleteConversation(String threadId, String documentId) async {
    await (await ref.read(
      conversationStoreProvider.future,
    )).deleteThread(threadId);
    await loadLatestConversation(documentId);
  }

  Future<void> startNewConversation() async {
    if (_current.chat.chatBusy) return;
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          messages: const <ComposerMessage>[],
          lastRetrievalSnippets: const <CitationSnippet>[],
          statusMessage: 'New conversation ready.',
        ),
      ),
    );
  }

  Future<void> clearAllConversations() async {
    await (await ref.read(conversationStoreProvider.future)).clearAll();
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          messages: const <ComposerMessage>[],
          lastRetrievalSnippets: const <CitationSnippet>[],
          statusMessage: 'All saved conversations were cleared.',
        ),
      ),
    );
  }

  Future<void> toggleScopeMode() => _commit(
    _current.copyWith(
      chat: _current.chat.copyWith(
        useCurrentDocumentScope: !_current.chat.useCurrentDocumentScope,
      ),
    ),
  );

  Future<void> selectProvider(String? profileId) async {
    final profile = _profileById(_current.providerProfiles, profileId);
    final profiles = ref.read(providerProfileStoreProvider);
    final ready =
        profile != null &&
        (await profiles.readApiKey(profile.id))?.isNotEmpty == true;
    if (profile != null) await profiles.saveDefaultProfileId(profile.id);
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          selectedProviderId: profile?.id,
          clearSelectedProviderId: profile == null,
          providerReady: ready,
          statusMessage: ready
              ? '${profile.label} is ready.'
              : 'Add an API key to use this provider.',
        ),
      ),
    );
  }

  Future<void> saveProvider(AiProviderProfile profile, {String? apiKey}) async {
    final profiles = ref.read(providerProfileStoreProvider);
    await profiles.saveProfile(
      profile,
      apiKey: apiKey?.trim().isEmpty == true ? null : apiKey?.trim(),
    );
    await _commit(
      _current.copyWith(providerProfiles: await profiles.readProfiles()),
    );
    await selectProvider(profile.id);
  }

  Future<void> testProvider(
    AiProviderProfile profile, {
    required String apiKey,
  }) => ref.read(aiRuntimeServiceProvider).testProvider(profile, apiKey);

  Future<void> deleteProvider(String profileId) async {
    final profiles = ref.read(providerProfileStoreProvider);
    await profiles.deleteProfile(profileId);
    final wasSelected = _current.chat.selectedProviderId == profileId;
    await _commit(
      _current.copyWith(providerProfiles: await profiles.readProfiles()),
    );
    if (wasSelected) {
      await selectProvider(null);
    }
  }

  Future<void> sendPrompt(String prompt, AiDocumentContext context) async {
    final current = _current;
    if (prompt.trim().isEmpty ||
        current.chat.chatBusy ||
        !current.chat.providerReady ||
        current.chat.selectedProviderId == null) {
      clarixLog.w(
        'AI prompt rejected: empty=${prompt.trim().isEmpty}, '
        'busy=${current.chat.chatBusy}, '
        'providerReady=${current.chat.providerReady}, '
        'providerSelected=${current.chat.selectedProviderId != null}.',
      );
      return;
    }
    clarixLog.i(
      'AI prompt accepted for document ${context.documentId} '
      'using provider ${current.chat.selectedProviderId}.',
    );
    final user = ComposerMessage(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      text: prompt.trim(),
      createdAt: DateTime.now().toUtc(),
      citations: const [],
    );
    final assistant = ComposerMessage(
      id: 'assistant_${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      text: '',
      createdAt: DateTime.now().toUtc(),
      citations: const [],
    );
    await _commit(
      current.copyWith(
        chat: current.chat.copyWith(
          chatBusy: true,
          activityPhase: AiRuntimePhase.loadingInference,
          statusMessage:
              'Loading inference model. First response can take a minute.',
          messages: [...current.chat.messages, user, assistant],
          lastRetrievalSnippets: const [],
        ),
      ),
    );
    final buffer = StringBuffer();
    try {
      clarixLog.i('AI conversation migration started.');
      final store = await ref.read(conversationStoreProvider.future);
      if (context.agentController != null) {
        await NativeConversationMigrator(
          legacy: store,
          importConversation: context.agentController!.importConversation,
          documentId: context.documentId,
        ).run();
      }
      final threads = await store.listThreads(context.documentId);
      clarixLog.i(
        'AI provider run starting with ${threads.length} persisted thread(s).',
      );
      final chatHistory = current.chat.messages
          .where((m) => m.text.trim().isNotEmpty)
          .map((m) => <String, String>{
                'role': m.role == 'assistant' ? 'assistant' : 'user',
                'content': m.text.trim(),
              })
          .toList();

      String finalPrompt = prompt.trim();
      try {
        final chunkStore = ref.read(chunkStoreProvider);
        final workspaceState = ref.read(workspaceNotifierProvider).value;
        final StringBuffer contextBuffer = StringBuffer();

        if (workspaceState != null && workspaceState.session.tabs.isNotEmpty) {
          contextBuffer.writeln('[ACTIVE WORKSPACE DOCUMENT SOURCE TEXT]');
          for (final tab in workspaceState.session.tabs) {
            final chunks = await chunkStore.readChunks(tab.documentId);
            if (chunks.isNotEmpty) {
              contextBuffer.writeln('\n--- DOCUMENT SOURCE: "${tab.title}" ---');
              for (final c in chunks.take(5)) {
                final snippet = c.text.length > 300 ? '${c.text.substring(0, 300)}...' : c.text;
                contextBuffer.writeln('[Page ${c.pageNumber}]: $snippet');
              }
            }
          }
        } else if (context.documentId.isNotEmpty && context.documentId != 'study_mode_home') {
          final chunks = await chunkStore.readChunks(context.documentId);
          if (chunks.isNotEmpty) {
            contextBuffer.writeln('[DOCUMENT SOURCE TEXT: "${context.title}"]');
            for (final c in chunks.take(10)) {
              final snippet = c.text.length > 300 ? '${c.text.substring(0, 300)}...' : c.text;
              contextBuffer.writeln('[Page ${c.pageNumber}]: $snippet');
            }
          }
        }

        if (contextBuffer.isNotEmpty) {
          finalPrompt = '${contextBuffer.toString()}\n\n[USER REQUEST]:\n$finalPrompt';
        }
      } catch (e) {
        clarixLog.w('Failed to extract document chunks for AI prompt: $e');
      }

      final activeThreadId = threads.isEmpty ? (await store.createThread(documentId: context.documentId, title: 'Chat')).id : threads.first.id;

      final reply = await ref
          .read(aiRuntimeServiceProvider)
          .sendPrompt(
            prompt: finalPrompt,
            profileId: current.chat.selectedProviderId!,
            conversationId: activeThreadId,
            controller: context.agentController,
            history: chatHistory,
            onStatus: _setActivity,
            onToken: (token) {
              buffer.write(token);
              final raw = buffer.toString();

              String displayText = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
              if (displayText.contains('<think>')) {
                final thinkIdx = displayText.indexOf('<think>');
                displayText = displayText.substring(0, thinkIdx);
              }
              displayText = displayText.trimLeft();

              if (raw.contains('<think>')) {
                final thinkMatch = RegExp(r'<think>([\s\S]*?)(?:</think>|$)').firstMatch(raw);
                if (thinkMatch != null) {
                  final thinkContent = thinkMatch.group(1)?.trim() ?? '';
                  if (thinkContent.isNotEmpty) {
                    final lastLine = thinkContent.split('\n').where((l) => l.trim().isNotEmpty).lastOrNull ?? thinkContent;
                    final statusSnippet = lastLine.length > 40 ? '${lastLine.substring(0, 40)}...' : lastLine;
                    _setActivity(AiRuntimePhase.generating, statusSnippet);
                  }
                }
              }

              _replaceLastAssistant(
                displayText.isEmpty ? '...' : displayText,
                assistantId: assistant.id,
                busy: true,
              );

              if (raw.contains('[[SCROLL_TO_PAGE:')) {
                final match = RegExp(r'\[\[SCROLL_TO_PAGE:\s*\{"page":\s*(\d+)\}\]\]').firstMatch(raw);
                if (match != null) {
                  final pageNum = int.tryParse(match.group(1) ?? '');
                  if (pageNum != null) {
                    ref.read(workspaceNotifierProvider.notifier).updateViewerState(
                          tabId: context.tabId,
                          currentPage: pageNum,
                        );
                  }
                }
              }

              if (raw.contains('[[EDIT_TEXT:')) {
                final match = RegExp(r'\[\[EDIT_TEXT:\s*(\{.*?\})\]\]').firstMatch(raw);
                if (match != null) {
                  try {
                    final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
                    final int page = jsonMap['page'] as int? ?? 1;
                    final String oldText = jsonMap['oldText'] as String? ?? '';
                    final String newText = jsonMap['newText'] as String? ?? '';
                    if (newText.isNotEmpty || oldText.isNotEmpty) {
                      ref.read(workspaceNotifierProvider.notifier).updateViewerState(
                        tabId: context.tabId,
                        currentPage: page,
                      );
                      clarixLog.i('AI EDIT_TEXT targeted to Markdown Document Editor: page=$page, old="$oldText", new="$newText"');
                    }
                  } catch (e) {
                    clarixLog.w('AI edit text parsing failed: $e');
                  }
                }
              }

              if (raw.contains('[[ADD_CONTENT:')) {
                final match = RegExp(r'\[\[ADD_CONTENT:\s*(\{.*?\})\]\]').firstMatch(raw);
                if (match != null) {
                  try {
                    final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
                    final int page = jsonMap['page'] as int? ?? 1;
                    final String content = jsonMap['content'] as String? ?? '';
                    if (content.isNotEmpty) {
                      ref.read(workspaceNotifierProvider.notifier).updateViewerState(
                        tabId: context.tabId,
                        currentPage: page,
                      );
                      clarixLog.i('AI ADD_CONTENT targeted to Markdown Document Editor: page=$page, content="$content"');
                    }
                  } catch (e) {
                    clarixLog.w('AI add content parsing failed: $e');
                  }
                }
              }
            },
          );

      final cleanFinalText = reply.text
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
          .replaceAll(RegExp(r'<think>[\s\S]*$'), '')
          .trim();

      _replaceLastAssistant(
        cleanFinalText.isEmpty ? 'Action complete.' : cleanFinalText,
        assistantId: assistant.id,
        citations: reply.citations,
        busy: false,
        phase: AiRuntimePhase.idle,
        status: 'Ready to chat with your remote provider.',
      );

      await store.appendExchange(
        threadId: activeThreadId,
        user: ConversationMessage(
          id: user.id,
          role: user.role,
          content: user.text,
          createdAt: user.createdAt,
          tokenEstimate: user.text.length ~/ 4,
          citations: user.citations,
        ),
        assistant: ConversationMessage(
          id: assistant.id,
          role: assistant.role,
          content: reply.text,
          createdAt: DateTime.now().toUtc(),
          tokenEstimate: reply.text.length ~/ 4,
          citations: reply.citations,
        ),
      );

      if (reply.text.contains('[[EDIT_TEXT:') ||
          reply.text.contains('[[ADD_CONTENT:') ||
          reply.text.contains('[[REPLACE_DOCUMENT:')) {
        try {
          String newMarkdown = '';
          final chunkStore = ref.read(chunkStoreProvider);
          final chunks = await chunkStore.readChunks(context.documentId);
          final originalText = chunks.map((c) => c.text).join('\n\n');

          if (reply.text.contains('[[EDIT_TEXT:')) {
            final match = RegExp(r'\[\[EDIT_TEXT:\s*(\{[\s\S]*?\})\]\]').firstMatch(reply.text);
            if (match != null) {
              final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
              final String oldText = jsonMap['oldText'] as String? ?? '';
              final String newText = jsonMap['newText'] as String? ?? '';
              if (oldText.isNotEmpty && originalText.contains(oldText)) {
                newMarkdown = originalText.replaceFirst(oldText, newText);
              } else if (newText.isNotEmpty) {
                newMarkdown = newText;
              }
            }
          }

          if (reply.text.contains('[[ADD_CONTENT:')) {
            final match = RegExp(r'\[\[ADD_CONTENT:\s*(\{[\s\S]*?\})\]\]').firstMatch(reply.text);
            if (match != null) {
              final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
              final String content = jsonMap['content'] as String? ?? '';
              if (content.isNotEmpty) {
                newMarkdown = '$originalText\n\n$content';
              }
            }
          }

          if (newMarkdown.trim().isEmpty) {
            // Fallback: extract clean response body without tags
            newMarkdown = reply.text
                .replaceAll(RegExp(r'\[\[[\s\S]*?\]\]'), '')
                .trim();
          }

          if (newMarkdown.trim().isNotEmpty && context.filePath.isNotEmpty) {
            final pdfBytes = await MarkdownPdfCompiler.compile(newMarkdown, title: context.title);
            final file = File(context.filePath);
            if (file.existsSync()) {
              await file.delete();
            }
            await file.writeAsBytes(pdfBytes, flush: true);
            clarixLog.i('Successfully performed in-place agentic PDF replacement at ${context.filePath}');

            await ref.read(workspaceNotifierProvider.notifier).reloadActivePdf();
          }
        } catch (e, st) {
          clarixLog.e('Failed to execute agentic edit in-place: $e', error: e, stackTrace: st);
        }
      }

      if (reply.text.contains('[[CREATE_SOLUTION_PDF:')) {
        final match = RegExp(r'\[\[CREATE_SOLUTION_PDF:\s*(\{[\s\S]*?\})\]\]').firstMatch(reply.text);
        String solutionName = 'solution.pdf';
        if (match != null) {
          try {
            final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
            solutionName = jsonMap['solutionName'] as String? ?? 'solution.pdf';
          } catch (e) {
            clarixLog.w('Failed to parse solutionName JSON: $e');
          }
        }
        solutionName = solutionName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        final cleanText = reply.text
            .replaceAll(RegExp(r'\[\[CREATE_SOLUTION_PDF:[\s\S]*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[SAVE_DOCUMENT:[\s\S]*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[SCROLL_TO_PAGE:[\s\S]*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[EDIT_TEXT:[\s\S]*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[ADD_CONTENT:[\s\S]*?\]\]'), '')
            .trim();

        try {
          final pdfBytes = await MarkdownPdfCompiler.compile(cleanText, title: solutionName);
          final saveDir = Directory.current.path;
          final solutionFile = File('$saveDir/$solutionName');
          await solutionFile.writeAsBytes(pdfBytes);
          clarixLog.i('Successfully created solution PDF at ${solutionFile.path}');

          await ref.read(workspaceNotifierProvider.notifier).openPdfFiles([solutionFile.path]);
        } catch (e, st) {
          clarixLog.e('Failed to compile solution PDF: $e', error: e, stackTrace: st);
        }
      }

      if (reply.text.contains('[[SAVE_DOCUMENT:')) {
        final match = RegExp(r'\[\[SAVE_DOCUMENT:\s*(\{[\s\S]*?\})\]\]').firstMatch(reply.text);
        String filename = 'edited_document.pdf';
        if (match != null) {
          try {
            final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
            filename = jsonMap['filename'] as String? ?? 'edited_document.pdf';
          } catch (e) {
            clarixLog.w('Failed to parse SAVE_DOCUMENT JSON: $e');
          }
        }
        filename = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        final cleanText = reply.text
            .replaceAll(RegExp(r'\[\[SAVE_DOCUMENT:.*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[CREATE_SOLUTION_PDF:.*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[SCROLL_TO_PAGE:.*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[EDIT_TEXT:.*?\]\]'), '')
            .replaceAll(RegExp(r'\[\[ADD_CONTENT:.*?\]\]'), '')
            .trim();

        try {
          final pdfBytes = await MarkdownPdfCompiler.compile(cleanText, title: filename);
          final saveDir = Directory.current.path;
          final targetFile = File('$saveDir/$filename');
          await targetFile.writeAsBytes(pdfBytes);
          clarixLog.i('Successfully saved document PDF at ${targetFile.path}');
        } catch (e, st) {
          clarixLog.e('Failed to save document PDF: $e', error: e, stackTrace: st);
        }
      }

      if (reply.text.contains('[[SAVE_PDF_EDITS]]')) {
        try {
          await ref.read(workspaceNotifierProvider.notifier).saveActivePdfEdits();
          clarixLog.i('Successfully executed SAVE_PDF_EDITS.');
        } catch (e, st) {
          clarixLog.e('Failed to execute SAVE_PDF_EDITS: $e', error: e, stackTrace: st);
        }
      }

      if (reply.text.contains('[[SAVE_AS_NEW_DOCUMENT:')) {
        final match = RegExp(r'\[\[SAVE_AS_NEW_DOCUMENT:\s*(\{[\s\S]*?\})\]\]').firstMatch(reply.text);
        String filename = 'edited_document.pdf';
        if (match != null) {
          try {
            final jsonMap = jsonDecode(match.group(1)!) as Map<String, dynamic>;
            filename = jsonMap['filename'] as String? ?? 'edited_document.pdf';
          } catch (e) {
            clarixLog.w('Failed to parse filename JSON: $e');
          }
        }
        filename = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        
        try {
          final saveDir = Directory.current.path;
          final targetPath = '$saveDir/$filename';
          await ref.read(workspaceNotifierProvider.notifier).saveAsNewDocument(
            tabId: context.tabId,
            targetPath: targetPath,
          );
          clarixLog.i('Successfully executed SAVE_AS_NEW_DOCUMENT to $targetPath');
        } catch (e, st) {
          clarixLog.e('Failed to execute SAVE_AS_NEW_DOCUMENT: $e', error: e, stackTrace: st);
        }
      }
    } catch (error, stackTrace) {
      clarixLog.w(
        'Prompt generation failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _replaceLastAssistant(
        'I could not generate a response.\n\n$error',
        assistantId: assistant.id,
        busy: false,
        phase: AiRuntimePhase.failed,
        status: 'Generation failed.',
      );
    }
  }

  Future<void> stopGeneration() async {
    await ref.read(aiRuntimeServiceProvider).stopGeneration();
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          chatBusy: false,
          activityPhase: AiRuntimePhase.idle,
          statusMessage: 'Generation stopped.',
        ),
      ),
    );
  }

  AiFeatureState get _current => state.value ?? AiFeatureState.initial();
  Future<void> _commit(AiFeatureState value) async {
    state = AsyncData(value);
    await ref.read(aiPreferencesStoreProvider).writeState(value.chat);
  }

  void _setActivity(AiRuntimePhase phase, String message) {
    final value = _current;
    state = AsyncData(
      value.copyWith(
        chat: value.chat.copyWith(activityPhase: phase, statusMessage: message),
      ),
    );
    clarixLog.i('AI activity: ${phase.name} - $message');
  }

  void _replaceLastAssistant(
    String text, {
    String? assistantId,
    List<CitationSnippet>? citations,
    bool? busy,
    AiRuntimePhase? phase,
    String? status,
  }) {
    final value = _current;
    if (value.chat.messages.isEmpty) return;
    final messages = List<ComposerMessage>.from(value.chat.messages);
    final targetIndex = assistantId != null
        ? messages.indexWhere((m) => m.id == assistantId)
        : -1;
    final idx = targetIndex != -1 ? targetIndex : messages.length - 1;
    messages[idx] = messages[idx].copyWith(
      text: text,
      citations: citations,
    );
    state = AsyncData(
      value.copyWith(
        chat: value.chat.copyWith(
          messages: messages,
          chatBusy: busy,
          activityPhase: phase,
          statusMessage: status,
          lastRetrievalSnippets: citations,
        ),
      ),
    );
  }

  AiProviderProfile? _profileById(
    List<AiProviderProfile> profiles,
    String? id,
  ) => id == null
      ? null
      : profiles.where((profile) => profile.id == id).firstOrNull;
}
