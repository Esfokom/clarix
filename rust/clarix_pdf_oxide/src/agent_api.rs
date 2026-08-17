use std::collections::{BTreeMap, HashMap};
use std::fmt;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

use clarix_agent_core::{
    AgentProviderConfig, AgentRunEngine, AgentRunEventKind, AgentRunId, AgentRunRequest,
    AgentRunStatus, ApprovalId, ConversationId, RunBudgets, SecretString,
};
use clarix_editing_core::{
    ContextLimits, DocumentRevision, EditorSessionActor, ObjectId, PageId, SelectionContext,
    SelectionKind, SelectionSet, TextRangeRef,
};
use clarix_editing_store::SqliteAgentRunRepository;
use sha2::{Digest, Sha256};

use crate::agent_provider::OpenAiCompatibleRustProvider;
use crate::editing_api::{
    NativeEditorSession, NativeSelectionKind, NativeSelectionRange, NativeSelectionSet,
};
use crate::frb_generated::StreamSink;

const AGENT_SCHEMA_VERSION: u32 = 1;
type NativeEngine =
    AgentRunEngine<OpenAiCompatibleRustProvider, EditorSessionActor, SqliteAgentRunRepository>;

#[derive(Clone)]
pub struct NativeStartAgentRunRequest {
    pub schema_version: u32,
    pub provider_endpoint: String,
    pub model_id: String,
    pub headers: HashMap<String, String>,
    pub api_key: String,
    pub conversation_id: Option<String>,
    pub user_prompt: String,
    pub selection: NativeSelectionSet,
    pub disclosure_sha256: String,
    pub max_tool_calls: u32,
    pub max_provider_rounds: u32,
    pub max_elapsed_ms: u64,
    pub max_output_tokens: u32,
}

impl fmt::Debug for NativeStartAgentRunRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("NativeStartAgentRunRequest")
            .field("schema_version", &self.schema_version)
            .field("provider_endpoint", &self.provider_endpoint)
            .field("model_id", &self.model_id)
            .field("header_names", &self.headers.keys().collect::<Vec<_>>())
            .field("api_key", &"[REDACTED]")
            .field("conversation_id", &self.conversation_id)
            .field("user_prompt", &self.user_prompt)
            .field("selection", &self.selection)
            .field("disclosure_sha256", &self.disclosure_sha256)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone)]
pub struct NativeSelectionContext {
    pub schema_version: u32,
    pub document_id: String,
    pub revision: u64,
    pub kind: NativeSelectionKind,
    pub ranges: Vec<NativeSelectionRange>,
    pub page_numbers: Vec<u32>,
    pub nearby_text_before: String,
    pub nearby_text_after: String,
    pub disclosure_sha256: String,
}

#[derive(Debug, Clone)]
pub struct NativeAgentRun {
    pub schema_version: u32,
    pub run_id: String,
    pub status: String,
}

#[derive(Debug, Clone)]
pub struct NativeAgentEvent {
    pub schema_version: u32,
    pub session_id: String,
    pub run_id: String,
    pub sequence: u64,
    pub document_revision: u64,
    pub kind: String,
    pub payload_json: String,
}

#[derive(Debug, Clone)]
pub struct NativeAgentAudit {
    pub schema_version: u32,
    pub run_id: String,
    pub status: String,
    pub events: Vec<NativeAgentEvent>,
}

struct NativeRunHandle {
    engine: Arc<NativeEngine>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

pub(crate) struct NativeAgentRuntime {
    actor: EditorSessionActor,
    repository: Arc<SqliteAgentRunRepository>,
    runs: Mutex<HashMap<AgentRunId, Arc<NativeRunHandle>>>,
    closed: AtomicBool,
}

impl NativeAgentRuntime {
    pub(crate) fn new(
        actor: EditorSessionActor,
        repository: Arc<SqliteAgentRunRepository>,
    ) -> Self {
        Self {
            actor,
            repository,
            runs: Mutex::new(HashMap::new()),
            closed: AtomicBool::new(false),
        }
    }

