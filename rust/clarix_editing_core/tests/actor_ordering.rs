use std::sync::{Arc, Barrier};

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditingError, EditorCommand, EditorEvent, EditorSessionActor, ObjectId, PageId, PageNode,
    PdfBox, SearchMode, SearchRequest, TextBlock, Utf16Range,
};

#[test]
fn actor_validates_selection_against_its_current_revision() {
    let (model, object_id) = sample_model("selection");
    let actor = EditorSessionActor::spawn(model);
    let selection = actor
        .validate_selection(clarix_editing_core::SelectionSet {
            revision: DocumentRevision::INITIAL,
            kind: clarix_editing_core::SelectionKind::Objects,
            ranges: Vec::new(),
            object_ids: vec![object_id],
            primary_index: Some(0),
        })
        .unwrap();
    assert_eq!(selection.object_ids, vec![object_id]);
    actor.close().unwrap();
}

fn sample_model(text: &str) -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("actor-test/page/1");
    let object_id = ObjectId::from_source_key("actor-test/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("actor-test"),
        "sha256:actor-test".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(TextBlock::plain(
                object_id,
                page_id,
                text,
                PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

fn replace(
    object_id: ObjectId,
    base_revision: u64,
    range_end: u32,
    replacement: &str,
) -> CommandEnvelope {
    let mut revision = DocumentRevision::INITIAL;
    for _ in 0..base_revision {
        revision = revision.next().unwrap();
    }
    CommandEnvelope::user(
        CommandId::new(),
        revision,
        EditorCommand::ReplaceTextRange {
            object_id,
            range: Utf16Range::new(0, range_end).unwrap(),
            replacement: replacement.into(),
        },
    )
}

#[test]
fn actor_emits_commits_in_revision_order_and_closes_cleanly() {
    let (model, object_id) = sample_model("A");
    let actor = EditorSessionActor::spawn(model);
    let events = actor.subscribe().unwrap();
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::Ready { revision } if revision.value() == 0
    ));
    assert_eq!(
        actor
            .submit(replace(object_id, 0, 1, "AB"))
            .unwrap()
            .committed_revision
            .value(),
        1
    );
    assert_eq!(
        actor
            .submit(replace(object_id, 1, 2, "ABC"))
            .unwrap()
            .committed_revision
            .value(),
        2
    );
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::CommandCommitted { result } if result.committed_revision.value() == 1
    ));
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::CommandCommitted { result } if result.committed_revision.value() == 2
    ));
    actor.close().unwrap();
    assert_eq!(actor.snapshot().unwrap_err().code(), "session_closed");
    actor.close().unwrap();
}

#[test]
fn actor_prepares_without_publication_then_publishes_once() {
    let (model, object_id) = sample_model("Before");
    let actor = EditorSessionActor::spawn(model);
    let events = actor.subscribe().unwrap();
    let _ = events.recv().unwrap();

    let prepared = actor.prepare(replace(object_id, 0, 6, "After")).unwrap();
    assert_eq!(
        actor.snapshot().unwrap().revision,
        DocumentRevision::INITIAL
    );
    assert!(matches!(
        actor.snapshot().unwrap().object(object_id),
        Some(DocumentObject::Text(block)) if block.text == "Before"
    ));
    assert!(events.try_recv().is_err());

    let result = actor.publish(prepared).unwrap();
    assert_eq!(result.committed_revision.value(), 1);
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::CommandCommitted { result } if result.committed_revision.value() == 1
    ));
    actor.close().unwrap();
}

#[test]
fn concurrent_callers_commit_unique_increasing_revisions() {
    let (model, _) = sample_model("A");
    let actor = EditorSessionActor::spawn(model);
    let barrier = Arc::new(Barrier::new(8));
    let mut threads = Vec::new();

    for caller in 0..8 {
        let actor = actor.clone();
        let barrier = Arc::clone(&barrier);
        threads.push(std::thread::spawn(move || {
            barrier.wait();
            loop {
                let revision = actor.snapshot().unwrap().revision;
                let command = CommandEnvelope::user(
                    CommandId::new(),
                    revision,
                    EditorCommand::CreateCheckpoint {
                        label: format!("caller-{caller}"),
                    },
                );
                match actor.submit(command) {
                    Ok(result) => return result.committed_revision.value(),
                    Err(EditingError::RevisionConflict { .. }) => continue,
                    Err(error) => panic!("unexpected actor error: {error}"),
                }
            }
        }));
    }

    let mut revisions: Vec<_> = threads
        .into_iter()
        .map(|thread| thread.join().unwrap())
        .collect();
    revisions.sort_unstable();
    assert_eq!(revisions, vec![1, 2, 3, 4, 5, 6, 7, 8]);
    actor.close().unwrap();
}

#[test]
fn slow_subscriber_does_not_block_commits() {
    let (model, _) = sample_model("A");
    let actor = EditorSessionActor::spawn(model);
    let _unread_events = actor.subscribe_with_capacity(2).unwrap();

    for index in 0..10 {
        let revision = actor.snapshot().unwrap().revision;
        let result = actor
            .submit(CommandEnvelope::user(
                CommandId::new(),
                revision,
                EditorCommand::CreateCheckpoint {
                    label: format!("checkpoint-{index}"),
                },
            ))
            .unwrap();
        assert_eq!(result.committed_revision.value(), index + 1);
    }

    actor.close().unwrap();
}

#[test]
fn subscriber_receives_lagged_marker_after_capacity_returns() {
    let (model, _) = sample_model("A");
    let actor = EditorSessionActor::spawn(model);
    let events = actor.subscribe_with_capacity(2).unwrap();

    for index in 0..3 {
        let revision = actor.snapshot().unwrap().revision;
        actor
            .submit(CommandEnvelope::user(
                CommandId::new(),
                revision,
                EditorCommand::CreateCheckpoint {
                    label: format!("fill-{index}"),
                },
            ))
            .unwrap();
    }
    assert!(matches!(events.recv().unwrap(), EditorEvent::Ready { .. }));
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::CommandCommitted { .. }
    ));

    let revision = actor.snapshot().unwrap().revision;
    actor
        .submit(CommandEnvelope::user(
            CommandId::new(),
            revision,
            EditorCommand::CreateCheckpoint {
                label: "resume".into(),
            },
        ))
        .unwrap();
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::Lagged { latest_revision } if latest_revision.value() == 4
    ));
    assert!(matches!(
        events.recv().unwrap(),
        EditorEvent::CommandCommitted { result } if result.committed_revision.value() == 4
    ));
    actor.close().unwrap();
}

#[test]
fn actor_searches_the_current_revision_without_cross_thread_model_access() {
    let (model, _) = sample_model("draft draft");
    let actor = EditorSessionActor::spawn(model);

    let result = actor
        .search(SearchRequest {
            query: "draft".into(),
            mode: SearchMode::Exact,
            whole_word: true,
            offset: 0,
            limit: 10,
        })
        .unwrap();

    assert_eq!(result.revision, DocumentRevision::INITIAL);
    assert_eq!(result.total_matches, 2);
    actor.close().unwrap();
}
