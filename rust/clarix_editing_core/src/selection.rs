use serde::{Deserialize, Serialize};

use crate::{
    DocumentModel, DocumentObject, DocumentRevision, EditingError, ObjectId, TextRangeRef,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SelectionKind {
    TextRanges,
    Objects,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SelectionSet {
    pub revision: DocumentRevision,
    pub kind: SelectionKind,
    pub ranges: Vec<TextRangeRef>,
    pub object_ids: Vec<ObjectId>,
    pub primary_index: Option<u32>,
}

pub(crate) fn validate_selection(
    model: &DocumentModel,
    selection: SelectionSet,
) -> Result<SelectionSet, EditingError> {
    if selection.revision != model.revision {
        return Err(EditingError::RevisionConflict {
            expected: selection.revision,
            actual: model.revision,
        });
    }
    match selection.kind {
        SelectionKind::TextRanges => validate_text_selection(model, selection),
        SelectionKind::Objects => validate_object_selection(model, selection),
    }
}

fn validate_text_selection(
    model: &DocumentModel,
    mut selection: SelectionSet,
) -> Result<SelectionSet, EditingError> {
    if selection.ranges.is_empty() || !selection.object_ids.is_empty() {
        return Err(EditingError::InvalidCommand(
            "text selection must contain ranges and no object IDs".into(),
        ));
    }
    let mut ranges = selection
        .ranges
        .drain(..)
        .map(|range| validate_text_range(model, range))
        .collect::<Result<Vec<_>, _>>()?;
    ranges.sort_by_key(|range| {
        (
            range.page_number,
            range.object_id.to_string(),
            range.start_utf16,
            range.end_utf16,
        )
    });
    let mut merged = Vec::<TextRangeRef>::new();
    for range in ranges {
        if let Some(previous) = merged.last_mut() {
            if previous.object_id == range.object_id && range.start_utf16 <= previous.end_utf16 {
                previous.end_utf16 = previous.end_utf16.max(range.end_utf16);
                refresh_quote(model, previous)?;
                continue;
            }
        }
        merged.push(range);
    }
    selection.ranges = merged;
    selection.primary_index = selection.primary_index.map(|_| 0);
    Ok(selection)
}

fn validate_object_selection(
    model: &DocumentModel,
    mut selection: SelectionSet,
) -> Result<SelectionSet, EditingError> {
    if !selection.ranges.is_empty() || selection.object_ids.is_empty() {
        return Err(EditingError::InvalidCommand(
            "object selection must contain object IDs and no text ranges".into(),
        ));
    }
    for object_id in &selection.object_ids {
        if model.object(*object_id).is_none() {
            return Err(EditingError::ObjectNotFound(*object_id));
        }
    }
    selection.object_ids.sort_by_key(ToString::to_string);
    selection.object_ids.dedup();
    selection.primary_index = selection.primary_index.map(|_| 0);
    Ok(selection)
}

fn validate_text_range(
    model: &DocumentModel,
    mut range: TextRangeRef,
) -> Result<TextRangeRef, EditingError> {
    let object = model
        .object(range.object_id)
        .ok_or(EditingError::ObjectNotFound(range.object_id))?;
    if object.page_id() != range.page_id {
        return Err(EditingError::InvalidCommand(
            "selection range page does not match object page".into(),
        ));
    }
    let page = model
        .pages
        .iter()
        .find(|page| page.id == range.page_id)
        .ok_or_else(|| EditingError::InvalidCommand("selection page is unavailable".into()))?;
    if page.page_number != range.page_number {
        return Err(EditingError::InvalidCommand(
            "selection range page number does not match object page".into(),
        ));
    }
    let DocumentObject::Text(text) = object else {
        return Err(EditingError::WrongObjectKind(range.object_id));
    };
    let byte_range = crate::text::utf16_range_to_byte_range(
        &text.text,
        crate::Utf16Range::new(range.start_utf16, range.end_utf16)
            .map_err(|_| EditingError::InvalidTextBoundary)?,
    )
    .map_err(|_| EditingError::InvalidTextBoundary)?;
    if byte_range.is_empty() || text.text[byte_range.clone()] != range.quoted_text {
        return Err(EditingError::SelectionQuoteMismatch {
            object_id: range.object_id,
        });
    }
    range.quoted_text = text.text[byte_range].to_owned();
    Ok(range)
}

fn refresh_quote(model: &DocumentModel, range: &mut TextRangeRef) -> Result<(), EditingError> {
    let object = model
        .object(range.object_id)
        .ok_or(EditingError::ObjectNotFound(range.object_id))?;
    let DocumentObject::Text(text) = object else {
        return Err(EditingError::WrongObjectKind(range.object_id));
    };
    let byte_range = crate::text::utf16_range_to_byte_range(
        &text.text,
        crate::Utf16Range::new(range.start_utf16, range.end_utf16)
            .map_err(|_| EditingError::InvalidTextBoundary)?,
    )
    .map_err(|_| EditingError::InvalidTextBoundary)?;
    range.quoted_text = text.text[byte_range].to_owned();
    Ok(())
}
