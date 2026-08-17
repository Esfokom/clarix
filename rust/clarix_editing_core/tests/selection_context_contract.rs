use clarix_editing_core::{
    ContextLimits, DocumentId, DocumentModel, DocumentObject, DocumentRevision, EditingError,
    EditorSessionActor, ObjectId, PageId, PageNode, PdfBox, SelectionContextBuilder, SelectionKind,
    SelectionSet, TextBlock, TextCharacterBox, TextRangeRef, TextRun, TextStyle, Utf16Range,
};

fn fixture_document(text: &str) -> (DocumentModel, ObjectId, PageId) {
    let page_id = PageId::from_source_key("selection-context/page/1");
    let object_id = ObjectId::from_source_key("selection-context/page/1/text/1");
    let text_len = text.encode_utf16().count() as u32;
    let mut offset = 0_u32;
    let boxes = text
        .chars()
        .map(|character| {
            let start = offset;
            offset += character.len_utf16() as u32;
            TextCharacterBox {
                range: Utf16Range::new(start, offset).unwrap(),
                bounds: PdfBox::new(f64::from(start) * 5.0, 10.0, f64::from(offset) * 5.0, 22.0)
                    .unwrap(),
            }
        })
        .collect();
    let mut block = TextBlock::plain(
        object_id,
        page_id,
        text,
        PdfBox::new(0.0, 10.0, f64::from(text_len) * 5.0, 22.0).unwrap(),
    )
    .with_character_boxes(boxes);
    block.runs = vec![TextRun {
        range: Utf16Range::new(0, text_len).unwrap(),
        style: TextStyle {
            font_family: Some("Inter".into()),
            font_size: 11.0,
            font_weight: 500,
            italic: false,
            color_rgba: [20, 30, 40, 255],
        },
    }];
    let model = DocumentModel::new(
        DocumentId::from_source_key("selection-context"),
        "sha256:selection-context".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::text(block)],
        )],
    )
    .unwrap();
    (model, object_id, page_id)
}

fn text_selection(
    object_id: ObjectId,
    page_id: PageId,
    start_utf16: u32,
    end_utf16: u32,
    quoted_text: &str,
) -> SelectionSet {
    SelectionSet {
        revision: DocumentRevision::INITIAL,
        kind: SelectionKind::TextRanges,
        ranges: vec![TextRangeRef {
            object_id,
            page_id,
            page_number: 1,
            start_utf16,
            end_utf16,
            quoted_text: quoted_text.into(),
        }],
        object_ids: vec![],
        primary_index: Some(0),
    }
}

#[test]
fn context_preserves_exact_target_style_geometry_and_bounded_nearby_text() {
    let (model, object_id, page_id) = fixture_document("Before selected after");
    let context = SelectionContextBuilder::build(
        &model,
        text_selection(object_id, page_id, 7, 15, "selected"),
        ContextLimits {
            before_utf16: 7,
            after_utf16: 6,
            max_ranges: 8,
        },
    )
    .unwrap();

    assert_eq!(context.document_id, model.id);
    assert_eq!(context.document_revision, DocumentRevision::INITIAL);
    assert_eq!(context.ranges.len(), 1);
    assert_eq!(context.ranges[0].object_id, object_id);
    assert_eq!(context.ranges[0].quoted_text, "selected");
    assert_eq!(context.page_ids, vec![page_id]);
    assert_eq!(context.nearby_text_before, "Before ");
    assert_eq!(context.nearby_text_after, " after");
    assert_eq!(context.style_summary.font_families, vec!["Inter"]);
    assert_eq!(context.style_summary.font_sizes, vec![11.0]);
    assert_eq!(context.style_summary.font_weights, vec![500]);
    assert_eq!(context.quads.len(), 8);
    assert_eq!(context.quads[0].bounds.left, 35.0);
    assert_eq!(context.quads[7].bounds.right, 75.0);
}

#[test]
fn context_rejects_a_stale_quote_with_a_specific_error() {
    let (model, object_id, page_id) = fixture_document("current");

    let error = SelectionContextBuilder::build(
        &model,
        text_selection(object_id, page_id, 0, 7, "previous"),
        ContextLimits::default(),
    )
    .unwrap_err();

    assert_eq!(error, EditingError::SelectionQuoteMismatch { object_id });
}

#[test]
fn context_clamps_nearby_text_without_splitting_utf16_characters() {
    let (model, object_id, page_id) = fixture_document("A😀B selected C😀D");
    let context = SelectionContextBuilder::build(
        &model,
        text_selection(object_id, page_id, 5, 13, "selected"),
        ContextLimits {
            before_utf16: 3,
            after_utf16: 4,
            max_ranges: 8,
        },
    )
    .unwrap();

    assert_eq!(context.nearby_text_before, "B ");
    assert_eq!(context.nearby_text_after, " C😀");
}

#[test]
fn context_enforces_the_range_budget_after_selection_validation() {
    let (model, object_id, page_id) = fixture_document("one two three");
    let selection = SelectionSet {
        revision: DocumentRevision::INITIAL,
        kind: SelectionKind::TextRanges,
        ranges: vec![
            TextRangeRef {
                object_id,
                page_id,
                page_number: 1,
                start_utf16: 0,
                end_utf16: 3,
                quoted_text: "one".into(),
            },
            TextRangeRef {
                object_id,
                page_id,
                page_number: 1,
                start_utf16: 8,
                end_utf16: 13,
                quoted_text: "three".into(),
            },
        ],
        object_ids: vec![],
        primary_index: Some(0),
    };

    let error = SelectionContextBuilder::build(
        &model,
        selection,
        ContextLimits {
            before_utf16: 10,
            after_utf16: 10,
            max_ranges: 1,
        },
    )
    .unwrap_err();

    assert_eq!(error.code(), "selection_limit_exceeded");
}

#[test]
fn actor_builds_context_from_its_current_revision() {
    let (model, object_id, page_id) = fixture_document("selected");
    let actor = EditorSessionActor::spawn(model);

    let context = actor
        .selection_context(
            text_selection(object_id, page_id, 0, 8, "selected"),
            ContextLimits::default(),
        )
        .unwrap();

    assert_eq!(context.ranges[0].quoted_text, "selected");
    assert_eq!(context.document_revision, DocumentRevision::INITIAL);
    actor.close().unwrap();
}