    fn ensure_open(&self) -> Result<(), String> {
        if self.closed.load(Ordering::Acquire) {
            Err("session_closed: editor session is closed".into())
        } else {
            Ok(())
        }
    }

    fn handle(&self, run_id: AgentRunId) -> Result<Arc<NativeRunHandle>, String> {
        self.ensure_open()?;
        self.runs
            .lock()
            .map_err(|_| "agent_runtime_poisoned: run registry".to_owned())?
            .get(&run_id)
            .cloned()
            .ok_or_else(|| "agent_run_not_found: run is not active in this session".into())
    }

    pub(crate) fn close(&self) -> Result<(), String> {
        if self.closed.swap(true, Ordering::AcqRel) {
            return Ok(());
        }
        let handles = self
            .runs
            .lock()
            .map_err(|_| "agent_runtime_poisoned: run registry".to_owned())?
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for handle in &handles {
            let audit_runs = self
                .runs
                .lock()
                .map_err(|_| "agent_runtime_poisoned: run registry".to_owned())?;
            if let Some((run_id, _)) = audit_runs
                .iter()
                .find(|(_, candidate)| Arc::ptr_eq(candidate, handle))
            {
                handle.engine.cancel(*run_id);
            }
        }
        for handle in handles {
            join_worker(&handle)?;
        }
        Ok(())
    }
}

impl NativeEditorSession {
    pub fn selection_context(
        &self,
        selection: NativeSelectionSet,
        before_utf16: u32,
        after_utf16: u32,
        max_ranges: u32,
    ) -> Result<NativeSelectionContext, String> {
        self.agent_runtime.ensure_open()?;
        let context = self
            .actor
            .selection_context(
                core_selection(selection)?,
                ContextLimits {
                    before_utf16,
                    after_utf16,
                    max_ranges,
                },
            )
            .map_err(|error| format!("{}: {error}", error.code()))?;
        native_selection_context(context)
    }

    pub fn start_agent_run(
        &self,
        request: NativeStartAgentRunRequest,
    ) -> Result<NativeAgentRun, String> {
        self.agent_runtime.ensure_open()?;
        if request.schema_version != AGENT_SCHEMA_VERSION {
            return Err("agent_schema_mismatch: unsupported request schema".into());
        }
        let selection = core_selection(request.selection.clone())?;
        let context = self
            .actor
            .selection_context(selection, ContextLimits::default())
            .map_err(|error| format!("{}: {error}", error.code()))?;
        let disclosure = disclosure_digest(&context)?;
        if disclosure != request.disclosure_sha256 {
            return Err(
                "disclosure_mismatch: selection disclosure acknowledgement is stale".into(),
            );
        }
        let budgets = RunBudgets {
            max_tool_calls: request.max_tool_calls,
            max_provider_rounds: request.max_provider_rounds,
            max_elapsed_ms: request.max_elapsed_ms,
            max_output_tokens: request.max_output_tokens,
        }
        .validate()
        .map_err(|error| format!("{}: {error}", error.code()))?;
        let provider = Arc::new(
            OpenAiCompatibleRustProvider::new(
                &request.provider_endpoint,
                &request.model_id,
                request
                    .headers
                    .clone()
                    .into_iter()
                    .collect::<BTreeMap<_, _>>(),
                &request.api_key,
                Duration::from_millis(request.max_elapsed_ms.min(120_000)),
            )
            .map_err(|error| format!("{}: {error}", error.code()))?,
        );
        let run_id = AgentRunId::new();
        let conversation_id = request
            .conversation_id
            .as_deref()
            .map(ConversationId::from_str)
            .transpose()
            .map_err(|_| "invalid_conversation_id: expected a canonical UUID".to_owned())?
            .unwrap_or_default();
        let engine = Arc::new(AgentRunEngine::new(
            provider,
            Arc::new(self.agent_runtime.actor.clone()),
            self.agent_runtime.repository.clone(),
        ));
        let core_request = AgentRunRequest {
            run_id,
            conversation_id,
            document_id: context.document_id,
            starting_revision: context.document_revision,
            user_prompt: request.user_prompt,
            selection_context: Some(context),
            provider: AgentProviderConfig {
                provider_id: "openai-compatible".into(),
                endpoint: request.provider_endpoint,
                model_id: request.model_id,
                headers: request.headers.into_iter().collect(),
                api_key: SecretString::new(request.api_key),
            },
            budgets,
        };
        let worker_engine = engine.clone();
        let worker = std::thread::Builder::new()
            .name(format!("clarix-agent-{run_id}"))
            .spawn(move || {
                let _ = worker_engine.start(core_request);
            })
            .map_err(|error| format!("agent_worker_failed: {error}"))?;
        self.agent_runtime
            .runs
            .lock()
            .map_err(|_| "agent_runtime_poisoned: run registry".to_owned())?
            .insert(
                run_id,
                Arc::new(NativeRunHandle {
                    engine,
                    worker: Mutex::new(Some(worker)),
                }),
            );
        Ok(NativeAgentRun {
            schema_version: AGENT_SCHEMA_VERSION,
            run_id: run_id.to_string(),
            status: "queued".into(),
        })
    }

