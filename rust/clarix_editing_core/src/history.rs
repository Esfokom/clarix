use serde::{Deserialize, Serialize};

use crate::DocumentObject;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum InverseOperation {
    ReplaceObjects(Vec<DocumentObject>),
    RemoveObjects(Vec<crate::ObjectId>),
    Checkpoint,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TypingGroup {
    pub id: String,
    pub composition_id: Option<String>,
    pub caret_before: u32,
    pub caret_after: u32,
    pub composition_boundary: bool,
}

#[derive(Debug, Clone)]
pub(crate) enum HistoryEntry {
    Object {
        before: Box<DocumentObject>,
        after: Box<DocumentObject>,
        typing: Option<TypingGroup>,
    },
    Objects {
        before: Vec<DocumentObject>,
        after: Vec<DocumentObject>,
    },
    Inserted {
        object: Box<DocumentObject>,
    },
    Checkpoint {
        label: String,
    },
}

pub(crate) fn can_coalesce(
    previous: &HistoryEntry,
    next_before: &DocumentObject,
    next_typing: Option<&TypingGroup>,
) -> bool {
    let Some(next_typing) = next_typing else {
        return false;
    };
    let HistoryEntry::Object {
        after,
        typing: Some(previous_typing),
        ..
    } = previous
    else {
        return false;
    };
    previous_typing.id == next_typing.id
        && previous_typing.composition_id == next_typing.composition_id
        && !previous_typing.composition_boundary
        && !next_typing.composition_boundary
        && previous_typing.caret_after == next_typing.caret_before
        && after.id() == next_before.id()
}
