use std::path::{Path, PathBuf};

use clarix_editing_core::{AtomicReplaceRequest, AtomicReplacementPort, SaveError, SaveStage};

#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsAtomicReplacer;

impl AtomicReplacementPort for WindowsAtomicReplacer {
    fn replace(&self, request: AtomicReplaceRequest) -> Result<(), SaveError> {
        ensure_same_directory(&request.working, &request.target)?;
        flush(&request.working)?;
        if request.replace_existing {
            if !request.target.exists() {
                return Err(SaveError::new(
                    SaveStage::ReplaceOrMove,
                    "source_unavailable",
                    "the replacement target no longer exists",
                ));
            }
            replace_existing(&request)
        } else {
            if request.target.exists() {
                return Err(SaveError::new(
                    SaveStage::ReplaceOrMove,
                    "target_exists",
                    "Save As refuses to overwrite an existing destination",
                ));
            }
            std::fs::rename(&request.working, &request.target)
                .map_err(|error| map_io_error(error, request.target))
        }
    }
}

fn ensure_same_directory(working: &Path, target: &Path) -> Result<(), SaveError> {
    let working_parent = working.parent().unwrap_or_else(|| Path::new("."));
    let target_parent = target.parent().unwrap_or_else(|| Path::new("."));
    let working_parent = std::fs::canonicalize(working_parent)
        .map_err(|error| map_io_error(error, working.to_path_buf()))?;
    let target_parent = std::fs::canonicalize(target_parent)
        .map_err(|error| map_io_error(error, target.to_path_buf()))?;
    if working_parent != target_parent {
        return Err(SaveError::new(
            SaveStage::ReplaceOrMove,
            "non_atomic_target",
            "working and target files are not sibling paths on the same volume",
        ));
    }
    Ok(())
}

fn flush(path: &Path) -> Result<(), SaveError> {
    std::fs::OpenOptions::new()
        .write(true)
        .open(path)
        .and_then(|file| file.sync_all())
        .map_err(|error| map_io_error(error, path.to_path_buf()))
}

#[cfg(windows)]
fn replace_existing(request: &AtomicReplaceRequest) -> Result<(), SaveError> {
    use std::os::windows::ffi::OsStrExt;

    #[link(name = "Kernel32")]
    extern "system" {
        fn ReplaceFileW(
            replaced_file_name: *const u16,
            replacement_file_name: *const u16,
            backup_file_name: *const u16,
            replace_flags: u32,
            exclude: *mut core::ffi::c_void,
            reserved: *mut core::ffi::c_void,
        ) -> i32;
        fn GetLastError() -> u32;
    }

    fn wide(path: &Path) -> Vec<u16> {
        path.as_os_str().encode_wide().chain(Some(0)).collect()
    }

    let target = wide(&request.target);
    let working = wide(&request.working);
    let backup = request.backup.as_deref().map(wide);
    let backup_pointer = backup
        .as_ref()
        .map_or(std::ptr::null(), |path| path.as_ptr());
    // SAFETY: all strings are NUL-terminated and live for the duration of the call.
    let replaced = unsafe {
        ReplaceFileW(
            target.as_ptr(),
            working.as_ptr(),
            backup_pointer,
            0x0000_0001,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    };
    if replaced == 0 {
        // SAFETY: GetLastError has no preconditions and is read immediately after failure.
        let raw = unsafe { GetLastError() } as i32;
        return Err(map_windows_replace_error(raw, request.target.clone()));
    }
    Ok(())
}

#[cfg(not(windows))]
fn replace_existing(_: &AtomicReplaceRequest) -> Result<(), SaveError> {
    Err(SaveError::new(
        SaveStage::ReplaceOrMove,
        "unsupported_platform",
        "ReplaceFileW is available only on Windows",
    ))
}

fn map_io_error(error: std::io::Error, path: PathBuf) -> SaveError {
    match error.raw_os_error() {
        Some(raw) => map_windows_replace_error(raw, path),
        None => SaveError::new(
            SaveStage::ReplaceOrMove,
            "io_error",
            format!("{}: {error}", path.display()),
        ),
    }
}

pub fn map_windows_replace_error(raw_os_error: i32, path: PathBuf) -> SaveError {
    let code = match raw_os_error {
        32 | 33 => "source_locked",
        5 => "permission_denied",
        112 => "disk_full",
        17 => "non_atomic_target",
        1460 => "replace_timeout",
        _ => "replace_failed",
    };
    SaveError::new(
        SaveStage::ReplaceOrMove,
        code,
        format!(
            "Windows replacement failed for {} (OS error {raw_os_error})",
            path.display()
        ),
    )
}
