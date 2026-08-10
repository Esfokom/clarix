use lopdf::{Bookmark, Dictionary, Document, Object};
use std::path::Path;

use crate::api::{NativePdfHighlight, NativePdfSaveRequest};

pub fn save(request: NativePdfSaveRequest) -> Result<(), String> {
    let source = Path::new(&request.path);
    if !source.is_file() {
        return Err(format!("PDF does not exist: {}", request.path));
    }
    let mut document = Document::load(source).map_err(|error| error.to_string())?;
    if document.is_encrypted() {
        return Err("Encrypted PDFs cannot be modified without an owner password.".to_string());
    }
    let pages = document.get_pages();
    for bookmark in request.bookmarks {
        let page = pages.get(&(bookmark.page_number as u32)).ok_or_else(|| {
            format!(
                "Bookmark page {} is outside this PDF.",
                bookmark.page_number
            )
        })?;
        document.add_bookmark(
            Bookmark::new(bookmark.title, [0.0, 0.0, 0.0], 0, *page),
            None,
        );
    }
    if let Some(outlines) = document.build_outline() {
        let catalog = document.catalog_mut().map_err(|error| error.to_string())?;
        catalog.set("Outlines", outlines);
        catalog.set("PageMode", "UseOutlines");
    }
    for highlight in request.highlights {
        append_highlight(&mut document, &pages, highlight)?;
    }
    let temporary = format!("{}.clarix-saving", request.path);
    document
        .save(&temporary)
        .map_err(|error| error.to_string())?;
    std::fs::rename(&temporary, source).map_err(|error| {
        let _ = std::fs::remove_file(&temporary);
        format!("Could not replace the original PDF: {error}")
    })
}

fn append_highlight(
    document: &mut Document,
    pages: &std::collections::BTreeMap<u32, (u32, u16)>,
    highlight: NativePdfHighlight,
) -> Result<(), String> {
    let page_id = *pages.get(&(highlight.page_number as u32)).ok_or_else(|| {
        format!(
            "Highlight page {} is outside this PDF.",
            highlight.page_number
        )
    })?;
    let (left, top, right, bottom) = (
        highlight.left,
        highlight.top,
        highlight.right,
        highlight.bottom,
    );
    let annotation = document.add_object(Dictionary::from_iter([
        ("Type", Object::Name(b"Annot".to_vec())),
        ("Subtype", Object::Name(b"Highlight".to_vec())),
        (
            "Rect",
            vec![left.into(), bottom.into(), right.into(), top.into()].into(),
        ),
        (
            "QuadPoints",
            vec![
                left.into(),
                top.into(),
                right.into(),
                top.into(),
                left.into(),
                bottom.into(),
                right.into(),
                bottom.into(),
            ]
            .into(),
        ),
        (
            "C",
            vec![
                highlight.red.into(),
                highlight.green.into(),
                highlight.blue.into(),
            ]
            .into(),
        ),
        ("CA", highlight.opacity.into()),
        ("Contents", Object::string_literal(highlight.text)),
        ("NM", Object::string_literal(highlight.id)),
    ]));
    let page = document
        .get_dictionary_mut(page_id)
        .map_err(|error| error.to_string())?;
    let annotations = page.get_mut(b"Annots").ok();
    match annotations {
        Some(Object::Array(items)) => items.push(annotation.into()),
        _ => page.set("Annots", vec![annotation.into()]),
    }
    Ok(())
}
