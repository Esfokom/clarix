import 'dart:async';
import 'dart:convert';

import '../ffi/agent_api.dart' as native_agent;
import '../ffi/editing_api.dart' as native_editor;
import 'agent_bridge_types.dart';

const int _agentSchemaVersion = 1;
final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

class NativeAgentRunWire {
  const NativeAgentRunWire({
    required this.schemaVersion,
    required this.runId,
    required this.status,
  });

  final int schemaVersion;
  final String runId;
  final String status;
}

class NativeAgentEventWire {
  const NativeAgentEventWire({
    required this.schemaVersion,
    required this.sessionId,
    required this.runId,
    required this.sequence,
    required this.documentRevision,
    required this.kind,
    required this.payloadJson,
  });

  final int schemaVersion;
  final String sessionId;
  final String runId;
  final int sequence;
  final int documentRevision;
  final String kind;
  final String payloadJson;

  NativeAgentEventWire copyWith({String? kind, String? payloadJson}) =>
      NativeAgentEventWire(
        schemaVersion: schemaVersion,
        sessionId: sessionId,
        runId: runId,
        sequence: sequence,
        documentRevision: documentRevision,
        kind: kind ?? this.kind,
        payloadJson: payloadJson ?? this.payloadJson,
      );
}

abstract interface class NativeAgentPort {
  Future<AgentSelectionContext> selectionContext(AgentSelection selection);
  Future<NativeAgentRunWire> start(AgentStartRequest request);
  Stream<NativeAgentEventWire> events(String runId);
  Future<NativeAgentRunWire> approve(String runId, String approvalId);
  Future<NativeAgentRunWire> reject(String runId, String approvalId);
  Future<NativeAgentRunWire> rebase(
    String runId,
    String approvalId,
    int currentRevision,
  );
  Future<void> cancel(String runId);
}

abstract interface class NativeAgentPortProvider {
  NativeAgentPort get agentPort;
}

class AgentBridgeSession {
  factory AgentBridgeSession.forTest(
    NativeAgentPort native, {
    required String sessionId,
  }) => AgentBridgeSession._(native, sessionId);

  AgentBridgeSession._(this._native, this._sessionId);

  factory AgentBridgeSession.fromNative(
    native_editor.NativeEditorSession session, {
    required String sessionId,
  }) => AgentBridgeSession.forTest(
    FrbNativeAgentPort(session),
    sessionId: sessionId,
  );

  final NativeAgentPort _native;
  final String _sessionId;
  final StreamController<AgentRunEvent> _events =
      StreamController<AgentRunEvent>.broadcast(sync: true);
  StreamSubscription<NativeAgentEventWire>? _subscription;
  String? _activeRunId;
  int _lastSequence = 0;
  bool _terminal = false;
  bool _closed = false;

  Stream<AgentRunEvent> get events => _events.stream;
  String? get activeRunId => _activeRunId;

  Future<AgentSelectionContext> selectionContext(
    AgentSelection selection,
  ) async {
    _ensureOpen();
    final context = await _native.selectionContext(selection);
    _canonical(context.documentId, 'documentId');
    if (context.revision < 0 || context.disclosureSha256.isEmpty) {
      throw const AgentProtocolViolation('invalid native selection context');
    }
    return context;
  }

  Future<AgentRunView> start(AgentStartRequest request) async {
    _ensureOpen();
    if (_activeRunId != null && !_terminal) {
      throw StateError('an agent run is already active for this session');
    }
    final wire = await _native.start(request);
    final run = _run(wire);
    _activeRunId = run.runId;
    _lastSequence = 0;
    _terminal = run.status.isTerminal;
    await _subscription?.cancel();
    _subscription = _native
        .events(run.runId)
        .listen(_accept, onError: _events.addError);
    return run;
  }

  Future<AgentRunView> approve(AgentProposal proposal) {
    _validateProposal(proposal);
    return _native.approve(proposal.runId, proposal.approvalId).then(_run);
  }

