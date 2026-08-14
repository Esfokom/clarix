use clarix_editing_core::{
    CapabilityReason, EditCapability, FontRef, FontSource, ObjectId, OverflowPolicy,
    ParagraphStyle, SourceBinding, SourceGlyph, TextAffinity, TextAlignment, TextAnchor, TextBlock,
    TextLayoutRecipe, WritingDirection,
};

#[test]
fn text_anchor_rejects_surrogate_and_non_grapheme_boundaries() {
    let object_id = ObjectId::from_source_key("anchor/object");
    let text = "A👩🏽‍💻e\u{301}";

    assert!(TextAnchor::new(object_id, text, 1, TextAffinity::Downstream).is_ok());
    assert_eq!(
        TextAnchor::new(object_id, text, 2, TextAffinity::Downstream)
            .unwrap_err()
            .code(),
        "invalid_text_boundary"
    );
    assert_eq!(
        TextAnchor::new(object_id, text, 9, TextAffinity::Downstream)
            .unwrap_err()
            .code(),
        "invalid_grapheme_boundary"
    );
}

#[test]
fn phase1_text_contract_round_trips_all_materialization_fields() {
    let font = FontRef {
        postscript_name: "FixtureSans-Regular".into(),
        bytes_sha256: "a".repeat(64),
        asset_id: Some("sha256:fixture-font".into()),
        source: FontSource::Embedded,
        embeddable: true,
    };
    let layout = TextLayoutRecipe {
        paragraph: ParagraphStyle {
            alignment: TextAlignment::Center,
            line_spacing: 1.25,
        },
        baseline: 12.0,
        line_height: 14.0,
        character_spacing: 0.5,
        horizontal_scale: 0.95,
        direction: WritingDirection::LeftToRight,
        overflow: OverflowPolicy::Reject,
    };
    let glyphs = vec![SourceGlyph {
        utf16_start: 0,
        utf16_end: 1,
        character_code: 65,
        glyph_id: 36,
    }];
    let reason = CapabilityReason {
        code: "font_encoding_incomplete".into(),
        message: "the source encoding cannot represent new characters".into(),
    };

    let encoded = serde_json::to_string(&(font, layout, glyphs, reason)).unwrap();
    let decoded: (
        FontRef,
        TextLayoutRecipe,
        Vec<SourceGlyph>,
        CapabilityReason,
    ) = serde_json::from_str(&encoded).unwrap();

    assert_eq!(decoded.0.postscript_name, "FixtureSans-Regular");
    assert_eq!(decoded.1.paragraph.alignment, TextAlignment::Center);
    assert_eq!(decoded.2[0].glyph_id, 36);
    assert_eq!(decoded.3.code, "font_encoding_incomplete");
}

#[test]
fn imported_editable_text_requires_font_and_materialization_contract() {
    let page_id = clarix_editing_core::PageId::from_source_key("contract/page");
    let object_id = ObjectId::from_source_key("contract/object");
    let block = TextBlock::plain(
        object_id,
        page_id,
        "A",
        clarix_editing_core::PdfBox::new(0.0, 0.0, 10.0, 10.0).unwrap(),
    )
    .with_source_binding(SourceBinding {
        adapter_id: "fixture".into(),
        source_revision: "sha256:source".into(),
        source_key: "page/1/text/1".into(),
        confidence: 1.0,
    });
    let page = clarix_editing_core::PageNode::new(
        page_id,
        1,
        100.0,
        100.0,
        vec![clarix_editing_core::DocumentObject::text(block)],
    );

    let error = clarix_editing_core::DocumentModel::new(
        clarix_editing_core::DocumentId::from_source_key("contract"),
        "sha256:source".into(),
        vec![page],
    )
    .unwrap_err();
    assert!(matches!(
        error,
        clarix_editing_core::ModelError::IncompleteEditableText(id) if id == object_id
    ));
    let _ = EditCapability::Editable;
}
