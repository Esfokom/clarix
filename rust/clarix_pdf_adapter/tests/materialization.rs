use std::path::PathBuf;

use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentModel, DocumentObject, EditCapability, EditorCommand,
    EditorSessionState, FontFallbackApproval, FontRef, FontSource, SessionId, SourceGlyph,
    TextBlock, TextLayoutRecipe, Utf16Range,
};
use clarix_pdf_adapter::{
    IndependentPdfValidator, InstalledFontCatalog, InstalledFontRequest, PdfImporter,
    PdfOxideImporter, PdfTextMaterializer, SourceRef,
};
use lopdf::content::Content;

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
    .with_character_boxes(original.character_boxes.clone())
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
fn approved_fallback_is_embedded_and_reopens_as_searchable_text() {
    let directory = tempfile::tempdir().unwrap();
    let output = directory.path().join("fallback.pdf");
    let model = qualified_snapshot();
    let object_id = model.pages[0].objects[0].id();
    let face = InstalledFontCatalog::windows()
        .propose(&InstalledFontRequest {
            preferred_family: "Arial".into(),
            weight: 400,
            italic: false,
            text: "€".into(),
        })
        .expect("Windows must provide an embeddable fallback for the euro sign");
    let mut session = EditorSessionState::new(SessionId::new(), model);
    session
        .submit(CommandEnvelope::user(
            CommandId::new(),
            session.revision(),
            EditorCommand::ReplaceTextRangeWithFontFallback {
                object_id,
                range: Utf16Range::new(0, 5).unwrap(),
                replacement: "€".into(),
                approval: Box::new(FontFallbackApproval {
                    proposal_token: CommandId::new().to_string(),
                    font: FontRef {
                        postscript_name: face.postscript_name,
                        bytes_sha256: face.bytes_sha256,
                        asset_id: Some(face.path.to_string_lossy().into_owned()),
                        source: FontSource::ApprovedFallback,
                        embeddable: true,
                    },
                    glyphs: face.glyphs,
                }),
            },
        ))
        .unwrap();

    PdfTextMaterializer::new(source())
        .materialize_snapshot(&session.snapshot().unwrap(), &output)
        .unwrap();

    let saved = lopdf::Document::load(&output).unwrap();
    let page_id = saved.get_pages()[&1];
    let operations = Content::decode(&saved.get_page_content(page_id).unwrap())
        .unwrap()
        .operations;
    let fallback_selection = operations
        .iter()
        .position(|operation| {
            operation.operator == "Tf"
                && operation.operands.first().is_some_and(
                    |operand| matches!(operand, lopdf::Object::Name(name) if name.starts_with(b"ClarixFallback")),
                )
        })
        .expect("saved content must select the embedded fallback font");
    assert!(matches!(
        operations.get(fallback_selection + 1),
        Some(operation) if matches!(operation.operator.as_str(), "Tj" | "TJ" | "'" | "\"")
    ));
    assert!(matches!(
        operations.get(fallback_selection + 2),
        Some(operation) if operation.operator == "Tf"
            && operation.operands.first().is_some_and(
                |operand| matches!(operand, lopdf::Object::Name(name) if !name.starts_with(b"ClarixFallback")),
            )
    ));

    let reopened = SourceRef::from_path(output).unwrap();
    let page = PdfOxideImporter.inspect_page(&reopened, 1).unwrap();
    assert!(page
        .page
        .objects
        .iter()
        .any(|object| matches!(object, DocumentObject::Text(text) if text.text == "€")));
}

#[test]
fn unqualified_snapshot_is_rejected_before_output_exists() {
    let source = source();
    let imported = PdfOxideImporter.inspect_page(&source, 1).unwrap();
    let mut page = imported.page;
    let object = &page.objects[0];
    let DocumentObject::Text(text) = object else {
        panic!("fixture must contain text")
    };
    page.objects[0] = DocumentObject::text(TextBlock::plain(
        object.id(),
        object.page_id(),
        text.text.clone(),
        object.bounds(),
    ));
    let model = DocumentModel::new(
        clarix_editing_core::DocumentId::from_source_key("unqualified-test"),
        source.fingerprint().into(),
        vec![page],
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

#[test]
fn repeated_materialize_validate_cycles_leave_only_expected_outputs() {
    let directory = tempfile::tempdir().unwrap();
    let snapshot = qualified_snapshot();
    let materializer = PdfTextMaterializer::new(source());
    for cycle in 0..25 {
        let output = directory.path().join(format!("cycle-{cycle}.pdf"));
        materializer
            .materialize_snapshot(&snapshot, &output)
            .unwrap();
        let report = IndependentPdfValidator
            .validate_document(&output, 1)
            .unwrap();
        assert!(report.valid, "cycle {cycle}: {:?}", report.failures);
    }
    let files = std::fs::read_dir(directory.path())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect::<Vec<_>>();
    assert_eq!(files.len(), 25);
    assert!(files
        .iter()
        .all(|path| { path.extension().and_then(|extension| extension.to_str()) == Some("pdf") }));
}
