import 'dart:async';

import '../../../../core/agent/agent_bridge.dart';
import '../../../../core/agent/agent_bridge_types.dart';

class AgentRunControllerState {
  const AgentRunControllerState({
    this.activeRunId,
    this.status,
    this.lastSequence = 0,
    this.pendingProposal,
    this.committedRevision,
    this.error,
  });

  final String? activeRunId;
  final AgentRunStatus? status;
  final int lastSequence;
  final AgentProposal? pendingProposal;
  final int? committedRevision;
  final Object? error;

  AgentRunControllerState copyWith({
    String? activeRunId,
    AgentRunStatus? status,
    int? lastSequence,
    AgentProposal? pendingProposal,
    bool clearProposal = false,
    int? committedRevision,
    Object? error,
  }) => AgentRunControllerState(
    activeRunId: activeRunId ?? this.activeRunId,
    status: status ?? this.status,
    lastSequence: lastSequence ?? this.lastSequence,
    pendingProposal: clearProposal
        ? null
        : pendingProposal ?? this.pendingProposal,
    committedRevision: committedRevision ?? this.committedRevision,
    error: error,
  );
}

class AgentRunController {
  AgentRunController({required AgentBridgeSession bridge}) : _bridge = bridge {
    _subscription = bridge.events.listen(
      _onEvent,
      onError: (Object error) {
        _emit(_state.copyWith(error: error));
      },
    );
  }

  final AgentBridgeSession _bridge;
  final StreamController<AgentRunControllerState> _changes =
      StreamController<AgentRunControllerState>.broadcast(sync: true);
  late final StreamSubscription<AgentRunEvent> _subscription;
  AgentRunControllerState _state = const AgentRunControllerState();
  Future<void> _operation = Future<void>.value();
  bool _disposed = false;

  AgentRunControllerState get state => _state;
  Stream<AgentRunControllerState> get changes => _changes.stream;

  Future<AgentRunView> start(AgentStartRequest request) async {
    _ensureActive();
    if (_state.activeRunId != null && !(_state.status?.isTerminal ?? true)) {
      throw StateError('one agent run is already active for this tab');
    }
    final run = await _bridge.start(request);
    _emit(AgentRunControllerState(activeRunId: run.runId, status: run.status));
    return run;
  }

  Future<void> approve(AgentProposal proposal) => _serialize(() async {
    _requireOwned(proposal);
    final run = await _bridge.approve(proposal);
    _emit(_state.copyWith(status: run.status, clearProposal: true));
  });

  Future<void> reject(AgentProposal proposal) => _serialize(() async {
    _requireOwned(proposal);
    final run = await _bridge.reject(proposal);
    _emit(_state.copyWith(status: run.status, clearProposal: true));
  });

  Future<void> rebase(AgentProposal proposal, int currentRevision) =>
      _serialize(() async {
        _requireOwned(proposal);
        final run = await _bridge.rebase(proposal, currentRevision);
        _emit(_state.copyWith(status: run.status, clearProposal: true));
      });

  Future<void> cancel() => _serialize(_bridge.cancel);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _bridge.close();
    await _changes.close();
  }

  void _onEvent(AgentRunEvent event) {
    if (event.runId != _state.activeRunId) {
      _emit(_state.copyWith(error: StateError('cross-run event')));
      return;
    }
    final status = _statusFromEvent(event) ?? _state.status;
    _emit(
      _state.copyWith(
        status: status,
        lastSequence: event.sequence,
        committedRevision: event.kind == 'commandCommitted'
            ? event.documentRevision
            : null,
      ),
    );
  }

  AgentRunStatus? _statusFromEvent(AgentRunEvent event) {
    if (event.kind != 'statusChanged') return null;
    final outer = event.payload['StatusChanged'];
    if (outer is! Map<String, dynamic>) return null;
    final raw = outer['status'];
    return AgentRunStatus.values
        .where((value) => value.name == raw)
        .firstOrNull;
  }

  Future<void> _serialize(Future<void> Function() action) {
    final completer = Completer<void>();
    _operation = _operation
        .then((_) => action())
        .then(
          (_) => completer.complete(),
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        );
    return completer.future;
  }

  void _requireOwned(AgentProposal proposal) {
    _ensureActive();
    if (proposal.runId != _state.activeRunId) {
      throw StateError('proposal does not belong to this tab run');
    }
  }

  void _emit(AgentRunControllerState state) {
    _state = state;
    if (!_changes.isClosed) _changes.add(state);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('agent run controller is disposed');
  }
}
