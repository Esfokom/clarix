use std::path::PathBuf;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};

use clarix_editing_core::DocumentObject;
use clarix_pdf_adapter::{
    CleanPatchBackend, CleanPatchCache, CleanPatchRenderRequest, CleanPatchRenderer, PdfImporter,
    PdfOxideImporter, SourceRef,
};

fn fixture() -> SourceRef {
    SourceRef::from_path(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test_fixtures/editing_corpus/generated/standard-latin.pdf"),
    )
    .unwrap()
}

fn request(dpi: u32) -> CleanPatchRenderRequest {
    let source = fixture();
    let page = PdfOxideImporter.inspect_page(&source, 1).unwrap();
    let object = &page.page.objects[0];
    let DocumentObject::Text(_) = object else {
        panic!("fixture must contain text")
    };
    let bounds = object.bounds();
    CleanPatchRenderRequest {
        source,
        page_number: 1,
        source_key: object.source_binding().unwrap().source_key.clone(),
        bounds,
        dpi,
    }
}

#[test]
fn clean_patch_omits_only_the_bound_source_text() {
    let result = CleanPatchRenderer.render(request(144)).unwrap();

    assert!(result.bleed_points >= 1.0);
    assert_eq!(
        result.rgba_bytes.len(),
        result.width as usize * result.height as usize * 4
    );
    assert!(result
        .rgba_bytes
        .chunks_exact(4)
        .all(|pixel| pixel == [255, 255, 255, 255]));
}

struct CountingBackend(AtomicUsize);

impl CleanPatchBackend for CountingBackend {
    fn render(
        &self,
        request: CleanPatchRenderRequest,
    ) -> Result<clarix_pdf_adapter::CleanPatch, clarix_pdf_adapter::PdfAdapterError> {
        self.0.fetch_add(1, Ordering::AcqRel);
        Ok(clarix_pdf_adapter::CleanPatch::solid_for_test(
            request, 8, 8,
        ))
    }
}

#[test]
fn second_request_hits_cache_and_budget_evicts_coldest_scale() {
    let backend = Arc::new(CountingBackend(AtomicUsize::new(0)));
    let cache = CleanPatchCache::new(backend.clone(), 300);

    let first = cache.get_or_render(request(72)).unwrap();
    let repeated = cache.get_or_render(request(72)).unwrap();
    assert!(Arc::ptr_eq(&first, &repeated));
    assert_eq!(backend.0.load(Ordering::Acquire), 1);

    cache.get_or_render(request(144)).unwrap();
    assert!(!cache.contains(&first.key));
}

#[test]
fn ambiguous_locator_is_rejected_without_rendering() {
    let mut request = request(144);
    request.source_key = "ambiguous".into();

    let error = CleanPatchRenderer.render(request).unwrap_err();

    assert_eq!(error.code(), "unsafe_clean_patch");
}
