use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use lopdf::{Dictionary, Document, Object, ObjectId};

use crate::api::{
    NativePdfAnnotations, NativePdfBookmark, NativePdfHighlight, NativePdfSaveRequest,
};

/// Reads native PDF state. IDs are stable object references for imported
/// objects, or their /NM names when a previous Clarix save supplied one.
pub fn read(path: &str) -> Result<NativePdfAnnotations, String> {
    let document = Document::load(path).map_err(|error| error.to_string())?;
    let pages = document.get_pages();
    let page_numbers = pages
        .iter()
        .map(|(number, id)| (*id, *number as usize))
        .collect();
    Ok(NativePdfAnnotations {
        bookmarks: read_bookmarks(&document, &page_numbers)?,
        highlights: read_highlights(&document, &pages)?,
    })
}

pub fn save(request: NativePdfSaveRequest) -> Result<(), String> {
    let source = Path::new(&request.path);
    if !source.is_file() {
        return Err(format!("PDF does not exist: {}", request.path));
    }
    let output_path = request.output_path.as_deref().unwrap_or(&request.path);
    let destination = Path::new(output_path);
    let mut document = Document::load(source).map_err(|error| error.to_string())?;
    if document.is_encrypted() {
        return Err("Encrypted PDFs cannot be modified without an owner password.".to_string());
    }
    let pages = document.get_pages();
    merge_bookmarks(&mut document, &pages, request.bookmarks)?;
    merge_highlights(&mut document, &pages, request.highlights)?;
    let temporary = format!("{}.clarix-saving", output_path);
    document
        .save(&temporary)
        .map_err(|error| error.to_string())?;
    std::fs::rename(&temporary, destination).map_err(|error| {
        let _ = std::fs::remove_file(&temporary);
        format!("Could not replace the original PDF: {error}")
    })
}

fn read_bookmarks(
    document: &Document,
    pages: &BTreeMap<ObjectId, usize>,
) -> Result<Vec<NativePdfBookmark>, String> {
    let catalog = document.catalog().map_err(|error| error.to_string())?;
    let outlines = match resolve_dict(document, catalog.get(b"Outlines").ok()) {
        Some(value) => value,
        None => return Ok(vec![]),
    };
    let mut result = Vec::new();
    let mut seen = BTreeSet::new();
    collect_outline_chain(
        document,
        outlines.get(b"First").ok(),
        pages,
        &mut seen,
        &mut result,
    )?;
    Ok(result)
}

fn collect_outline_chain(
    document: &Document,
    first: Option<&Object>,
    pages: &BTreeMap<ObjectId, usize>,
    seen: &mut BTreeSet<ObjectId>,
    result: &mut Vec<NativePdfBookmark>,
) -> Result<(), String> {
    let mut next = first.cloned();
    while let Some(node) = next {
        let (id, dict) = resolve_dict_with_id(document, &node)
            .ok_or_else(|| "Invalid PDF outline node.".to_string())?;
        if !seen.insert(id) {
            break;
        }
        if let Some((title, page_number)) = outline_title_and_page(document, dict, pages) {
            let id = dict
                .get(b"NM")
                .ok()
                .and_then(pdf_string)
                .unwrap_or_else(|| format!("native-outline-{}-{}", id.0, id.1));
            result.push(NativePdfBookmark {
                id,
                title,
                page_number,
            });
        }
        if let Ok(child) = dict.get(b"First") {
            collect_outline_chain(document, Some(child), pages, seen, result)?;
        }
        next = dict.get(b"Next").ok().cloned();
    }
    Ok(())
}

fn outline_title_and_page(
    document: &Document,
    dict: &Dictionary,
    pages: &BTreeMap<ObjectId, usize>,
) -> Option<(String, usize)> {
    let title = pdf_string(dict.get(b"Title").ok()?)?;
    let destination = dict.get(b"Dest").ok().or_else(|| {
        resolve_dict(document, dict.get(b"A").ok()).and_then(|action| action.get(b"D").ok())
    })?;
    let destination = resolve_object(document, destination)?;
    let page_id = destination.as_array().ok()?.first()?.as_reference().ok()?;
    Some((title, *pages.get(&page_id)?))
}

