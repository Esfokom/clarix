use std::sync::{Arc, Mutex};

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DurableCommit,
    DurableSnapshot, EditorCommand, EditorSessionActor, MaterializationRecord, ObjectId, PageId,
    PageNode, PdfBox, PersistenceError, ProjectCheckpoint, ProjectRepository, RecoveredProject,
    RecoveryRequest, SessionId, TextBlock, Utf16Range,
};
use clarix_editing_store::{ProjectLocation, ProjectSeed, SqliteProjectRepository};
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn fixture() -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("sidecar-bench/page/1");
    let object_id = ObjectId::from_source_key("sidecar-bench/object/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("sidecar-bench/document"),
        "sha256:sidecar-bench".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                "A",
                PdfBox::new(0.0, 0.0, 20.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

fn submit_next(actor: &EditorSessionActor, object_id: ObjectId) {
    let snapshot = actor.snapshot().unwrap();
    let text = match snapshot.object(object_id).unwrap() {
        DocumentObject::Text(block) => block.text.as_str(),
        _ => unreachable!(),
    };
    let payload = if text == "A" {
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(0, 1).unwrap(),
            replacement: "B".into(),
        }
    } else {
        EditorCommand::Undo
    };
    black_box(
        actor
            .submit(CommandEnvelope::user(
                CommandId::new(),
                snapshot.revision,
                payload,
            ))
            .unwrap(),
    );
}

struct MemoryRepository(Mutex<RecoveredProject>);

impl MemoryRepository {
    fn new(model: DocumentModel) -> Self {
        Self(Mutex::new(RecoveredProject {
            model,
            undo_cursor: 0,
            materialized_revision: None,
            warnings: Vec::new(),
            commands: Vec::new(),
        }))
    }
}

impl ProjectRepository for MemoryRepository {
    fn recover(&self, _: RecoveryRequest) -> Result<RecoveredProject, PersistenceError> {
        Ok(self.0.lock().unwrap().clone())
    }

    fn append(&self, commit: &DurableCommit) -> Result<(), PersistenceError> {
        let mut recovered = self.0.lock().unwrap();
        recovered.model = commit.resulting_model.clone();
        recovered.undo_cursor = commit.undo_cursor;
        recovered.commands.push(commit.into());
        Ok(())
    }

    fn write_snapshot(&self, _: &DurableSnapshot) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn checkpoint(&self, _: &ProjectCheckpoint) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn record_materialization(&self, _: MaterializationRecord) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn close(&self) -> Result<(), PersistenceError> {
        Ok(())
    }
}

fn sidecar_latency(c: &mut Criterion) {
    let (memory_model, memory_object) = fixture();
    let memory_actor = EditorSessionActor::spawn_durable(
        SessionId::new(),
        memory_model.clone(),
        Arc::new(MemoryRepository::new(memory_model)),
    );
    c.bench_function("sidecar_ack/in_memory_warm_actor", |b| {
        b.iter(|| submit_next(&memory_actor, memory_object))
    });
    memory_actor.close().unwrap();

    let directory = tempfile::tempdir().unwrap();
    let (sqlite_model, sqlite_object) = fixture();
    let location = ProjectLocation::under(directory.path(), sqlite_model.id);
    let repository = Arc::new(
        SqliteProjectRepository::open(
            location,
            ProjectSeed {
                model: sqlite_model.clone(),
                undo_cursor: 0,
                materialized_revision: None,
            },
        )
        .unwrap(),
    );
    let sqlite_actor = EditorSessionActor::spawn_durable(
        SessionId::new(),
        sqlite_model.clone(),
        repository.clone(),
    );
    c.bench_function("sidecar_ack/sqlite_durable", |b| {
        b.iter(|| submit_next(&sqlite_actor, sqlite_object))
    });
    sqlite_actor.close().unwrap();

    let recovery = RecoveryRequest {
        document_id: sqlite_model.id,
        source_fingerprint: sqlite_model.source_fingerprint.clone(),
    };
    c.bench_function("sidecar_recovery/current_snapshot", |b| {
        b.iter(|| black_box(repository.recover(black_box(recovery.clone())).unwrap()))
    });
    let snapshot = repository.recover(recovery).unwrap();
    let durable_snapshot = DurableSnapshot {
        revision: snapshot.model.revision,
        undo_cursor: snapshot.undo_cursor,
        model: snapshot.model,
    };
    c.bench_function("sidecar_snapshot/sqlite", |b| {
        b.iter(|| {
            repository
                .write_snapshot(black_box(&durable_snapshot))
                .unwrap()
        })
    });
}

criterion_group!(benches, sidecar_latency);
criterion_main!(benches);