  Future<AgentRunView> reject(AgentProposal proposal) {
    _validateProposal(proposal);
    return _native.reject(proposal.runId, proposal.approvalId).then(_run);
  }

  Future<AgentRunView> rebase(AgentProposal proposal, int currentRevision) {
    _validateProposal(proposal);
    if (currentRevision < 0) {
      throw const AgentProtocolViolation('revision must be non-negative');
    }
    return _native
        .rebase(proposal.runId, proposal.approvalId, currentRevision)
        .then(_run);
  }

  Future<void> cancel() async {
    _ensureOpen();
    final runId = _activeRunId;
    if (runId != null && !_terminal) await _native.cancel(runId);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _events.close();
  }

  void _accept(NativeAgentEventWire wire) {
    try {
      _schema(wire.schemaVersion);
      _canonical(wire.sessionId, 'sessionId');
      _canonical(wire.runId, 'runId');
      if (wire.sessionId != _sessionId || wire.runId != _activeRunId) {
        throw const AgentProtocolViolation(
          'event does not belong to the active session and run',
        );
      }
      if (_terminal) {
        throw const AgentProtocolViolation(
          'event arrived after terminal state',
        );
      }
      if (wire.sequence <= _lastSequence) {
        throw AgentProtocolViolation(
          'event sequence ${wire.sequence} is not greater than $_lastSequence',
        );
      }
      if (wire.documentRevision < 0) {
        throw const AgentProtocolViolation('revision must be non-negative');
      }
      final decoded = jsonDecode(wire.payloadJson);
      if (decoded is! Map<String, dynamic>) {
        throw const AgentProtocolViolation('event payload must be an object');
      }
      final event = AgentRunEvent(
        sessionId: wire.sessionId,
        runId: wire.runId,
        sequence: wire.sequence,
        documentRevision: wire.documentRevision,
        kind: wire.kind,
        payload: decoded,
      );
      _lastSequence = wire.sequence;
      _terminal = event.isTerminal;
      _events.add(event);
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  AgentRunView _run(NativeAgentRunWire wire) {
    _schema(wire.schemaVersion);
    _canonical(wire.runId, 'runId');
    final status = AgentRunStatus.values
        .where((value) => value.name == wire.status)
        .firstOrNull;
    if (status == null) {
      throw AgentProtocolViolation('unknown agent status ${wire.status}');
    }
    return AgentRunView(runId: wire.runId, status: status);
  }

  void _validateProposal(AgentProposal proposal) {
    _ensureOpen();
    if (proposal.runId != _activeRunId) {
      throw StateError('proposal does not belong to the active run');
    }
    _canonical(proposal.proposalId, 'proposalId');
    _canonical(proposal.approvalId, 'approvalId');
    if (proposal.baseRevision < 0 || proposal.digestSha256.isEmpty) {
      throw const AgentProtocolViolation('proposal binding is incomplete');
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('agent bridge session is closed');
  }
}

class FrbNativeAgentPort implements NativeAgentPort {
  FrbNativeAgentPort(this._session);

  final native_editor.NativeEditorSession _session;

  @override
  Future<AgentSelectionContext> selectionContext(
    AgentSelection selection,
  ) async {
    final value = await _session.selectionContext(
      selection: _selection(selection),
      beforeUtf16: 512,
      afterUtf16: 512,
      maxRanges: 8,
    );
    return AgentSelectionContext(
      documentId: value.documentId,
      revision: _safeInt(value.revision, 'revision'),
      ranges: value.ranges
          .map(
            (range) => AgentSelectionRange(
              objectId: range.objectId,
              pageId: range.pageId,
              pageNumber: range.pageNumber,
              startUtf16: range.startUtf16,
              endUtf16: range.endUtf16,
              quotedText: range.quotedText,
            ),
          )
          .toList(growable: false),
      pageNumbers: value.pageNumbers.toList(growable: false),
      nearbyTextBefore: value.nearbyTextBefore,
      nearbyTextAfter: value.nearbyTextAfter,
      disclosureSha256: value.disclosureSha256,
    );
  }

  @override
  Future<NativeAgentRunWire> start(AgentStartRequest request) async => _wireRun(
    await _session.startAgentRun(
      request: native_agent.NativeStartAgentRunRequest(
        schemaVersion: _agentSchemaVersion,
        providerEndpoint: request.providerEndpoint,
        modelId: request.modelId,
        headers: request.headers,
        apiKey: request.apiKey,
        conversationId: request.conversationId,
        userPrompt: request.userPrompt,
        selection: _selection(request.selection),
        disclosureSha256: request.disclosureSha256,
        maxToolCalls: request.maxToolCalls,
        maxProviderRounds: request.maxProviderRounds,
        maxElapsedMs: BigInt.from(request.maxElapsedMs),
        maxOutputTokens: request.maxOutputTokens,
      ),
    ),
  );

  @override
  Stream<NativeAgentEventWire> events(String runId) => _session
      .agentEvents(runId: runId)
      .map(
        (value) => NativeAgentEventWire(
          schemaVersion: value.schemaVersion,
          sessionId: value.sessionId,
          runId: value.runId,
          sequence: _safeInt(value.sequence, 'sequence'),
          documentRevision: _safeInt(
            value.documentRevision,
            'documentRevision',
          ),
          kind: value.kind,
          payloadJson: value.payloadJson,
        ),
      );

  @override
  Future<NativeAgentRunWire> approve(String runId, String approvalId) async =>
      _wireRun(
        await _session.approveAgentProposal(
          runId: runId,
          approvalId: approvalId,
        ),
      );

  @override
  Future<NativeAgentRunWire> reject(String runId, String approvalId) async =>
      _wireRun(
        await _session.rejectAgentProposal(
          runId: runId,
          approvalId: approvalId,
        ),
      );

  @override
  Future<NativeAgentRunWire> rebase(
    String runId,
    String approvalId,
    int currentRevision,
  ) async => _wireRun(
    await _session.rebaseAgentProposal(
      runId: runId,
      approvalId: approvalId,
      currentRevision: BigInt.from(currentRevision),
    ),
  );

  @override
  Future<void> cancel(String runId) => _session.cancelAgentRun(runId: runId);

  static native_editor.NativeSelectionSet _selection(AgentSelection value) =>
      native_editor.NativeSelectionSet(
        expectedRevision: BigInt.from(value.revision),
        kind: native_editor.NativeSelectionKind.textRanges,
        ranges: value.ranges
            .map(
              (range) => native_editor.NativeSelectionRange(
                objectId: range.objectId,
                pageId: range.pageId,
                pageNumber: range.pageNumber,
                startUtf16: range.startUtf16,
                endUtf16: range.endUtf16,
                quotedText: range.quotedText,
              ),
            )
            .toList(growable: false),
        objectIds: value.objectIds,
        primaryIndex: value.primaryIndex,
      );

  static NativeAgentRunWire _wireRun(native_agent.NativeAgentRun value) =>
      NativeAgentRunWire(
        schemaVersion: value.schemaVersion,
        runId: value.runId,
        status: value.status,
      );
}

void _schema(int value) {
  if (value != _agentSchemaVersion) {
    throw AgentProtocolViolation(
      'expected schema $_agentSchemaVersion, received $value',
    );
  }
}

void _canonical(String value, String field) {
  if (!_uuid.hasMatch(value)) {
    throw AgentProtocolViolation('$field must be a canonical UUID');
  }
}

int _safeInt(BigInt value, String field) {
  if (value.isNegative || value > BigInt.from(0x1fffffffffffff)) {
    throw AgentProtocolViolation('$field is outside Dart integer range');
  }
  return value.toInt();
}