fn read_highlights(
    document: &Document,
    pages: &BTreeMap<u32, ObjectId>,
) -> Result<Vec<NativePdfHighlight>, String> {
    let mut result = Vec::new();
    for (page_number, page_id) in pages {
        let page = document
            .get_dictionary(*page_id)
            .map_err(|error| error.to_string())?;
        let Ok(annots) = page.get(b"Annots").and_then(Object::as_array) else {
            continue;
        };
        for annotation in annots {
            let (object_id, dict) = match resolve_dict_with_id(document, annotation) {
                Some(value) => value,
                None => continue,
            };
            if dict
                .get(b"Subtype")
                .ok()
                .and_then(|value| value.as_name().ok())
                != Some(b"Highlight")
            {
                continue;
            }
            let rect = dict
                .get(b"Rect")
                .ok()
                .and_then(|value| value.as_array().ok());
            let Some(rect) = rect.filter(|value| value.len() >= 4) else {
                continue;
            };
            let color = dict.get(b"C").ok().and_then(|value| value.as_array().ok());
            let channel = |index| {
                color
                    .and_then(|value| value.get(index))
                    .and_then(pdf_number)
                    .unwrap_or(1.0)
            };
            result.push(NativePdfHighlight {
                id: dict
                    .get(b"NM")
                    .ok()
                    .and_then(pdf_string)
                    .unwrap_or_else(|| format!("native-highlight-{}-{}", object_id.0, object_id.1)),
                page_number: *page_number as usize,
                left: pdf_number(&rect[0]).unwrap_or_default(),
                bottom: pdf_number(&rect[1]).unwrap_or_default(),
                right: pdf_number(&rect[2]).unwrap_or_default(),
                top: pdf_number(&rect[3]).unwrap_or_default(),
                red: channel(0),
                green: channel(1),
                blue: channel(2),
                opacity: dict.get(b"CA").ok().and_then(pdf_number).unwrap_or(1.0),
                text: dict
                    .get(b"Contents")
                    .ok()
                    .and_then(pdf_string)
                    .unwrap_or_default(),
                quad_points: dict
                    .get(b"QuadPoints")
                    .ok()
                    .and_then(|value| value.as_array().ok())
                    .map(|points| points.iter().filter_map(pdf_number).collect())
                    .unwrap_or_default(),
            });
        }
    }
    Ok(result)
}

fn merge_bookmarks(
    document: &mut Document,
    pages: &BTreeMap<u32, ObjectId>,
    bookmarks: Vec<NativePdfBookmark>,
) -> Result<(), String> {
    let existing = outline_ids(document)?;
    let mut additions = Vec::new();
    for bookmark in bookmarks {
        let page = *pages.get(&(bookmark.page_number as u32)).ok_or_else(|| {
            format!(
                "Bookmark page {} is outside this PDF.",
                bookmark.page_number
            )
        })?;
        if let Some(id) = existing.get(&bookmark.id) {
            let outline = document
                .get_dictionary_mut(*id)
                .map_err(|error| error.to_string())?;
            outline.set("Title", Object::string_literal(bookmark.title));
            outline.set(
                "Dest",
                vec![
                    Object::Reference(page),
                    Object::Name(b"XYZ".to_vec()),
                    0.into(),
                    0.into(),
                    0.into(),
                ],
            );
        } else {
            additions.push(bookmark);
        }
    }
    if additions.is_empty() {
        return Ok(());
    }
    let additions_count = additions.len() as i64;
    let outline_id = ensure_outlines_root(document)?;
    let last = document
        .get_dictionary(outline_id)
        .ok()
        .and_then(|outline| outline.get(b"Last").ok())
        .and_then(|value| value.as_reference().ok());
    let mut previous = last;
    for bookmark in additions {
        let page = *pages.get(&(bookmark.page_number as u32)).ok_or_else(|| {
            format!(
                "Bookmark page {} is outside this PDF.",
                bookmark.page_number
            )
        })?;
        let id = document.add_object(Dictionary::from_iter([
            ("Title", Object::string_literal(bookmark.title)),
            ("Parent", Object::Reference(outline_id)),
            (
                "Dest",
                vec![
                    Object::Reference(page),
                    Object::Name(b"XYZ".to_vec()),
                    0.into(),
                    0.into(),
                    0.into(),
                ]
                .into(),
            ),
            ("NM", Object::string_literal(bookmark.id)),
        ]));
        if let Some(previous_id) = previous {
            document
                .get_dictionary_mut(previous_id)
                .map_err(|e| e.to_string())?
                .set("Next", id);
            document
                .get_dictionary_mut(id)
                .map_err(|e| e.to_string())?
                .set("Prev", previous_id);
        } else {
            document
                .get_dictionary_mut(outline_id)
                .map_err(|e| e.to_string())?
                .set("First", id);
        }
        previous = Some(id);
    }
    let outline = document
        .get_dictionary_mut(outline_id)
        .map_err(|e| e.to_string())?;
    if let Some(last) = previous {
        outline.set("Last", last);
    }
    let count = outline
        .get(b"Count")
        .ok()
        .and_then(|value| value.as_i64().ok())
        .unwrap_or(0)
        + additions_count;
    outline.set("Count", count);
    Ok(())
}

