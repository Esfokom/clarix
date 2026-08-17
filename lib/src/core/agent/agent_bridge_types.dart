enum AgentRunStatus {
  queued,
  assemblingContext,
  callingProvider,
  executingTool,
  awaitingApproval,
  budgetPaused,
  completed,
  cancelled,
  failed;

  bool get isTerminal =>
      this == completed || this == cancelled || this == failed;
}

class AgentSelectionRange {
  const AgentSelectionRange({
    required this.objectId,
    required this.pageId,
    required this.pageNumber,
    required this.startUtf16,
    required this.endUtf16,
    required this.quotedText,
  });

  final String objectId;
  final String pageId;
  final int pageNumber;
  final int startUtf16;
  final int endUtf16;
  final String quotedText;
}

class AgentSelection {
  const AgentSelection({
    required this.revision,
    required this.ranges,
    required this.objectIds,
    this.primaryIndex,
  });

  final int revision;
  final List<AgentSelectionRange> ranges;
  final List<String> objectIds;
  final int? primaryIndex;
}

class AgentSelectionContext {
  const AgentSelectionContext({
    required this.documentId,
    required this.revision,
    required this.ranges,
    required this.pageNumbers,
    required this.nearbyTextBefore,
    required this.nearbyTextAfter,
    required this.disclosureSha256,
  });

  final String documentId;
  final int revision;
  final List<AgentSelectionRange> ranges;
  final List<int> pageNumbers;
  final String nearbyTextBefore;
  final String nearbyTextAfter;
  final String disclosureSha256;
}

class AgentStartRequest {
  const AgentStartRequest({
    required this.providerEndpoint,
    required this.modelId,
    required this.headers,
    required this.apiKey,
    required this.userPrompt,
    this.selection,
    this.disclosureSha256,
    this.conversationId,
    this.maxToolCalls = 12,
    this.maxProviderRounds = 6,
    this.maxElapsedMs = 120000,
    this.maxOutputTokens = 8192,
  });

  final String providerEndpoint;
  final String modelId;
  final Map<String, String> headers;
  final String apiKey;
  final String? conversationId;
  final String userPrompt;
  final AgentSelection? selection;
  final String? disclosureSha256;
  final int maxToolCalls;
  final int maxProviderRounds;
  final int maxElapsedMs;
  final int maxOutputTokens;
}

class AgentRunView {
  const AgentRunView({required this.runId, required this.status});

  final String runId;
  final AgentRunStatus status;
}

class AgentRunEvent {
  const AgentRunEvent({
    required this.sessionId,
    required this.runId,
    required this.sequence,
    required this.documentRevision,
    required this.kind,
    required this.payload,
  });

  final String sessionId;
  final String runId;
  final int sequence;
  final int documentRevision;
  final String kind;
  final Map<String, Object?> payload;

  bool get isTerminal => kind == 'finished';
}

class AgentProposal {
  const AgentProposal({
    required this.runId,
    required this.proposalId,
    required this.approvalId,
    required this.baseRevision,
    required this.digestSha256,
    this.toolName = '',
    this.targets = const <AgentProposalTarget>[],
    this.reasons = const <String>[],
  });

  final String runId;
  final String proposalId;
  final String approvalId;
  final int baseRevision;
  final String digestSha256;
  final String toolName;
  final List<AgentProposalTarget> targets;
  final List<String> reasons;
}

class AgentProposalTarget {
  const AgentProposalTarget({
    required this.objectId,
    required this.pageId,
    required this.pageNumber,
    required this.startUtf16,
    required this.endUtf16,
    required this.beforeText,
    required this.afterText,
  });

  final String objectId;
  final String pageId;
  final int pageNumber;
  final int startUtf16;
  final int endUtf16;
  final String beforeText;
  final String afterText;
}

class AgentDisclosure {
  const AgentDisclosure({
    required this.providerLabel,
    required this.selectedText,
    required this.nearbyTextBefore,
    required this.nearbyTextAfter,
    required this.pageNumbers,
    required this.sha256,
  });

  final String providerLabel;
  final String selectedText;
  final String nearbyTextBefore;
  final String nearbyTextAfter;
  final List<int> pageNumbers;
  final String sha256;
}

class AgentConversationMessage {
  const AgentConversationMessage({
    required this.id,
    required this.sequence,
    required this.role,
    required this.content,
    required this.citationsJson,
    required this.createdAt,
    required this.tokenEstimate,
    required this.isCompacted,
  });
  final String id;
  final int sequence;
  final String role;
  final String content;
  final String citationsJson;
  final String createdAt;
  final int tokenEstimate;
  final bool isCompacted;
}

class AgentConversationImport {
  const AgentConversationImport({
    required this.legacyId,
    required this.documentId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.summary,
    this.summaryThroughSequence,
  });
  final String legacyId;
  final String documentId;
  final String title;
  final String createdAt;
  final String updatedAt;
  final String? summary;
  final int? summaryThroughSequence;
  final List<AgentConversationMessage> messages;
}

class AgentConversationImportReceipt {
  const AgentConversationImportReceipt({
    required this.conversationId,
    required this.messageCount,
    required this.digestSha256,
    required this.alreadyPresent,
  });
  final String conversationId;
  final int messageCount;
  final String digestSha256;
  final bool alreadyPresent;
}

class AgentProtocolViolation implements Exception {
  const AgentProtocolViolation(this.message);

  final String message;

  @override
  String toString() => 'AgentProtocolViolation: $message';
}
