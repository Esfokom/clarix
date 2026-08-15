use std::path::PathBuf;

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentModel, DocumentObject, EditCapability, EditorCommand,
    EditorSessionState, FontRef, FontSource, SessionId, SourceGlyph, TextBlock, TextLayoutRecipe,
    Utf16Range,
};
use clarix_pdf_adapter::{PdfImporter, PdfOxideImporter, PdfTextMaterializer, SourceRef};

fn source() -> SourceRef {
    SourceRef::from_path(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test_fixtures/editing_corpus/generated/standard-latin.pdf"),
    )
    .unwrap()
}

fn qualified_snapshot() -> DocumentModel {
    let source = source();
    let imported = PdfOxideImporter.inspect_page(&source, 1).unwrap();
    let object = &imported.page.objects[0];
    let object_id = object.id();
    let DocumentObject::Text(original) = object else {
        panic!("fixture must contain text")
    };
    let original_utf16_length = original.text.encode_utf16().count() as u32;
    let mut binding = object.source_binding().unwrap().clone();
    binding.confidence = 1.0;
    let allowed = format!("{}After", original.text);
    let mut utf16 = 0_u32;
    let source_glyphs = allowed
        .chars()
        .map(|character| {
            let start = utf16;
            utf16 += character.len_utf16() as u32;
            SourceGlyph {
                utf16_start: start,
                utf16_end: utf16,
                character_code: character as u32,
                glyph_id: character as u32,
            }
        })
        .collect();
    let mut qualified = TextBlock::plain(
        object.id(),
        object.page_id(),
        original.text.clone(),
        object.bounds(),
    )
    .with_source_binding(binding)
    .with_text_contract(
        FontRef {
            postscript_name: original.runs[0]
                .style
                .font_family
                .clone()
                .unwrap_or_else(|| "Helvetica".into()),
            bytes_sha256: "0".repeat(64),
            asset_id: Some("fixture-font".into()),
            source: FontSource::Embedded,
            embeddable: true,
        },
        TextLayoutRecipe {
            baseline: original.layout.baseline,
            line_height: original.layout.line_height,
            ..TextLayoutRecipe::default()
        },
        source_glyphs,
    )
    .with_capability(EditCapability::Editable, None);
    qualified.runs = original.runs.clone();
    let mut page = imported.page;
    page.objects[0] = DocumentObject::text(qualified);
    let model = DocumentModel::new(
        clarix_editing_core::DocumentId::from_source_key("materialization-test"),
        source.fingerprint().into(),
        vec![page],
    )
    .unwrap();
    let mut session = EditorSessionState::new(SessionId::new(), model);
    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            session.revision(),
            EditorCommand::ReplaceTextRange {
                object_id,
                range: Utf16Range::new(0, original_utf16_length).unwrap(),
                replacement: "After".into(),
            },
        ))
        .unwrap();
    session.snapshot().unwrap()
}

#[test]
fn replacement_survives_reopen_as_searchable_text() {
    let directory = tempfile::tempdir().unwrap();
    let output = directory.path().join("materialized.pdf");
    let snapshot = qualified_snapshot();

    PdfTextMaterializer::new(source())
        .materialize_snapshot(&snapshot, &output)
        .unwrap();

    let reopened = SourceRef::from_path(output).unwrap();
    let page = PdfOxideImporter.inspect_page(&reopened, 1).unwrap();
    assert!(page
        .page
        .objects
        .iter()
        .any(|object| matches!(object, DocumentObject::Text(text) if text.text == "After")));
}

#[test]
fn unqualified_snapshot_is_rejected_before_output_exists() {
    let source = source();
    let imported = PdfOxideImporter.inspect_page(&source, 1).unwrap();
    let model = DocumentModel::new(
        clarix_editing_core::DocumentId::from_source_key("unqualified-test"),
        source.fingerprint().into(),
        vec![imported.page],
    )
    .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let output = directory.path().join("rejected.pdf");

    let error = PdfTextMaterializer::new(source)
        .materialize_snapshot(&model, &output)
        .unwrap_err();

    assert_eq!(error.code(), "unsupported_materialization");
    assert!(!output.exists());
}
