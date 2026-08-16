use clarix_editing_core::{
    AffineTransform, CapabilityReason, DocumentObject, EditCapability, FontRef, FontSource,
    ObjectId, PageId, PageImportRequest, PageImportSource, PageNode, PdfBox, SourceBinding,
    SourceGlyph, TextBlock, TextCharacterBox, TextLayoutRecipe, TextStyle, Utf16Range,
    WritingDirection,
};
use pdf_oxide::PdfDocument;
use sha2::{Digest, Sha256};
use unicode_segmentation::UnicodeSegmentation;

use crate::{
    contract::sha256_hex, CapabilityReport, DocumentImport, PageImport, PdfAdapterError,
    PdfImporter, SourceRef,
};

const ADAPTER_ID: &str = "pdf-oxide/0.3-read-only";

#[derive(Debug, Default, Clone, Copy)]
pub struct PdfOxideImporter;

impl PdfImporter for PdfOxideImporter {
    fn adapter_id(&self) -> &'static str {
        ADAPTER_ID
    }

    fn inspect_document(&self, source: &SourceRef) -> Result<DocumentImport, PdfAdapterError> {
        verify_source(source)?;
        let document = open_document(source)?;
        let page_count = document
            .page_count()
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        Ok(DocumentImport {
            source_fingerprint: source.fingerprint().to_owned(),
            page_count: u32::try_from(page_count)
                .map_err(|_| PdfAdapterError::Adapter("page count exceeds u32".into()))?,
            report: CapabilityReport::read_only(self.adapter_id()),
        })
    }

    fn inspect_page(
        &self,
        source: &SourceRef,
        page_number: u32,
    ) -> Result<PageImport, PdfAdapterError> {
        verify_source(source)?;
        let document = open_document(source)?;
        let page_count = document
            .page_count()
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        let page_count_u32 = u32::try_from(page_count)
            .map_err(|_| PdfAdapterError::Adapter("page count exceeds u32".into()))?;
        if page_number == 0 || page_number > page_count_u32 {
            return Err(PdfAdapterError::PageOutOfRange {
                requested: page_number,
                page_count: page_count_u32,
            });
        }
        let page_index = (page_number - 1) as usize;
        let (left, bottom, right, top) = document
            .get_page_media_box(page_index)
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        let width = f64::from(right - left);
        let height = f64::from(top - bottom);
        if !width.is_finite() || !height.is_finite() || width <= 0.0 || height <= 0.0 {
            return Err(PdfAdapterError::InvalidPdf(
                "page MediaBox has invalid dimensions".into(),
            ));
        }

        let page_key = format!("{}/page/{page_number}", source.fingerprint());
        let page_id = PageId::from_source_key(&page_key);
        let spans = document
            .extract_spans(page_index)
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
        let simple_source = simple_text_stream(source, page_number, spans.len());
        let mut objects = Vec::new();

        for (occurrence, span) in spans
            .into_iter()
            .filter(|span| !span.text.is_empty())
            .enumerate()
        {
            let character_boxes = character_boxes(&span)?;
            let bounds = PdfBox::new(
                f64::from(span.bbox.x),
                f64::from(span.bbox.y),
                f64::from(span.bbox.x + span.bbox.width),
                f64::from(span.bbox.y + span.bbox.height),
            )
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
            let text_fingerprint = hex_digest(span.text.as_bytes());
            let object_key = format!(
                "{page_key}/text/{}/{}/{}/{}/{occurrence}/{text_fingerprint}",
                normalized(span.bbox.x),
                normalized(span.bbox.y),
                normalized(span.bbox.width),
                normalized(span.bbox.height),
            );
            let object_id = ObjectId::from_source_key(&object_key);
            let qualified = simple_source && qualifies_base14_ascii(&span);
            let binding = SourceBinding {
                adapter_id: ADAPTER_ID.into(),
                source_revision: source.fingerprint().into(),
                source_key: object_key,
                confidence: if qualified { 1.0 } else { 0.5 },
            };
            let angle = f64::from(span.rotation_degrees).to_radians();
            let transform = AffineTransform::new(
                angle.cos(),
                angle.sin(),
                -angle.sin(),
                angle.cos(),
                0.0,
                0.0,
            )
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?;
            let font_name = span.font_name.clone();
            let mut block = TextBlock::plain(object_id, page_id, span.text, bounds)
                .with_source_binding(binding)
                .with_transform(transform)
                .with_character_boxes(character_boxes)
                .with_capability(if qualified { EditCapability::Editable } else { EditCapability::ReadOnly }, if qualified { None } else { Some(CapabilityReason {
                    code: "font_encoding_incomplete".into(),
                    message: "the font lacks a verified reversible glyph encoding and exact source operator locator"
                        .into(),
                }) });
            block.runs[0].style = TextStyle {
                font_family: Some(span.font_name),
                font_size: f64::from(span.font_size),
                font_weight: span.font_weight.to_pdf_value(),
                italic: span.is_italic,
                color_rgba: [
                    color_channel(span.color.r),
                    color_channel(span.color.g),
                    color_channel(span.color.b),
                    255,
                ],
            };
            block.layout = TextLayoutRecipe {
                baseline: bounds.bottom + f64::from(span.font_size) * f64::from(span.text_rise),
                line_height: f64::from(span.bbox.height.max(span.font_size)),
                character_spacing: f64::from(span.char_spacing),
                horizontal_scale: f64::from(span.horizontal_scaling / 100.0),
                direction: if span.wmode == 1 {
                    WritingDirection::TopToBottom
                } else if span.rtl_draw_logical {
                    WritingDirection::RightToLeft
                } else {
                    WritingDirection::LeftToRight
                },
                ..TextLayoutRecipe::default()
            };
            if qualified {
                let layout = block.layout.clone();
                block = block.with_text_contract(
                    FontRef {
                        postscript_name: font_name.clone(),
                        bytes_sha256: hex_digest(font_name.as_bytes()),
                        asset_id: Some(format!("pdf-base14:{font_name}")),
                        source: FontSource::ApprovedFallback,
                        embeddable: true,
                    },
                    layout,
                    win_ansi_ascii_glyphs(),
                );
            }
            objects.push(DocumentObject::text(block));
        }

        Ok(PageImport {
            page: PageNode::new(page_id, page_number, width, height, objects),
            report: CapabilityReport::read_only(self.adapter_id()),
            warnings: vec![
                "Text style and layout are preserved where exposed, but editing remains disabled until font encoding and source operators are reversible."
                    .into(),
            ],
        })
    }
}

