use serde::{Deserialize, Serialize};

use crate::{
    DocumentModel, DocumentObject, DocumentRevision, EditCapability, ObjectId, ObjectKind, PageId,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityIssue {
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub kind: ObjectKind,
    pub capability: EditCapability,
    pub code: String,
    pub message: String,
    pub supported_operations: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityReport {
    pub revision: DocumentRevision,
    pub editable_count: u32,
    pub overlay_only_count: u32,
    pub read_only_count: u32,
    pub issues: Vec<CompatibilityIssue>,
}

pub struct CompatibilityReporter;

impl CompatibilityReporter {
    pub fn for_document(document: &DocumentModel) -> CompatibilityReport {
        let mut report = CompatibilityReport {
            revision: document.revision,
            editable_count: 0,
            overlay_only_count: 0,
            read_only_count: 0,
            issues: Vec::new(),
        };
        for page in &document.pages {
            for object in &page.objects {
                match object.capability() {
                    EditCapability::Editable => report.editable_count += 1,
                    EditCapability::OverlayOnly => {
                        report.overlay_only_count += 1;
                        report.issues.push(issue(object));
                    }
                    EditCapability::ReadOnly => {
                        report.read_only_count += 1;
                        report.issues.push(issue(object));
                    }
                }
            }
        }
        report
    }
}

fn issue(object: &DocumentObject) -> CompatibilityIssue {
    let (code, message) = match object {
        DocumentObject::Text(text) => text
            .capability_reason()
            .map(|reason| (reason.code.clone(), reason.message.clone()))
            .unwrap_or_else(|| {
                (
                    "unsupported_text_operation".into(),
                    "This text object is not editable in the current compatibility mode.".into(),
                )
            }),
        _ => (
            "unsupported_object_kind".into(),
            "This object kind is not editable in the current phase.".into(),
        ),
    };
    CompatibilityIssue {
        object_id: object.id(),
        page_id: object.page_id(),
        kind: object.kind(),
        capability: object.capability(),
        code,
        message,
        supported_operations: match object.capability() {
            EditCapability::Editable => vec!["edit", "format", "transform", "search"],
            EditCapability::OverlayOnly => vec!["select", "search"],
            EditCapability::ReadOnly => vec!["search"],
        }
        .into_iter()
        .map(str::to_owned)
        .collect(),
    }
}