fn outline_ids(document: &Document) -> Result<BTreeMap<String, ObjectId>, String> {
    let catalog = document.catalog().map_err(|error| error.to_string())?;
    let outlines = match resolve_dict(document, catalog.get(b"Outlines").ok()) {
        Some(value) => value,
        None => return Ok(BTreeMap::new()),
    };
    let mut ids = BTreeMap::new();
    collect_outline_ids(
        document,
        outlines.get(b"First").ok(),
        &mut BTreeSet::new(),
        &mut ids,
    )?;
    Ok(ids)
}

fn collect_outline_ids(
    document: &Document,
    first: Option<&Object>,
    seen: &mut BTreeSet<ObjectId>,
    ids: &mut BTreeMap<String, ObjectId>,
) -> Result<(), String> {
    let mut next = first.cloned();
    while let Some(node) = next {
        let (id, dict) = resolve_dict_with_id(document, &node)
            .ok_or_else(|| "Invalid PDF outline node.".to_string())?;
        if !seen.insert(id) {
            break;
        }
        if let Some(name) = dict.get(b"NM").ok().and_then(pdf_string) {
            ids.insert(name, id);
        }
        if let Ok(child) = dict.get(b"First") {
            collect_outline_ids(document, Some(child), seen, ids)?;
        }
        next = dict.get(b"Next").ok().cloned();
    }
    Ok(())
}

fn ensure_outlines_root(document: &mut Document) -> Result<ObjectId, String> {
    if let Ok(catalog) = document.catalog() {
        if let Ok(id) = catalog.get(b"Outlines").and_then(Object::as_reference) {
            return Ok(id);
        }
    }
    let root = document.add_object(Dictionary::new());
    let catalog = document.catalog_mut().map_err(|error| error.to_string())?;
    catalog.set("Outlines", root);
    catalog.set("PageMode", "UseOutlines");
    Ok(root)
}

fn merge_highlights(
    document: &mut Document,
    pages: &BTreeMap<u32, ObjectId>,
    highlights: Vec<NativePdfHighlight>,
) -> Result<(), String> {
    let mut existing = BTreeMap::new();
    for page_id in pages.values() {
        let page = document
            .get_dictionary(*page_id)
            .map_err(|error| error.to_string())?;
        if let Ok(annots) = page.get(b"Annots").and_then(Object::as_array) {
            for annotation in annots {
                if let Some((id, dict)) = resolve_dict_with_id(document, annotation) {
                    if dict
                        .get(b"Subtype")
                        .ok()
                        .and_then(|value| value.as_name().ok())
                        == Some(b"Highlight")
                    {
                        if let Some(name) = dict.get(b"NM").ok().and_then(pdf_string) {
                            existing.insert(name, id);
                        }
                    }
                }
            }
        }
    }
    for highlight in highlights {
        if let Some(id) = existing.get(&highlight.id) {
            let annotation = document
                .get_dictionary_mut(*id)
                .map_err(|error| error.to_string())?;
            set_highlight_geometry(annotation, &highlight);
            annotation.set(
                "C",
                vec![
                    highlight.red.into(),
                    highlight.green.into(),
                    highlight.blue.into(),
                ],
            );
            annotation.set("CA", highlight.opacity);
            annotation.set("Contents", Object::string_literal(highlight.text));
        } else {
            append_highlight(document, pages, highlight)?;
        }
    }
    Ok(())
}

