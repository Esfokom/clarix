use clarix_editing_core::{
    DocumentObject, ObjectId, PageId, PageNode, PdfBox, SourceBinding, TextBlock,
};
use pdf_oxide::PdfDocument;
use sha2::{Digest, Sha256};

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
        let mut objects = Vec::new();

        for (occurrence, span) in spans
            .into_iter()
            .filter(|span| !span.text.is_empty())
            .enumerate()
        {
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
            let binding = SourceBinding {
                adapter_id: ADAPTER_ID.into(),
                source_revision: source.fingerprint().into(),
                source_key: object_key,
                confidence: 1.0,
            };
            objects.push(DocumentObject::Text(
                TextBlock::plain(object_id, page_id, span.text, bounds)
                    .with_source_binding(binding),
            ));
        }

        Ok(PageImport {
            page: PageNode::new(page_id, page_number, width, height, objects),
            report: CapabilityReport::read_only(self.adapter_id()),
            warnings: vec![
                "Phase 0 imports text and geometry only; font, image, vector, and form fidelity are unqualified."
                    .into(),
            ],
        })
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
