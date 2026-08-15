use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use clarix_editing_core::{DocumentModel, DocumentObject, EditCapability};
use lopdf::content::Content;
use lopdf::{Object, StringFormat};

use crate::{
    contract::sha256_hex, DocumentSnapshot, PdfAdapterError, PdfMaterializer, SaveReport, SourceRef,
};

#[derive(Debug, Clone)]
pub struct PdfTextMaterializer {
    source: SourceRef,
}

impl PdfTextMaterializer {
    pub fn new(source: SourceRef) -> Self {
        Self { source }
    }

    pub fn materialize_snapshot(
        &self,
        snapshot: &DocumentModel,
        target: &Path,
    ) -> Result<SaveReport, PdfAdapterError> {
        if snapshot.source_fingerprint != self.source.fingerprint() {
            return Err(PdfAdapterError::FingerprintMismatch);
        }
        let mut replacements: BTreeMap<u32, Vec<(usize, String)>> = BTreeMap::new();
        for page in &snapshot.pages {
            for object in &page.objects {
                let DocumentObject::Text(text) = object else {
                    continue;
                };
                qualify_text(object, text)?;
                if object.modified_revision() == clarix_editing_core::DocumentRevision::INITIAL {
                    continue;
                }
                let occurrence = object
                    .source_binding()
                    .and_then(|binding| binding.source_key.rsplit('/').nth(1))
                    .and_then(|value| value.parse::<usize>().ok())
                    .ok_or_else(|| {
                        PdfAdapterError::UnsupportedMaterialization(
                            "text source locator has no deterministic occurrence".into(),
                        )
                    })?;
                replacements
                    .entry(page.page_number)
                    .or_default()
                    .push((occurrence, text.text.clone()));
            }
        }

        let mut output = lopdf::Document::load(self.source.path())
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        let pages = output.get_pages();
        for (page_number, page_replacements) in replacements {
            let page_id =
                pages
                    .get(&page_number)
                    .copied()
                    .ok_or(PdfAdapterError::PageOutOfRange {
                        requested: page_number,
                        page_count: pages.len() as u32,
                    })?;
            if output.get_page_contents(page_id).len() != 1 {
                return Err(PdfAdapterError::UnsupportedMaterialization(
                    "page content is split across ambiguous streams".into(),
                ));
            }
            let bytes = output
                .get_page_content(page_id)
                .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
            let mut content = Content::decode(&bytes)
                .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
            for (occurrence, replacement) in page_replacements {
                replace_text_occurrence(&mut content, occurrence, replacement.as_bytes())?;
            }
            let encoded = content
                .encode()
                .map_err(|error| PdfAdapterError::Adapter(error.to_string()))?;
            output
                .change_page_content(page_id, encoded)
                .map_err(|error| PdfAdapterError::Adapter(error.to_string()))?;
        }

        let parent = target.parent().unwrap_or_else(|| Path::new("."));
        if !parent.exists() {
            return Err(PdfAdapterError::Io(format!(
                "target directory does not exist: {}",
                parent.display()
            )));
        }
        let staging = staging_path(target);
        output
            .save(&staging)
            .map_err(|error| PdfAdapterError::Io(error.to_string()))?;
        std::fs::rename(&staging, target).map_err(|error| {
            let _ = std::fs::remove_file(&staging);
            PdfAdapterError::Io(error.to_string())
        })?;
        let bytes =
            std::fs::read(target).map_err(|error| PdfAdapterError::Io(error.to_string()))?;
        Ok(SaveReport {
            output_sha256: sha256_hex(&bytes),
            bytes_written: bytes.len() as u64,
            warnings: Vec::new(),
        })
    }
}

impl PdfMaterializer for PdfTextMaterializer {
    fn materialize(
        &self,
        snapshot: &DocumentSnapshot,
        target: &Path,
    ) -> Result<SaveReport, PdfAdapterError> {
        self.materialize_snapshot(&snapshot.model, target)
    }
}

impl clarix_editing_core::MaterializationPort for PdfTextMaterializer {
    fn materialize(
        &self,
        snapshot: &DocumentModel,
        target: &Path,
    ) -> Result<clarix_editing_core::MaterializationReport, clarix_editing_core::SaveError> {
        self.materialize_snapshot(snapshot, target)
            .map(|report| clarix_editing_core::MaterializationReport {
                output_sha256: report.output_sha256,
                bytes_written: report.bytes_written,
                warnings: report.warnings,
            })
            .map_err(|error| {
                clarix_editing_core::SaveError::new(
                    clarix_editing_core::SaveStage::MaterializeTemp,
                    error.code(),
                    error.to_string(),
                )
            })
    }
}

fn qualify_text(
    object: &DocumentObject,
    text: &clarix_editing_core::TextBlock,
) -> Result<(), PdfAdapterError> {
    let binding = object.source_binding().ok_or_else(|| {
        PdfAdapterError::UnsupportedMaterialization("text has no source binding".into())
    })?;
    let font = text.font().ok_or_else(|| {
        PdfAdapterError::UnsupportedMaterialization("text has no exact font reference".into())
    })?;
    if object.capability() != EditCapability::Editable
        || binding.confidence < 1.0
        || !font.is_valid()
        || !font.embeddable
    {
        return Err(PdfAdapterError::UnsupportedMaterialization(
            "text is not fully qualified for deterministic native replacement".into(),
        ));
    }
    if text.source_glyphs.is_empty()
        || text.text.chars().any(|character| {
            !text
                .source_glyphs
                .iter()
                .any(|glyph| glyph.character_code == character as u32)
        })
    {
        return Err(PdfAdapterError::UnsupportedMaterialization(
            "replacement contains a glyph that is not encodable by the source font".into(),
        ));
    }
    Ok(())
}

fn replace_text_occurrence(
    content: &mut Content<Vec<lopdf::content::Operation>>,
    occurrence: usize,
    replacement: &[u8],
) -> Result<(), PdfAdapterError> {
    let mut index = 0_usize;
    for operation in &mut content.operations {
        if !matches!(operation.operator.as_str(), "Tj" | "TJ" | "'" | "\"") {
            continue;
        }
        if index != occurrence {
            index += 1;
            continue;
        }
        match operation.operator.as_str() {
            "Tj" | "'" | "\"" => {
                let operand = operation.operands.last_mut().ok_or_else(|| {
                    PdfAdapterError::UnsupportedMaterialization(
                        "text-showing operator has no string operand".into(),
                    )
                })?;
                *operand = Object::String(replacement.to_vec(), StringFormat::Literal);
            }
            "TJ" => {
                let operand = operation.operands.first_mut().ok_or_else(|| {
                    PdfAdapterError::UnsupportedMaterialization(
                        "TJ operator has no array operand".into(),
                    )
                })?;
                *operand = Object::Array(vec![Object::String(
                    replacement.to_vec(),
                    StringFormat::Literal,
                )]);
            }
            _ => unreachable!(),
        }
        return Ok(());
    }
    Err(PdfAdapterError::UnsupportedMaterialization(
        "source text occurrence was not found".into(),
    ))
}

fn staging_path(target: &Path) -> PathBuf {
    let name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("document.pdf");
    target.with_file_name(format!(".{name}.clarix-materializing"))
}