fn append_highlight(
    document: &mut Document,
    pages: &BTreeMap<u32, ObjectId>,
    highlight: NativePdfHighlight,
) -> Result<(), String> {
    let page_id = *pages.get(&(highlight.page_number as u32)).ok_or_else(|| {
        format!(
            "Highlight page {} is outside this PDF.",
            highlight.page_number
        )
    })?;
    let mut annotation = Dictionary::from_iter([
        ("Type", Object::Name(b"Annot".to_vec())),
        ("Subtype", Object::Name(b"Highlight".to_vec())),
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
        ("Contents", Object::string_literal(highlight.text.clone())),
        ("NM", Object::string_literal(highlight.id.clone())),
    ]);
    set_highlight_geometry(&mut annotation, &highlight);
    let annotation = document.add_object(annotation);
    let page = document
        .get_dictionary_mut(page_id)
        .map_err(|error| error.to_string())?;
    match page.get_mut(b"Annots") {
        Ok(Object::Array(items)) => items.push(annotation.into()),
        _ => page.set("Annots", vec![annotation.into()]),
    }
    Ok(())
}

fn set_highlight_geometry(annotation: &mut Dictionary, highlight: &NativePdfHighlight) {
    let points = if highlight.quad_points.len() >= 8 {
        highlight.quad_points.clone()
    } else {
        vec![
            highlight.left,
            highlight.top,
            highlight.right,
            highlight.top,
            highlight.left,
            highlight.bottom,
            highlight.right,
            highlight.bottom,
        ]
    };
    let xs = points.iter().step_by(2).copied().collect::<Vec<_>>();
    let ys = points
        .iter()
        .skip(1)
        .step_by(2)
        .copied()
        .collect::<Vec<_>>();
    annotation.set(
        "Rect",
        vec![
            xs.iter().copied().fold(f32::INFINITY, f32::min).into(),
            ys.iter().copied().fold(f32::INFINITY, f32::min).into(),
            xs.iter().copied().fold(f32::NEG_INFINITY, f32::max).into(),
            ys.iter().copied().fold(f32::NEG_INFINITY, f32::max).into(),
        ],
    );
    annotation.set(
        "QuadPoints",
        points.into_iter().map(Object::from).collect::<Vec<_>>(),
    );
}