    pub fn agent_events(
        &self,
        run_id: String,
        sink: StreamSink<NativeAgentEvent>,
    ) -> Result<(), String> {
        self.agent_runtime.ensure_open()?;
        let run_id = parse_run_id(&run_id)?;
        self.agent_runtime.handle(run_id)?;
        let repository = self.agent_runtime.repository.clone();
        let session_id = self.actor.session_id().to_string();
        std::thread::Builder::new()
            .name(format!("clarix-agent-events-{run_id}"))
            .spawn(move || {
                let mut emitted = 0_usize;
                loop {
                    match repository.read_run_audit(run_id) {
                        Ok(audit) => {
                            for event in audit.events.iter().skip(emitted) {
                                if sink.add(native_event(&session_id, event)).is_err() {
                                    return;
                                }
                            }
                            emitted = audit.events.len();
                            if audit.header.status.is_terminal() {
                                return;
                            }
                        }
                        Err(_) if emitted == 0 => {}
                        Err(_) => return,
                    }
                    std::thread::sleep(Duration::from_millis(25));
                }
            })
            .map_err(|error| format!("agent_event_stream_failed: {error}"))?;
        Ok(())
    }

    pub fn approve_agent_proposal(
        &self,
        run_id: String,
        approval_id: String,
    ) -> Result<NativeAgentRun, String> {
        self.agent_runtime.ensure_open()?;
        let run_id = parse_run_id(&run_id)?;
        let approval_id = ApprovalId::from_str(&approval_id)
            .map_err(|_| "invalid_approval_id: expected a canonical UUID".to_owned())?;
        let handle = self.agent_runtime.handle(run_id)?;
        join_worker(&handle)?;
        let snapshot = handle
            .engine
            .approve(run_id, approval_id)
            .map_err(|error| format!("{}: {error}", error.code()))?;
        Ok(native_run(snapshot.run_id, snapshot.status))
    }

    pub fn reject_agent_proposal(
        &self,
        run_id: String,
        approval_id: String,
    ) -> Result<NativeAgentRun, String> {
        self.agent_runtime.ensure_open()?;
        let run_id = parse_run_id(&run_id)?;
        let approval_id = ApprovalId::from_str(&approval_id)
            .map_err(|_| "invalid_approval_id: expected a canonical UUID".to_owned())?;
        let handle = self.agent_runtime.handle(run_id)?;
        join_worker(&handle)?;
        let snapshot = handle
            .engine
            .reject(run_id, approval_id)
            .map_err(|error| format!("{}: {error}", error.code()))?;
        Ok(native_run(snapshot.run_id, snapshot.status))
    }

