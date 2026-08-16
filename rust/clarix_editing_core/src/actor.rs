use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

use crossbeam_channel::{bounded, Receiver, Sender, TrySendError};
use serde::{Deserialize, Serialize};

use crate::{
    CommandEnvelope, CommandResult, DocumentModel, DocumentRevision, DurableCommit, EditingError,
    EditorSessionState, PageNode, ProjectRepository, RecoveryRequest, SessionId,
};

const REQUEST_CAPACITY: usize = 64;
const DEFAULT_SUBSCRIBER_CAPACITY: usize = 32;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum EditorEvent {
    Ready { revision: DocumentRevision },
    CommandCommitted { result: CommandResult },
    Lagged { latest_revision: DocumentRevision },
    Closed { revision: DocumentRevision },
}

enum ActorRequest {
    Submit {
        command: CommandEnvelope,
        reply: Sender<Result<CommandResult, EditingError>>,
    },
    Snapshot {
        reply: Sender<Result<DocumentModel, EditingError>>,
    },
    Subscribe {
        capacity: usize,
        reply: Sender<Result<Receiver<EditorEvent>, EditingError>>,
    },
    HydratePage {
        page: PageNode,
        expected_revision: DocumentRevision,
        reply: Sender<Result<(), EditingError>>,
    },
    Close {
        reply: Sender<Result<(), EditingError>>,
    },
    Shutdown,
}

struct Subscriber {
    sender: Sender<EditorEvent>,
    lagged: bool,
}

struct ActorInner {
    sender: Sender<ActorRequest>,
    session_id: SessionId,
    closed: AtomicBool,
    worker: Mutex<Option<std::thread::JoinHandle<()>>>,
}

impl Drop for ActorInner {
    fn drop(&mut self) {
        self.closed.store(true, Ordering::Release);
        let _ = self.sender.send(ActorRequest::Shutdown);
        if let Ok(worker) = self.worker.get_mut() {
            if let Some(worker) = worker.take() {
                let _ = worker.join();
            }
        }
    }
}

#[derive(Clone)]
pub struct EditorSessionActor {
    inner: Arc<ActorInner>,
}

impl EditorSessionActor {
    pub fn spawn(model: DocumentModel) -> Self {
        Self::spawn_with_session(SessionId::new(), model)
    }

    pub fn spawn_with_session(session_id: SessionId, model: DocumentModel) -> Self {
        Self::spawn_with_repository(session_id, model, None)
    }

    pub fn spawn_durable(
        session_id: SessionId,
        model: DocumentModel,
        repository: Arc<dyn ProjectRepository>,
    ) -> Self {
        Self::spawn_with_repository(session_id, model, Some(repository))
    }

    pub fn spawn_recovered(
        session_id: SessionId,
        repository: Arc<dyn ProjectRepository>,
        request: RecoveryRequest,
    ) -> Result<Self, EditingError> {
        let recovered = repository
            .recover(request)
            .map_err(|error| EditingError::SidecarCommitFailed(error.to_string()))?;
        let undo_cursor = recovered.undo_cursor;
        let state =
            EditorSessionState::from_recovered(session_id, recovered.model, recovered.commands)?;
        if state.undo_cursor() != undo_cursor {
            return Err(EditingError::SidecarCommitFailed(
                "recovered history cursor does not match the journal".into(),
            ));
        }
        Ok(Self::spawn_with_state(state, Some(repository)))
    }

    fn spawn_with_repository(
        session_id: SessionId,
        model: DocumentModel,
        repository: Option<Arc<dyn ProjectRepository>>,
    ) -> Self {
        Self::spawn_with_state(EditorSessionState::new(session_id, model), repository)
    }

    fn spawn_with_state(
        session: EditorSessionState,
        repository: Option<Arc<dyn ProjectRepository>>,
    ) -> Self {
        let session_id = session.session_id();
        let (sender, receiver) = bounded(REQUEST_CAPACITY);
        let worker = std::thread::Builder::new()
            .name(format!("clarix-editor-{session_id}"))
            .spawn(move || run_actor(receiver, session, repository))
            .expect("failed to spawn editor session actor");
        Self {
            inner: Arc::new(ActorInner {
                sender,
                session_id,
                closed: AtomicBool::new(false),
                worker: Mutex::new(Some(worker)),
            }),
        }
    }

    pub fn session_id(&self) -> SessionId {
        self.inner.session_id
    }

    pub fn submit(&self, command: CommandEnvelope) -> Result<CommandResult, EditingError> {
        self.ensure_open()?;
        let (reply, response) = bounded(1);
        self.inner
            .sender
            .send(ActorRequest::Submit { command, reply })
            .map_err(|_| EditingError::ActorUnavailable)?;
        response
            .recv()
            .map_err(|_| EditingError::ActorUnavailable)?
    }

    pub fn snapshot(&self) -> Result<DocumentModel, EditingError> {
        self.ensure_open()?;
        let (reply, response) = bounded(1);
        self.inner
            .sender
            .send(ActorRequest::Snapshot { reply })
            .map_err(|_| EditingError::ActorUnavailable)?;
        response
            .recv()
            .map_err(|_| EditingError::ActorUnavailable)?
    }