fn character_boxes(
    span: &pdf_oxide::layout::TextSpan,
) -> Result<Vec<TextCharacterBox>, PdfAdapterError> {
    let characters = span.to_chars();
    let mut character_index = 0;
    let mut utf16_start = 0_u32;
    let mut output = Vec::new();
    for grapheme in span.text.graphemes(true) {
        let character_count = grapheme.chars().count();
        let end = character_index + character_count;
        let glyphs = characters.get(character_index..end).ok_or_else(|| {
            PdfAdapterError::Adapter("character geometry does not match extracted text".into())
        })?;
        let left = glyphs
            .iter()
            .map(|glyph| f64::from(glyph.bbox.x))
            .fold(f64::INFINITY, f64::min);
        let bottom = glyphs
            .iter()
            .map(|glyph| f64::from(glyph.bbox.y))
            .fold(f64::INFINITY, f64::min);
        let right = glyphs
            .iter()
            .map(|glyph| f64::from(glyph.bbox.x + glyph.bbox.width))
            .fold(f64::NEG_INFINITY, f64::max);
        let top = glyphs
            .iter()
            .map(|glyph| f64::from(glyph.bbox.y + glyph.bbox.height))
            .fold(f64::NEG_INFINITY, f64::max);
        let utf16_end = utf16_start
            .checked_add(grapheme.encode_utf16().count() as u32)
            .ok_or_else(|| PdfAdapterError::Adapter("text geometry exceeds UTF-16 range".into()))?;
        output.push(TextCharacterBox {
            range: Utf16Range::new(utf16_start, utf16_end)
                .map_err(|error| PdfAdapterError::Adapter(error.to_string()))?,
            bounds: PdfBox::new(left, bottom, right, top)
                .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?,
        });
        utf16_start = utf16_end;
        character_index = end;
    }
    if character_index != characters.len() {
        return Err(PdfAdapterError::Adapter(
            "character geometry has trailing glyphs".into(),
        ));
    }
    Ok(output)
}

impl PageImportSource for PdfOxideImporter {
    fn import_page(
        &self,
        request: PageImportRequest,
    ) -> Result<clarix_editing_core::ImportedPage, String> {
        let source = SourceRef::new(request.source.fingerprint, request.source.path);
        self.inspect_page(&source, request.page_number)
            .map(|imported| clarix_editing_core::ImportedPage {
                page: imported.page,
                warnings: imported.warnings,
            })
            .map_err(|error| format!("{}: {error}", error.code()))
    }
}

fn open_document(source: &SourceRef) -> Result<PdfDocument, PdfAdapterError> {
    PdfDocument::open(source.path()).map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))
}

fn verify_source(source: &SourceRef) -> Result<(), PdfAdapterError> {
    let bytes =
        std::fs::read(source.path()).map_err(|error| PdfAdapterError::Io(error.to_string()))?;
    if sha256_hex(&bytes) != source.fingerprint() {
        return Err(PdfAdapterError::FingerprintMismatch);
    }
    Ok(())
}

fn normalized(value: f32) -> i64 {
    (f64::from(value) * 1000.0).round() as i64
}

fn hex_digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn color_channel(value: f32) -> u8 {
    (value.clamp(0.0, 1.0) * 255.0).round() as u8
}

fn qualifies_base14_ascii(span: &pdf_oxide::layout::TextSpan) -> bool {
    const BASE14: [&str; 12] = [
        "Courier",
        "Courier-Bold",
        "Courier-Oblique",
        "Courier-BoldOblique",
        "Helvetica",
        "Helvetica-Bold",
        "Helvetica-Oblique",
        "Helvetica-BoldOblique",
        "Times-Roman",
        "Times-Bold",
        "Times-Italic",
        "Times-BoldItalic",
    ];
    BASE14.contains(&span.font_name.as_str()) && span.text.is_ascii() && span.wmode == 0
}

fn simple_text_stream(source: &SourceRef, page_number: u32, expected_spans: usize) -> bool {
    let Ok(document) = lopdf::Document::load(source.path()) else {
        return false;
    };
    let pages = document.get_pages();
    let Some(page_id) = pages.get(&page_number).copied() else {
        return false;
    };
    if document.get_page_contents(page_id).len() != 1 {
        return false;
    }
    let Ok(bytes) = document.get_page_content(page_id) else {
        return false;
    };
    let Ok(content) = lopdf::content::Content::decode(&bytes) else {
        return false;
    };
    let text_operations = content
        .operations
        .iter()
        .filter(|operation| matches!(operation.operator.as_str(), "Tj" | "TJ" | "'" | "\""))
        .count();
    text_operations == expected_spans
        && !content
            .operations
            .iter()
            .any(|operation| operation.operator == "Do")
}

fn win_ansi_ascii_glyphs() -> Vec<SourceGlyph> {
    (32_u32..=126)
        .map(|code| SourceGlyph {
            utf16_start: code - 32,
            utf16_end: code - 31,
            character_code: code,
            glyph_id: code,
        })
        .collect()
}