    pub fn rebase_agent_proposal(
        &self,
        run_id: String,
        approval_id: String,
        current_revision: u64,
    ) -> Result<NativeAgentRun, String> {
        self.agent_runtime.ensure_open()?;
        let run_id = parse_run_id(&run_id)?;
        let approval_id = ApprovalId::from_str(&approval_id)
            .map_err(|_| "invalid_approval_id: expected a canonical UUID".to_owned())?;
        let handle = self.agent_runtime.handle(run_id)?;
        join_worker(&handle)?;
        let snapshot = handle
            .engine
            .rebase(
                run_id,
                approval_id,
                DocumentRevision::from_value(current_revision),
            )
            .map_err(|error| format!("{}: {error}", error.code()))?;
        Ok(native_run(snapshot.run_id, snapshot.status))
    }

    pub fn cancel_agent_run(&self, run_id: String) -> Result<(), String> {
        self.agent_runtime.ensure_open()?;
        let run_id = parse_run_id(&run_id)?;
        let handle = self.agent_runtime.handle(run_id)?;
        if handle.engine.cancel(run_id) {
            Ok(())
        } else {
            Err("agent_run_not_found: run cannot be cancelled".into())
        }
    }

    pub fn read_agent_audit(&self, run_id: String) -> Result<NativeAgentAudit, String> {
        self.agent_runtime.ensure_open()?;
        let run_id = parse_run_id(&run_id)?;
        let audit = self
            .agent_runtime
            .repository
            .read_run_audit(run_id)
            .map_err(|error| format!("{}: {error}", error.code()))?;
        let session_id = self.actor.session_id().to_string();
        Ok(NativeAgentAudit {
            schema_version: AGENT_SCHEMA_VERSION,
            run_id: run_id.to_string(),
            status: status_name(audit.header.status).into(),
            events: audit
                .events
                .iter()
                .map(|event| native_event(&session_id, event))
                .collect(),
        })
    }
}

fn join_worker(handle: &NativeRunHandle) -> Result<(), String> {
    if let Some(worker) = handle
        .worker
        .lock()
        .map_err(|_| "agent_runtime_poisoned: worker".to_owned())?
        .take()
    {
        worker
            .join()
            .map_err(|_| "agent_worker_panicked: provider worker failed".to_owned())?;
    }
    Ok(())
}

fn core_selection(selection: NativeSelectionSet) -> Result<SelectionSet, String> {
    Ok(SelectionSet {
        revision: DocumentRevision::from_value(selection.expected_revision),
        kind: match selection.kind {
            NativeSelectionKind::TextRanges => SelectionKind::TextRanges,
            NativeSelectionKind::Objects => SelectionKind::Objects,
        },
        ranges: selection
            .ranges
            .into_iter()
            .map(|range| {
                Ok(TextRangeRef {
                    object_id: ObjectId::from_str(&range.object_id)
                        .map_err(|_| "invalid_object_id: expected a canonical UUID")?,
                    page_id: PageId::from_str(&range.page_id)
                        .map_err(|_| "invalid_page_id: expected a canonical UUID")?,
                    page_number: range.page_number,
                    start_utf16: range.start_utf16,
                    end_utf16: range.end_utf16,
                    quoted_text: range.quoted_text,
                })
            })
            .collect::<Result<Vec<_>, &str>>()
            .map_err(str::to_owned)?,
        object_ids: selection
            .object_ids
            .iter()
            .map(|id| {
                ObjectId::from_str(id)
                    .map_err(|_| "invalid_object_id: expected a canonical UUID".to_owned())
            })
            .collect::<Result<Vec<_>, _>>()?,
        primary_index: selection.primary_index,
    })
}

fn native_selection_context(context: SelectionContext) -> Result<NativeSelectionContext, String> {
    let disclosure_sha256 = disclosure_digest(&context)?;
    let page_numbers = context
        .ranges
        .iter()
        .map(|range| range.page_number)
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect();
    Ok(NativeSelectionContext {
        schema_version: AGENT_SCHEMA_VERSION,
        document_id: context.document_id.to_string(),
        revision: context.document_revision.value(),
        kind: match context.kind {
            SelectionKind::TextRanges => NativeSelectionKind::TextRanges,
            SelectionKind::Objects => NativeSelectionKind::Objects,
        },
        ranges: context
            .ranges
            .into_iter()
            .map(|range| NativeSelectionRange {
                object_id: range.object_id.to_string(),
                page_id: range.page_id.to_string(),
                page_number: range.page_number,
                start_utf16: range.start_utf16,
                end_utf16: range.end_utf16,
                quoted_text: range.quoted_text,
            })
            .collect(),
        page_numbers,
        nearby_text_before: context.nearby_text_before,
        nearby_text_after: context.nearby_text_after,
        disclosure_sha256,
    })
}

fn disclosure_digest(context: &SelectionContext) -> Result<String, String> {
    serde_json::to_vec(context)
        .map(|bytes| format!("{:x}", Sha256::digest(bytes)))
        .map_err(|error| format!("disclosure_serialization_failed: {error}"))
}

fn native_event(session_id: &str, event: &clarix_agent_core::AgentRunEvent) -> NativeAgentEvent {
    NativeAgentEvent {
        schema_version: AGENT_SCHEMA_VERSION,
        session_id: session_id.into(),
        run_id: event.run_id.to_string(),
        sequence: event.sequence,
        document_revision: event.document_revision.value(),
        kind: event_kind_name(&event.kind).into(),
        payload_json: serde_json::to_string(&event.kind).unwrap_or_else(|_| "null".into()),
    }
}

fn event_kind_name(kind: &AgentRunEventKind) -> &'static str {
    match kind {
        AgentRunEventKind::StatusChanged { .. } => "statusChanged",
        AgentRunEventKind::TextDelta { .. } => "textDelta",
        AgentRunEventKind::ContextDisclosed { .. } => "contextDisclosed",
        AgentRunEventKind::ToolStarted { .. } => "toolStarted",
        AgentRunEventKind::ToolCompleted { .. } => "toolCompleted",
        AgentRunEventKind::ApprovalRequested { .. } => "approvalRequested",
        AgentRunEventKind::ApprovalResolved { .. } => "approvalResolved",
        AgentRunEventKind::CommandCommitted { .. } => "commandCommitted",
        AgentRunEventKind::SaveRequested => "saveRequested",
        AgentRunEventKind::BudgetPaused { .. } => "budgetPaused",
        AgentRunEventKind::Finished { .. } => "finished",
    }
}

fn native_run(run_id: AgentRunId, status: AgentRunStatus) -> NativeAgentRun {
    NativeAgentRun {
        schema_version: AGENT_SCHEMA_VERSION,
        run_id: run_id.to_string(),
        status: status_name(status).into(),
    }
}

fn status_name(status: AgentRunStatus) -> &'static str {
    match status {
        AgentRunStatus::Queued => "queued",
        AgentRunStatus::AssemblingContext => "assemblingContext",
        AgentRunStatus::CallingProvider => "callingProvider",
        AgentRunStatus::ExecutingTool => "executingTool",
        AgentRunStatus::AwaitingApproval => "awaitingApproval",
        AgentRunStatus::BudgetPaused => "budgetPaused",
        AgentRunStatus::Completed => "completed",
        AgentRunStatus::Cancelled => "cancelled",
        AgentRunStatus::Failed => "failed",
    }
}

fn parse_run_id(value: &str) -> Result<AgentRunId, String> {
    AgentRunId::from_str(value).map_err(|_| "invalid_run_id: expected a canonical UUID".to_owned())
}
