use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use clarix_editing_core::{DocumentModel, DocumentObject, EditCapability, FontRef, FontSource};
use lopdf::content::{Content, Operation};
use lopdf::{dictionary, Dictionary, Document, Object, ObjectId, Stream, StringFormat};
use ttf_parser::{Face, Permissions};

use crate::installed_font::win_ansi_byte;
use crate::{
    contract::sha256_hex, DocumentSnapshot, PdfAdapterError, PdfMaterializer, SaveReport, SourceRef,
};

#[derive(Debug, Clone)]
struct TextReplacement {
    occurrence: usize,
    text: String,
    fallback: Option<FontRef>,
    font_size: f64,
}

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
        let mut replacements: BTreeMap<u32, Vec<TextReplacement>> = BTreeMap::new();
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
                    .push(TextReplacement {
                        occurrence,
                        text: text.text.clone(),
                        fallback: text
                            .font()
                            .filter(|font| font.source == FontSource::ApprovedFallback)
                            .cloned(),
                        font_size: text.runs.first().map_or(12.0, |run| run.style.font_size),
                    });
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
            for (serial, replacement) in page_replacements.into_iter().enumerate() {
                let (bytes, fallback_resource) = if let Some(font) = &replacement.fallback {
                    let (bytes, resource) =
                        embed_fallback_font(&mut output, page_id, font, &replacement.text, serial)?;
                    (bytes, Some(resource))
                } else {
                    (replacement.text.as_bytes().to_vec(), None)
                };
                replace_text_occurrence(
                    &mut content,
                    replacement.occurrence,
                    &bytes,
                    fallback_resource.as_deref(),
                    replacement.font_size,
                )?;
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
    fallback_resource: Option<&[u8]>,
    font_size: f64,
) -> Result<(), PdfAdapterError> {
    let mut index = 0_usize;
    let mut operation_index = None;
    for (position, operation) in content.operations.iter().enumerate() {
        if !matches!(operation.operator.as_str(), "Tj" | "TJ" | "'" | "\"") {
            continue;
        }
        if index != occurrence {
            index += 1;
            continue;
        }
        operation_index = Some(position);
        break;
    }
    let position = operation_index.ok_or_else(|| {
        PdfAdapterError::UnsupportedMaterialization("source text occurrence was not found".into())
    })?;
    match content.operations[position].operator.as_str() {
        "Tj" | "'" | "\"" => {
            let operand = content.operations[position]
                .operands
                .last_mut()
                .ok_or_else(|| {
                    PdfAdapterError::UnsupportedMaterialization(
                        "text-showing operator has no string operand".into(),
                    )
                })?;
            *operand = Object::String(replacement.to_vec(), StringFormat::Literal);
        }
        "TJ" => {
            let operand = content.operations[position]
                .operands
                .first_mut()
                .ok_or_else(|| {
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
    if let Some(resource) = fallback_resource {
        let restore_font = content.operations[..position]
            .iter()
            .rev()
            .find(|operation| operation.operator == "Tf")
            .cloned()
            .ok_or_else(|| {
                PdfAdapterError::UnsupportedMaterialization(
                    "fallback text has no preceding source font selection".into(),
                )
            })?;
        content.operations.insert(
            position,
            Operation::new(
                "Tf",
                vec![
                    Object::Name(resource.to_vec()),
                    Object::Real(font_size as f32),
                ],
            ),
        );
        content.operations.insert(position + 2, restore_font);
    }
    Ok(())
}

fn embed_fallback_font(
    document: &mut Document,
    page_id: ObjectId,
    font: &FontRef,
    text: &str,
    serial: usize,
) -> Result<(Vec<u8>, Vec<u8>), PdfAdapterError> {
    let asset = font.asset_id.as_ref().ok_or_else(|| {
        PdfAdapterError::UnsupportedMaterialization("approved fallback has no font asset".into())
    })?;
    let font_bytes = std::fs::read(asset)
        .map_err(|error| PdfAdapterError::Io(format!("fallback font asset: {error}")))?;
    if sha256_hex(&font_bytes) != font.bytes_sha256.to_ascii_lowercase() {
        return Err(PdfAdapterError::UnsupportedMaterialization(
            "approved fallback font fingerprint changed".into(),
        ));
    }
    let face = Face::parse(&font_bytes, 0).map_err(|error| {
        PdfAdapterError::UnsupportedMaterialization(format!("invalid fallback font: {error}"))
    })?;
    if face.tables().glyf.is_none()
        || face.is_variable()
        || !face.is_outline_embedding_allowed()
        || !matches!(
            face.permissions(),
            Some(Permissions::Installable | Permissions::Editable)
        )
    {
        return Err(PdfAdapterError::UnsupportedMaterialization(
            "approved fallback font is not an embeddable static TrueType font".into(),
        ));
    }
    let encoded = text
        .chars()
        .map(|character| {
            face.glyph_index(character)?;
            win_ansi_byte(character)
        })
        .collect::<Option<Vec<_>>>()
        .ok_or_else(|| {
            PdfAdapterError::UnsupportedMaterialization(
                "approved fallback text is not exactly WinAnsi encodable".into(),
            )
        })?;
    let units = i64::from(face.units_per_em());
    let scale = |value: i16| i64::from(value) * 1000 / units;
    let bbox = face.global_bounding_box();
    let widths = (32_u8..=255)
        .map(|byte| {
            let width = win_ansi_character(byte)
                .and_then(|character| face.glyph_index(character))
                .and_then(|glyph| face.glyph_hor_advance(glyph))
                .map_or(0, |advance| i64::from(advance) * 1000 / units);
            Object::Integer(width)
        })
        .collect::<Vec<_>>();
    let flags = 32_i64 | if face.is_italic() { 64 } else { 0 };
    let italic_angle = face.italic_angle();
    let ascent = scale(face.ascender());
    let descent = scale(face.descender());
    let cap_height = scale(face.capital_height().unwrap_or(face.ascender()));
    let font_file_id = document.add_object(Stream::new(
        dictionary! { "Length1" => font_bytes.len() as i64 },
        font_bytes,
    ));
    let base_font = font.postscript_name.as_bytes().to_vec();
    let descriptor_id = document.add_object(dictionary! {
        "Type" => "FontDescriptor",
        "FontName" => Object::Name(base_font.clone()),
        "Flags" => flags,
        "FontBBox" => vec![scale(bbox.x_min).into(), scale(bbox.y_min).into(), scale(bbox.x_max).into(), scale(bbox.y_max).into()],
        "ItalicAngle" => Object::Real(italic_angle),
        "Ascent" => ascent,
        "Descent" => descent,
        "CapHeight" => cap_height,
        "StemV" => 80,
        "FontFile2" => font_file_id,
    });
    let to_unicode_id = document.add_object(Stream::new(
        Dictionary::new(),
        to_unicode_cmap(text, &encoded).into_bytes(),
    ));
    let font_id = document.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "TrueType",
        "BaseFont" => Object::Name(base_font),
        "FirstChar" => 32,
        "LastChar" => 255,
        "Widths" => Object::Array(widths),
        "FontDescriptor" => descriptor_id,
        "Encoding" => "WinAnsiEncoding",
        "ToUnicode" => to_unicode_id,
    });
    let resource_name = format!("ClarixFallback{}", serial + 1).into_bytes();
    install_page_font(document, page_id, &resource_name, font_id)?;
    Ok((encoded, resource_name))
}

fn install_page_font(
    document: &mut Document,
    page_id: ObjectId,
    resource_name: &[u8],
    font_id: ObjectId,
) -> Result<(), PdfAdapterError> {
    let (direct, inherited_ids) = document
        .get_page_resources(page_id)
        .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
    let mut resources = if let Some(resources) = direct {
        resources.clone()
    } else if let Some(resource_id) = inherited_ids.first() {
        document
            .get_dictionary(*resource_id)
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?
            .clone()
    } else {
        Dictionary::new()
    };
    let mut fonts = match resources.get(b"Font").cloned() {
        Ok(Object::Dictionary(fonts)) => fonts,
        Ok(Object::Reference(id)) => document
            .get_dictionary(id)
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?
            .clone(),
        _ => Dictionary::new(),
    };
    fonts.set(resource_name.to_vec(), Object::Reference(font_id));
    resources.set("Font", Object::Dictionary(fonts));
    document
        .get_dictionary_mut(page_id)
        .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?
        .set("Resources", Object::Dictionary(resources));
    Ok(())
}

fn to_unicode_cmap(text: &str, encoded: &[u8]) -> String {
    let mut mappings = BTreeMap::new();
    for (character, byte) in text.chars().zip(encoded.iter().copied()) {
        mappings.entry(byte).or_insert(character as u32);
    }
    let entries = mappings
        .into_iter()
        .map(|(byte, character)| format!("<{byte:02X}> <{character:04X}>"))
        .collect::<Vec<_>>()
        .join("\n");
    format!(
        "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /ClarixUnicode def\n/CMapType 2 def\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n{} beginbfchar\n{}\nendbfchar\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n",
        entries.lines().count(),
        entries
    )
}

fn win_ansi_character(byte: u8) -> Option<char> {
    match byte {
        0x20..=0x7e | 0xa0..=0xff => char::from_u32(u32::from(byte)),
        0x80 => Some('€'),
        0x82 => Some('‚'),
        0x83 => Some('ƒ'),
        0x84 => Some('„'),
        0x85 => Some('…'),
        0x86 => Some('†'),
        0x87 => Some('‡'),
        0x88 => Some('ˆ'),
        0x89 => Some('‰'),
        0x8a => Some('Š'),
        0x8b => Some('‹'),
        0x8c => Some('Œ'),
        0x8e => Some('Ž'),
        0x91 => Some('‘'),
        0x92 => Some('’'),
        0x93 => Some('“'),
        0x94 => Some('”'),
        0x95 => Some('•'),
        0x96 => Some('–'),
        0x97 => Some('—'),
        0x98 => Some('˜'),
        0x99 => Some('™'),
        0x9a => Some('š'),
        0x9b => Some('›'),
        0x9c => Some('œ'),
        0x9e => Some('ž'),
        0x9f => Some('Ÿ'),
        _ => None,
    }
}

fn staging_path(target: &Path) -> PathBuf {
    let name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("document.pdf");
    target.with_file_name(format!(".{name}.clarix-materializing"))
}
