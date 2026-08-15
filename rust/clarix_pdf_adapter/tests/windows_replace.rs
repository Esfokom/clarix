use std::path::PathBuf;

use clarix_editing_core::{AtomicReplaceRequest, AtomicReplacementPort};
use clarix_pdf_adapter::{map_windows_replace_error, WindowsAtomicReplacer};

#[test]
fn replace_preserves_original_as_rolling_backup() {
    let directory = tempfile::tempdir().unwrap();
    let target = directory.path().join("document.pdf");
    let working = directory.path().join(".document.working.pdf");
    let backup = directory.path().join(".document.pdf.clarix-backup.pdf");
    std::fs::write(&target, b"original").unwrap();
    std::fs::write(&working, b"replacement").unwrap();

    WindowsAtomicReplacer
        .replace(AtomicReplaceRequest {
            working,
            target: target.clone(),
            backup: Some(backup.clone()),
            replace_existing: true,
        })
        .unwrap();

    assert_eq!(std::fs::read(target).unwrap(), b"replacement");
    assert_eq!(std::fs::read(backup).unwrap(), b"original");
}

#[test]
fn save_as_atomically_installs_without_touching_original() {
    let directory = tempfile::tempdir().unwrap();
    let original = directory.path().join("original.pdf");
    let working = directory.path().join(".export.working.pdf");
    let target = directory.path().join("export.pdf");
    std::fs::write(&original, b"original").unwrap();
    std::fs::write(&working, b"export").unwrap();

    WindowsAtomicReplacer
        .replace(AtomicReplaceRequest {
            working,
            target: target.clone(),
            backup: None,
            replace_existing: false,
        })
        .unwrap();

    assert_eq!(std::fs::read(original).unwrap(), b"original");
    assert_eq!(std::fs::read(target).unwrap(), b"export");
}

#[test]
fn windows_failures_have_stable_save_codes() {
    for (raw, expected) in [
        (32, "source_locked"),
        (5, "permission_denied"),
        (112, "disk_full"),
        (17, "non_atomic_target"),
        (1460, "replace_timeout"),
    ] {
        assert_eq!(
            map_windows_replace_error(raw, PathBuf::from("document.pdf")).code,
            expected
        );
    }
}