fn resolve_object<'a>(document: &'a Document, object: &'a Object) -> Option<&'a Object> {
    match object {
        Object::Reference(id) => document.get_object(*id).ok(),
        _ => Some(object),
    }
}
fn resolve_dict<'a>(document: &'a Document, object: Option<&'a Object>) -> Option<&'a Dictionary> {
    resolve_object(document, object?).and_then(|value| value.as_dict().ok())
}
fn resolve_dict_with_id<'a>(
    document: &'a Document,
    object: &'a Object,
) -> Option<(ObjectId, &'a Dictionary)> {
    let id = object.as_reference().ok()?;
    Some((id, document.get_dictionary(id).ok()?))
}
fn pdf_number(object: &Object) -> Option<f32> {
    object
        .as_float()
        .ok()
        .or_else(|| object.as_i64().ok().map(|value| value as f32))
}
fn pdf_string(object: &Object) -> Option<String> {
    object
        .as_str()
        .ok()
        .map(|value| String::from_utf8_lossy(value).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use lopdf::dictionary;

    #[test]
    fn reads_saves_and_reopens_native_bookmarks_and_highlights_without_duplication() {
        let path =
            std::env::temp_dir().join(format!("clarix-annotations-{}.pdf", std::process::id()));
        let mut document = Document::with_version("1.5");
        let pages_id = document.new_object_id();
        let page_id = document.add_object(dictionary! { "Type" => "Page", "Parent" => pages_id, "MediaBox" => vec![0.into(), 0.into(), 200.into(), 200.into()] });
        document.objects.insert(
            pages_id,
            dictionary! { "Type" => "Pages", "Kids" => vec![page_id.into()], "Count" => 1 }.into(),
        );
        let highlight_id = document.add_object(dictionary! {
            "Type" => "Annot", "Subtype" => "Highlight", "Rect" => vec![10.into(), 20.into(), 90.into(), 40.into()],
            "QuadPoints" => vec![10.into(), 40.into(), 90.into(), 40.into(), 10.into(), 20.into(), 90.into(), 20.into()],
            "C" => vec![1.into(), 0.into(), 0.into()], "Contents" => Object::string_literal("native text"), "NM" => Object::string_literal("native-hl"),
        });
        document
            .get_dictionary_mut(page_id)
            .unwrap()
            .set("Annots", vec![highlight_id.into()]);
        let outline_id = document.add_object(dictionary! { "Count" => 1 });
        let outline_item = document.add_object(dictionary! { "Title" => Object::string_literal("Native outline"), "Parent" => outline_id, "Dest" => vec![page_id.into(), Object::Name(b"XYZ".to_vec()), 0.into(), 0.into(), 0.into()], "NM" => Object::string_literal("native-outline") });
        let outline = document.get_dictionary_mut(outline_id).unwrap();
        outline.set("First", outline_item);
        outline.set("Last", outline_item);
        let catalog_id = document.add_object(
            dictionary! { "Type" => "Catalog", "Pages" => pages_id, "Outlines" => outline_id },
        );
        document.trailer.set("Root", catalog_id);
        document.save(&path).unwrap();

        let read_before = read(path.to_str().unwrap()).unwrap();
        assert_eq!(read_before.bookmarks[0].title, "Native outline");
        assert_eq!(read_before.highlights[0].text, "native text");
        assert_eq!(read_before.highlights[0].top, 40.0);

        let mut edited_bookmarks = read_before.bookmarks.clone();
        edited_bookmarks[0].title = "Renamed native outline".to_string();
        let mut edited_highlights = read_before.highlights.clone();
        edited_highlights[0].blue = 1.0;
        save(NativePdfSaveRequest {
            path: path.to_string_lossy().into_owned(),
            output_path: None,
            bookmarks: edited_bookmarks,
            highlights: edited_highlights,
        })
        .unwrap();
        let read_after = read(path.to_str().unwrap()).unwrap();
        assert_eq!(read_after.bookmarks.len(), 1);
        assert_eq!(read_after.bookmarks[0].title, "Renamed native outline");
        assert_eq!(read_after.highlights.len(), 1);
        assert_eq!(read_after.highlights[0].id, "native-hl");
        assert_eq!(read_after.highlights[0].blue, 1.0);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn saves_a_normalized_source_to_the_requested_original_path() {
        let source = std::env::temp_dir().join(format!(
            "clarix-normalized-source-{}.pdf",
            std::process::id()
        ));
        let destination = std::env::temp_dir().join(format!(
            "clarix-normalized-destination-{}.pdf",
            std::process::id()
        ));
        let mut document = Document::with_version("1.5");
        let pages_id = document.new_object_id();
        let page_id = document.add_object(dictionary! {
            "Type" => "Page", "Parent" => pages_id,
            "MediaBox" => vec![0.into(), 0.into(), 200.into(), 200.into()]
        });
        document.objects.insert(
            pages_id,
            dictionary! { "Type" => "Pages", "Kids" => vec![page_id.into()], "Count" => 1 }.into(),
        );
        let catalog_id =
            document.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages_id });
        document.trailer.set("Root", catalog_id);
        document.save(&source).unwrap();
        std::fs::write(&destination, b"existing destination").unwrap();

        save(NativePdfSaveRequest {
            path: source.to_string_lossy().into_owned(),
            output_path: Some(destination.to_string_lossy().into_owned()),
            bookmarks: vec![],
            highlights: vec![],
        })
        .unwrap();

        assert!(source.is_file());
        assert!(destination.is_file());
        assert_eq!(Document::load(&destination).unwrap().get_pages().len(), 1);
        let _ = std::fs::remove_file(source);
        let _ = std::fs::remove_file(destination);
    }
}
