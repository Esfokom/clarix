use serde::{Deserialize, Serialize};

use crate::{
    selection::validate_selection, text::utf16_range_to_byte_range, DocumentId, DocumentModel,
    DocumentObject, DocumentRevision, EditingError, ObjectId, PageId, PdfBox, SelectionKind,
    SelectionSet, TextRangeRef, Utf16Range,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContextLimits {
    pub before_utf16: u32,
    pub after_utf16: u32,
    pub max_ranges: u32,
}

impl Default for ContextLimits {
    fn default() -> Self {
        Self {
            before_utf16: 512,
            after_utf16: 512,
            max_ranges: 8,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SelectionStyleSummary {
    pub font_families: Vec<String>,
    pub font_sizes: Vec<f64>,
    pub font_weights: Vec<u16>,
    pub italic_values: Vec<bool>,
    pub colors_rgba: Vec<[u8; 4]>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SelectionQuad {
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub page_number: u32,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub bounds: PdfBox,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SelectionContext {
    pub document_id: DocumentId,
    pub document_revision: DocumentRevision,
    pub kind: SelectionKind,
    pub ranges: Vec<TextRangeRef>,
    pub object_ids: Vec<ObjectId>,
    pub primary_index: Option<u32>,
    pub page_ids: Vec<PageId>,
    pub style_summary: SelectionStyleSummary,
    pub quads: Vec<SelectionQuad>,
    pub nearby_text_before: String,
    pub nearby_text_after: String,
}

pub struct SelectionContextBuilder;

impl SelectionContextBuilder {
    pub fn build(
        model: &DocumentModel,
        selection: SelectionSet,
        limits: ContextLimits,
    ) -> Result<SelectionContext, EditingError> {
        if limits.max_ranges == 0 {
            return Err(EditingError::InvalidCommand(
                "selection context range limit must be positive".into(),
            ));
        }
        let selection = validate_selection(model, selection)?;
        let selected_count = match selection.kind {
            SelectionKind::TextRanges => selection.ranges.len(),
            SelectionKind::Objects => selection.object_ids.len(),
        };
        if selected_count > limits.max_ranges as usize {
            return Err(EditingError::SelectionLimitExceeded {
                limit: limits.max_ranges,
                actual: selected_count,
            });
        }

        let mut page_ids = Vec::new();
        let mut styles = StyleAccumulator::default();
        let mut quads = Vec::new();
        let (nearby_text_before, nearby_text_after) = match selection.kind {
            SelectionKind::TextRanges => {
                for range in &selection.ranges {
                    push_unique(&mut page_ids, range.page_id);
                    collect_text_range(model, range, &mut styles, &mut quads)?;
                }
                primary_nearby_text(model, &selection, limits)?
            }
            SelectionKind::Objects => {
                for object_id in &selection.object_ids {
                    let object = model
                        .object(*object_id)
                        .ok_or(EditingError::ObjectNotFound(*object_id))?;
                    let page = model
                        .pages
                        .iter()
                        .find(|page| page.id == object.page_id())
                        .ok_or_else(|| {
                            EditingError::InvalidCommand(
                                "selected object page is unavailable".into(),
                            )
                        })?;
                    push_unique(&mut page_ids, page.id);
                    if let DocumentObject::Text(text) = object {
                        for run in &text.runs {
                            styles.push(&run.style);
                        }
                    }
                    quads.push(SelectionQuad {
                        object_id: *object_id,
                        page_id: page.id,
                        page_number: page.page_number,
                        start_utf16: 0,
                        end_utf16: 0,
                        bounds: object.bounds(),
                    });
                }
                (String::new(), String::new())
            }
        };

        Ok(SelectionContext {
            document_id: model.id,
            document_revision: model.revision,
            kind: selection.kind,
            ranges: selection.ranges,
            object_ids: selection.object_ids,
            primary_index: selection.primary_index,
            page_ids,
            style_summary: styles.finish(),
            quads,
            nearby_text_before,
            nearby_text_after,
        })
    }
}

fn collect_text_range(
    model: &DocumentModel,
    range: &TextRangeRef,
    styles: &mut StyleAccumulator,
    quads: &mut Vec<SelectionQuad>,
) -> Result<(), EditingError> {
    let object = model
        .object(range.object_id)
        .ok_or(EditingError::ObjectNotFound(range.object_id))?;
    let DocumentObject::Text(text) = object else {
        return Err(EditingError::WrongObjectKind(range.object_id));
    };
    for run in &text.runs {
        if run.range.start < range.end_utf16 && run.range.end > range.start_utf16 {
            styles.push(&run.style);
        }
    }
    for character in &text.character_boxes {
        if character.range.start < range.end_utf16 && character.range.end > range.start_utf16 {
            quads.push(SelectionQuad {
                object_id: range.object_id,
                page_id: range.page_id,
                page_number: range.page_number,
                start_utf16: character.range.start.max(range.start_utf16),
                end_utf16: character.range.end.min(range.end_utf16),
                bounds: character.bounds,
            });
        }
    }
    Ok(())
}

fn primary_nearby_text(
    model: &DocumentModel,
    selection: &SelectionSet,
    limits: ContextLimits,
) -> Result<(String, String), EditingError> {
    let range = selection
        .primary_index
        .and_then(|index| selection.ranges.get(index as usize))
        .or_else(|| selection.ranges.first())
        .ok_or_else(|| EditingError::InvalidCommand("text selection is empty".into()))?;
    let object = model
        .object(range.object_id)
        .ok_or(EditingError::ObjectNotFound(range.object_id))?;
    let DocumentObject::Text(text) = object else {
        return Err(EditingError::WrongObjectKind(range.object_id));
    };
    let bytes = utf16_range_to_byte_range(
        &text.text,
        Utf16Range::new(range.start_utf16, range.end_utf16)
            .map_err(|_| EditingError::InvalidTextBoundary)?,
    )
    .map_err(|_| EditingError::InvalidTextBoundary)?;
    Ok((
        utf16_suffix(&text.text[..bytes.start], limits.before_utf16),
        utf16_prefix(&text.text[bytes.end..], limits.after_utf16),
    ))
}

fn utf16_prefix(text: &str, limit: u32) -> String {
    let mut used = 0_u32;
    let mut end = 0;
    for (offset, character) in text.char_indices() {
        let next = used + character.len_utf16() as u32;
        if next > limit {
            break;
        }
        used = next;
        end = offset + character.len_utf8();
    }
    text[..end].to_owned()
}

fn utf16_suffix(text: &str, limit: u32) -> String {
    let mut used = 0_u32;
    let mut start = text.len();
    for (offset, character) in text.char_indices().rev() {
        let next = used + character.len_utf16() as u32;
        if next > limit {
            break;
        }
        used = next;
        start = offset;
    }
    text[start..].to_owned()
}

fn push_unique<T: PartialEq>(values: &mut Vec<T>, value: T) {
    if !values.contains(&value) {
        values.push(value);
    }
}

#[derive(Default)]
struct StyleAccumulator {
    font_families: Vec<String>,
    font_sizes: Vec<f64>,
    font_weights: Vec<u16>,
    italic_values: Vec<bool>,
    colors_rgba: Vec<[u8; 4]>,
}

impl StyleAccumulator {
    fn push(&mut self, style: &crate::TextStyle) {
        if let Some(family) = &style.font_family {
            push_unique(&mut self.font_families, family.clone());
        }
        if !self.font_sizes.contains(&style.font_size) {
            self.font_sizes.push(style.font_size);
        }
        push_unique(&mut self.font_weights, style.font_weight);
        push_unique(&mut self.italic_values, style.italic);
        push_unique(&mut self.colors_rgba, style.color_rgba);
    }

    fn finish(mut self) -> SelectionStyleSummary {
        self.font_families.sort();
        self.font_sizes.sort_by(f64::total_cmp);
        self.font_weights.sort_unstable();
        self.italic_values.sort_unstable();
        self.colors_rgba.sort_unstable();
        SelectionStyleSummary {
            font_families: self.font_families,
            font_sizes: self.font_sizes,
            font_weights: self.font_weights,
            italic_values: self.italic_values,
            colors_rgba: self.colors_rgba,
        }
    }
}
