use std::path::{Path, PathBuf};

use clarix_editing_core::DocumentId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectLocation {
    pub root: PathBuf,
    pub database: PathBuf,
    pub assets: PathBuf,
    pub previews: PathBuf,
    pub recovery: PathBuf,
}

impl ProjectLocation {
    pub fn under(local_app_data: &Path, document_id: DocumentId) -> Self {
        let root = local_app_data
            .join("Clarix")
            .join("Projects")
            .join(document_id.to_string());
        Self {
            database: root.join("project.sqlite"),
            assets: root.join("assets"),
            previews: root.join("previews"),
            recovery: root.join("recovery"),
            root,
        }
    }

    pub(crate) fn create_directories(&self) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.root)?;
        std::fs::create_dir_all(&self.assets)?;
        std::fs::create_dir_all(&self.previews)?;
        std::fs::create_dir_all(&self.recovery)
    }
}
