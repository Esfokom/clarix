use clarix_editing_core::{
    CommandId, ContextLimits, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditingError, EditingToolGateway, EditorSessionActor, ObjectId, PageId, PageNode, PdfBox,
    ProposedToolEdit, SearchMode, SelectionKind, SelectionSet, TextBlock, TextRangeRef,
    ToolObservation, ToolRequest,
};

fn fixture_actor() -> (EditorSessionActor, ObjectId, ObjectId, PageId) {
    let page_id = PageId::from_source_key("agent-tools/page/1");
    let first_id = ObjectId::from_source_key("agent-tools/page/1/text/1");
    let second_id = ObjectId::from_source_key("agent-tools/page/1/text/2");
    let model = DocumentModel::new(
        DocumentId::from_source_key("agent-tools"),
        "sha256:agent-tools".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![
                DocumentObject::text(TextBlock::plain(
                    first_id,
                    page_id,
                    "alpha beta alpha",
                    PdfBox::new(0.0, 0.0, 100.0, 20.0).unwrap(),
                )),
                DocumentObject::text(TextBlock::plain(
                    second_id,
                    page_id,
                    "second",
                    PdfBox::new(0.0, 30.0, 100.0, 50.0).unwrap(),
                )),
            ],
        )],
    )
    .unwrap();
    (
        EditorSessionActor::spawn(model),
        first_id,
        second_id,
        page_id,
    )
}

fn selection(
    object_id: ObjectId,
    page_id: PageId,
    revision: DocumentRevision,
    start_utf16: u32,
    end_utf16: u32,
    quote: &str,
) -> SelectionSet {
    SelectionSet {
        revision,
        kind: SelectionKind::TextRanges,
        ranges: vec![TextRangeRef {
            object_id,
            page_id,
            page_number: 1,
            start_utf16,
            end_utf16,
            quoted_text: quote.into(),
        }],
        object_ids: vec![],
        primary_index: Some(0),
    }
}

#[test]
fn actor_gateway_inspects_exact_selection_and_revisioned_search() {
    let (actor, first_id, _, page_id) = fixture_actor();

    let inspected = actor
        .invoke(ToolRequest::InspectSelection {
            selection: selection(first_id, page_id, DocumentRevision::INITIAL, 0, 5, "alpha"),
            limits: ContextLimits::default(),
        })
        .unwrap();
    let searched = actor
        .invoke(ToolRequest::SearchText {
            revision: DocumentRevision::INITIAL,
            query: "alpha".into(),
            mode: SearchMode::Exact,
            whole_word: true,
            offset: 0,
            limit: 20,
        })
        .unwrap();

    let ToolObservation::Selection { context } = inspected else {
        panic!("inspect selection must return exact context")
    };
    assert_eq!(context.ranges[0].object_id, first_id);
    assert_eq!(context.ranges[0].quoted_text, "alpha");
    let ToolObservation::Search {
        revision,
        matches,
        total_matches,
        ..
    } = searched
    else {
        panic!("search must return stable text ranges")
    };
    assert_eq!(revision, DocumentRevision::INITIAL);
    assert_eq!(total_matches, 2);
    assert_eq!(matches.len(), 2);
    assert!(matches.iter().all(|matched| matched.object_id == first_id));
    actor.close().unwrap();
}

#[test]
fn actor_gateway_commits_one_exact_range_and_rejects_the_stale_selection() {
    let (actor, first_id, _, page_id) = fixture_actor();
    let target = selection(first_id, page_id, DocumentRevision::INITIAL, 0, 5, "alpha");

    let committed = actor
        .invoke(ToolRequest::ReplaceTextRange {
            command_id: CommandId::new(),
            selection: target.clone(),
            replacement: "omega".into(),
            provenance_ids: vec!["run-1".into(), "tool-1".into()],
        })
        .unwrap();
    let stale = actor.invoke(ToolRequest::ReplaceTextRange {
        command_id: CommandId::new(),
        selection: target,
        replacement: "other".into(),
        provenance_ids: vec!["run-1".into(), "tool-2".into()],
    });

    let ToolObservation::Command { result } = committed else {
        panic!("replacement must return a command acknowledgement")
    };
    assert_eq!(result.previous_revision, DocumentRevision::INITIAL);
    assert_eq!(result.committed_revision, DocumentRevision::from_value(1));
    assert_eq!(
        result.object_patches[0].text.as_deref(),
        Some("omega beta alpha")
    );
    assert_eq!(
        stale.unwrap_err(),
        EditingError::RevisionConflict {
            expected: DocumentRevision::INITIAL,
            actual: DocumentRevision::from_value(1),
        }
    );
    actor.close().unwrap();
}

#[test]
fn transaction_preview_is_immutable_and_commits_two_objects_once() {
    let (actor, first_id, second_id, page_id) = fixture_actor();
    let previewed = actor
        .invoke(ToolRequest::PreviewTransaction {
            revision: DocumentRevision::INITIAL,
            edits: vec![
                ProposedToolEdit::ReplaceText {
                    selection: selection(
                        first_id,
                        page_id,
                        DocumentRevision::INITIAL,
                        0,
                        5,
                        "alpha",
                    ),
                    replacement: "FIRST".into(),
                },
                ProposedToolEdit::ReplaceText {
                    selection: selection(
                        second_id,
                        page_id,
                        DocumentRevision::INITIAL,
                        0,
                        6,
                        "second",
                    ),
                    replacement: "SECOND".into(),
                },
            ],
        })
        .unwrap();

    let snapshot = actor.snapshot().unwrap();
    let DocumentObject::Text(first) = snapshot.object(first_id).unwrap() else {
        panic!("fixture object must remain text")
    };
    assert_eq!(first.text, "alpha beta alpha");
    assert_eq!(snapshot.revision, DocumentRevision::INITIAL);

    let ToolObservation::TransactionPreview { preview } = previewed else {
        panic!("preview request must return an immutable transaction preview")
    };
    let committed = actor
        .invoke(ToolRequest::CommitTransaction {
            command_id: CommandId::new(),
            preview_id: preview.preview_id,
            base_revision: preview.revision,
            provenance_ids: vec!["run-2".into(), "approval-1".into()],
        })
        .unwrap();

    let ToolObservation::Command { result } = committed else {
        panic!("approved transaction must return one command result")
    };
    assert_eq!(result.committed_revision, DocumentRevision::from_value(1));
    assert_eq!(result.object_patches.len(), 2);
    let snapshot = actor.snapshot().unwrap();
    let DocumentObject::Text(first) = snapshot.object(first_id).unwrap() else {
        panic!("first fixture object must remain text")
    };
    let DocumentObject::Text(second) = snapshot.object(second_id).unwrap() else {
        panic!("second fixture object must remain text")
    };
    assert_eq!(first.text, "FIRST beta alpha");
    assert_eq!(second.text, "SECOND");
    actor.close().unwrap();
}