    pub fn subscribe(&self) -> Result<Receiver<EditorEvent>, EditingError> {
        self.subscribe_with_capacity(DEFAULT_SUBSCRIBER_CAPACITY)
    }

    pub fn hydrate_page(
        &self,
        page: PageNode,
        expected_revision: DocumentRevision,
    ) -> Result<(), EditingError> {
        self.ensure_open()?;
        let (reply, response) = bounded(1);
        self.inner
            .sender
            .send(ActorRequest::HydratePage {
                page,
                expected_revision,
                reply,
            })
            .map_err(|_| EditingError::ActorUnavailable)?;
        response
            .recv()
            .map_err(|_| EditingError::ActorUnavailable)?
    }

    pub fn subscribe_with_capacity(
        &self,
        capacity: usize,
    ) -> Result<Receiver<EditorEvent>, EditingError> {
        self.ensure_open()?;
        if capacity == 0 {
            return Err(EditingError::InvalidCommand(
                "subscriber capacity must be greater than zero".into(),
            ));
        }
        let (reply, response) = bounded(1);
        self.inner
            .sender
            .send(ActorRequest::Subscribe { capacity, reply })
            .map_err(|_| EditingError::ActorUnavailable)?;
        response
            .recv()
            .map_err(|_| EditingError::ActorUnavailable)?
    }

    pub fn close(&self) -> Result<(), EditingError> {
        if self.inner.closed.swap(true, Ordering::AcqRel) {
            return Ok(());
        }
        let (reply, response) = bounded(1);
        if self
            .inner
            .sender
            .send(ActorRequest::Close { reply })
            .is_err()
        {
            return Err(EditingError::ActorUnavailable);
        }
        let result = response
            .recv()
            .map_err(|_| EditingError::ActorUnavailable)?;
        if let Some(worker) = self
            .inner
            .worker
            .lock()
            .map_err(|_| EditingError::ActorUnavailable)?
            .take()
        {
            worker.join().map_err(|_| EditingError::ActorUnavailable)?;
        }
        result
    }

    fn ensure_open(&self) -> Result<(), EditingError> {
        if self.inner.closed.load(Ordering::Acquire) {
            Err(EditingError::SessionClosed)
        } else {
            Ok(())
        }
    }
}

fn run_actor(
    receiver: Receiver<ActorRequest>,
    mut session: EditorSessionState,
    repository: Option<Arc<dyn ProjectRepository>>,
) {
    let mut subscribers: Vec<Subscriber> = Vec::new();
    while let Ok(request) = receiver.recv() {
        match request {
            ActorRequest::Submit { command, reply } => {
                let result = if let Some(repository) = &repository {
                    session.prepare(command).and_then(|prepared| {
                        repository
                            .append(&DurableCommit::from_prepared(&prepared))
                            .map_err(|error| {
                                EditingError::SidecarCommitFailed(error.to_string())
                            })?;
                        let mut result = session.publish(prepared)?;
                        result.durable = true;
                        Ok(result)
                    })
                } else {
                    session.submit(command)
                };
                if let Ok(committed) = &result {
                    broadcast(
                        &mut subscribers,
                        EditorEvent::CommandCommitted {
                            result: committed.clone(),
                        },
                        committed.committed_revision,
                    );
                }
                let _ = reply.send(result);
            }
            ActorRequest::Snapshot { reply } => {
                let _ = reply.send(session.snapshot());
            }
            ActorRequest::Subscribe { capacity, reply } => {
                let (sender, events) = bounded(capacity);
                let ready = EditorEvent::Ready {
                    revision: session.revision(),
                };
                if sender.try_send(ready).is_err() {
                    let _ = reply.send(Err(EditingError::ActorUnavailable));
                } else {
                    subscribers.push(Subscriber {
                        sender,
                        lagged: false,
                    });
                    let _ = reply.send(Ok(events));
                }
            }
            ActorRequest::HydratePage {
                page,
                expected_revision,
                reply,
            } => {
                let _ = reply.send(session.hydrate_page(page, expected_revision));
            }
            ActorRequest::Close { reply } => {
                let revision = session.revision();
                session.close();
                let result = repository
                    .as_ref()
                    .map_or(Ok(()), |repository| repository.close())
                    .map_err(|error| EditingError::SidecarCommitFailed(error.to_string()));
                if result.is_ok() {
                    broadcast(&mut subscribers, EditorEvent::Closed { revision }, revision);
                }
                let _ = reply.send(result);
                break;
            }
            ActorRequest::Shutdown => break,
        }
    }
}

fn broadcast(
    subscribers: &mut Vec<Subscriber>,
    event: EditorEvent,
    latest_revision: DocumentRevision,
) {
    subscribers.retain_mut(|subscriber| {
        if subscriber.lagged {
            match subscriber
                .sender
                .try_send(EditorEvent::Lagged { latest_revision })
            {
                Ok(()) => subscriber.lagged = false,
                Err(TrySendError::Full(_)) => return true,
                Err(TrySendError::Disconnected(_)) => return false,
            }
        }
        match subscriber.sender.try_send(event.clone()) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) => {
                subscriber.lagged = true;
                true
            }
            Err(TrySendError::Disconnected(_)) => false,
        }
    });
}
