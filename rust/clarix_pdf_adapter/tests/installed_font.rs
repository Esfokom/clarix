use std::path::PathBuf;

use clarix_pdf_adapter::{InstalledFontCatalog, InstalledFontRequest};
use sha2::{Digest, Sha256};

#[test]
fn proposes_an_embeddable_true_type_face_with_exact_glyph_coverage() {
    let arial = PathBuf::from(r"C:\Windows\Fonts\arial.ttf");
    assert!(arial.exists(), "Windows Phase 1 requires Arial");
    let catalog = InstalledFontCatalog::from_roots([arial.parent().unwrap().to_owned()]);
    let proposal = catalog
        .propose(&InstalledFontRequest {
            preferred_family: "Arial".into(),
            weight: 400,
            italic: false,
            text: "Invoice €".into(),
        })
        .expect("Windows must expose an embeddable WinAnsi font");

    assert_eq!(proposal.family, "Arial");
    assert!(proposal.postscript_name.starts_with("Arial"));
    let bytes = std::fs::read(&proposal.path).unwrap();
    assert_eq!(proposal.bytes_sha256, format!("{:x}", Sha256::digest(bytes)));
}

#[test]
fn refuses_text_that_cannot_be_materialized_by_the_phase_one_encoding() {
    let catalog = InstalledFontCatalog::windows();
    assert!(catalog
        .propose(&InstalledFontRequest {
            preferred_family: "Arial".into(),
            weight: 400,
            italic: false,
            text: "emoji 😀".into(),
        })
        .is_none());
}
