use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use lopdf::{dictionary, Document, Object, ObjectId};

use crate::api::{NativePdfComposeRequest, NativePdfComposeResponse};

const INHERITED_PAGE_ATTRIBUTES: [&[u8]; 4] = [b"Resources", b"MediaBox", b"CropBox", b"Rotate"];

pub fn compose_pdfs(request: NativePdfComposeRequest) -> NativePdfComposeResponse {
    let output_path = request.output_path.clone();
    match compose(&request) {
        Ok(page_count) => NativePdfComposeResponse {
            output_path,
            page_count,
            message: None,
        },
        Err(message) => NativePdfComposeResponse {
            output_path,
            page_count: 0,
            message: Some(message),
        },
    }
}

fn compose(request: &NativePdfComposeRequest) -> Result<usize, String> {
    if request.sources.is_empty() {
        return Err("Select at least one source PDF to compose.".to_string());
    }
    if request.output_path.trim().is_empty() {
        return Err("Choose an output path for the composed PDF.".to_string());
    }

    let output_path = PathBuf::from(&request.output_path);
    let partial_path = PathBuf::from(format!("{}.partial", request.output_path));
    for source in &request.sources {
        let source_path = Path::new(&source.path);
        if paths_refer_to_same_file(source_path, &output_path)
            || paths_refer_to_same_file(source_path, &partial_path)
        {
            return Err(
                "Choose an output path different from every source PDF so source files remain unchanged."
                    .to_string(),
            );
        }
    }

    let mut destination = Document::with_version("1.5");
    let mut next_object_id = 1;
    let mut selected_page_ids = Vec::new();

    for source in &request.sources {
        if source.path.trim().is_empty() {
            return Err(
                "A source PDF path is empty. Remove it and select the file again.".to_string(),
            );
        }

        let mut source_document = Document::load(&source.path)
            .map_err(|error| format!("Could not open source PDF '{}': {error}", source.path))?;
        if source_document.is_encrypted() {
            return Err(format!(
                "Source PDF '{}' is encrypted. Unlock it before combining or extracting pages.",
                source.path
            ));
        }

        if source_document.version > destination.version {
            destination.version = source_document.version.clone();
        }
        source_document.renumber_objects_with(next_object_id);
        next_object_id = source_document.max_id.saturating_add(1);

        let available_pages = source_document.get_pages();
        if available_pages.is_empty() {
            return Err(format!("Source PDF '{}' contains no pages.", source.path));
        }
        let requested_pages = if source.pages.is_empty() {
            available_pages.keys().map(|page| *page as usize).collect()
        } else {
            source.pages.clone()
        };

        for page_number in requested_pages {
            let page_id = available_pages
                .get(&(page_number as u32))
                .copied()
                .ok_or_else(|| {
                    format!(
                        "Page {page_number} is outside source PDF '{}' ({} {}).",
                        source.path,
                        available_pages.len(),
                        if available_pages.len() == 1 {
                            "page"
                        } else {
                            "pages"
                        }
                    )
                })?;
            materialize_inherited_page_attributes(&mut source_document, page_id)?;
            selected_page_ids.push(page_id);
        }

        destination.max_id = destination.max_id.max(source_document.max_id);
        destination.objects.extend(source_document.objects);
    }

    if selected_page_ids.is_empty() {
        return Err("Select at least one PDF page to compose.".to_string());
    }

    let pages_id = destination.new_object_id();
    let unique_page_ids = selected_page_ids.iter().copied().collect::<BTreeSet<_>>();
    for page_id in unique_page_ids {
        destination
            .get_dictionary_mut(page_id)
            .map_err(|error| format!("Could not import a selected PDF page: {error}"))?
            .set("Parent", pages_id);
    }
    destination.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => selected_page_ids
                .iter()
                .copied()
                .map(Object::Reference)
                .collect::<Vec<_>>(),
            "Count" => selected_page_ids.len() as i64,
        }),
    );
    let catalog_id = destination.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    destination.trailer.set("Root", catalog_id);

    if partial_path.exists() {
        fs::remove_file(&partial_path).map_err(|error| {
            format!(
                "Could not remove stale temporary output '{}': {error}",
                partial_path.display()
            )
        })?;
    }

    let save_result = destination.save(&partial_path).map_err(|error| {
        format!(
            "Could not save temporary composed PDF '{}': {error}",
            partial_path.display()
        )
    });
    let saved_file = match save_result {
        Ok(file) => file,
        Err(message) => {
            let _ = fs::remove_file(&partial_path);
            return Err(message);
        }
    };
    drop(saved_file);

    if let Err(error) = fs::rename(&partial_path, &output_path) {
        let _ = fs::remove_file(&partial_path);
        return Err(format!(
            "Could not move the composed PDF to '{}': {error}",
            output_path.display()
        ));
    }

    Ok(selected_page_ids.len())
}

fn materialize_inherited_page_attributes(
    document: &mut Document,
    page_id: ObjectId,
) -> Result<(), String> {
    let attributes = INHERITED_PAGE_ATTRIBUTES
        .iter()
        .filter_map(|key| {
            inherited_page_attribute(document, page_id, key).map(|value| ((*key).to_vec(), value))
        })
        .collect::<Vec<_>>();
    let page = document
        .get_dictionary_mut(page_id)
        .map_err(|error| format!("Could not read a selected PDF page: {error}"))?;
    for (key, value) in attributes {
        if !page.has(&key) {
            page.set(key, value);
        }
    }
    Ok(())
}

fn inherited_page_attribute(document: &Document, page_id: ObjectId, key: &[u8]) -> Option<Object> {
    let mut current_id = page_id;
    let mut visited = BTreeSet::new();
    while visited.insert(current_id) {
        let dictionary = document.get_dictionary(current_id).ok()?;
        if let Ok(value) = dictionary.get(key) {
            return Some(value.clone());
        }
        current_id = dictionary.get(b"Parent").ok()?.as_reference().ok()?;
    }
    None
}

fn paths_refer_to_same_file(first: &Path, second: &Path) -> bool {
    if first == second {
        return true;
    }
    match (fs::canonicalize(first), fs::canonicalize(second)) {
        (Ok(first), Ok(second)) => first == second,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    use lopdf::{dictionary, Document, Object};

    use super::compose_pdfs;
    use crate::api::{NativePdfComposeRequest, NativePdfSource};

    static NEXT_FIXTURE_ID: AtomicUsize = AtomicUsize::new(0);

    struct FixtureDirectory(PathBuf);

    impl FixtureDirectory {
        fn new() -> Self {
            let id = NEXT_FIXTURE_ID.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir()
                .join(format!("clarix-pdf-compose-{}-{id}", std::process::id()));
            fs::create_dir_all(&path).expect("create fixture directory");
            Self(path)
        }

        fn path(&self, name: &str) -> PathBuf {
            self.0.join(name)
        }
    }

    impl Drop for FixtureDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn compose_preserves_requested_page_order_without_touching_sources() {
        let fixtures = FixtureDirectory::new();
        let first_path = fixtures.path("first.pdf");
        let second_path = fixtures.path("second.pdf");
        let output_path = fixtures.path("merged.pdf");
        write_fixture_pdf(&first_path, &[111, 112]);
        write_fixture_pdf(&second_path, &[221, 222]);
        let first_before = fs::read(&first_path).expect("read first fixture");
        let second_before = fs::read(&second_path).expect("read second fixture");

        let response = compose_pdfs(NativePdfComposeRequest {
            sources: vec![
                NativePdfSource {
                    path: path_string(&first_path),
                    pages: vec![2, 1],
                },
                NativePdfSource {
                    path: path_string(&second_path),
                    pages: vec![2],
                },
            ],
            output_path: path_string(&output_path),
        });

        assert_eq!(response.message, None);
        assert_eq!(response.output_path, path_string(&output_path));
        assert_eq!(response.page_count, 3);
        assert_eq!(page_widths(&output_path), vec![112, 111, 222]);
        assert_eq!(fs::read(&first_path).expect("reread first"), first_before);
        assert_eq!(
            fs::read(&second_path).expect("reread second"),
            second_before
        );
        assert!(!PathBuf::from(format!("{}.partial", path_string(&output_path))).exists());
    }

    #[test]
    fn compose_rejects_overwriting_a_source_pdf() {
        let fixtures = FixtureDirectory::new();
        let source_path = fixtures.path("source.pdf");
        write_fixture_pdf(&source_path, &[320]);
        let source_before = fs::read(&source_path).expect("read source fixture");

        let response = compose_pdfs(NativePdfComposeRequest {
            sources: vec![NativePdfSource {
                path: path_string(&source_path),
                pages: vec![1],
            }],
            output_path: path_string(&source_path),
        });

        assert!(response
            .message
            .as_deref()
            .is_some_and(|message| message.contains("different from every source")));
        assert_eq!(response.page_count, 0);
        assert_eq!(
            fs::read(&source_path).expect("reread source"),
            source_before
        );
    }

    #[test]
    fn compose_reports_invalid_pages_and_leaves_no_partial_output() {
        let fixtures = FixtureDirectory::new();
        let source_path = fixtures.path("source.pdf");
        let output_path = fixtures.path("merged.pdf");
        write_fixture_pdf(&source_path, &[410]);

        let response = compose_pdfs(NativePdfComposeRequest {
            sources: vec![NativePdfSource {
                path: path_string(&source_path),
                pages: vec![2],
            }],
            output_path: path_string(&output_path),
        });

        assert!(response
            .message
            .as_deref()
            .is_some_and(|message| message.contains("Page 2") && message.contains("1 page")));
        assert_eq!(response.page_count, 0);
        assert!(!output_path.exists());
        assert!(!PathBuf::from(format!("{}.partial", path_string(&output_path))).exists());
    }

    fn write_fixture_pdf(path: &Path, page_widths: &[i64]) {
        let mut document = Document::with_version("1.5");
        let pages_id = document.new_object_id();
        let page_ids = page_widths
            .iter()
            .map(|width| {
                document.add_object(dictionary! {
                    "Type" => "Page",
                    "Parent" => pages_id,
                    "MediaBox" => vec![0.into(), 0.into(), (*width).into(), 500.into()],
                    "Resources" => dictionary! {},
                })
            })
            .collect::<Vec<_>>();
        document.objects.insert(
            pages_id,
            Object::Dictionary(dictionary! {
                "Type" => "Pages",
                "Kids" => page_ids
                    .iter()
                    .copied()
                    .map(Object::Reference)
                    .collect::<Vec<_>>(),
                "Count" => page_ids.len() as i64,
            }),
        );
        let catalog_id = document.add_object(dictionary! {
            "Type" => "Catalog",
            "Pages" => pages_id,
        });
        document.trailer.set("Root", catalog_id);
        document.save(path).expect("save fixture PDF");
    }

    fn page_widths(path: &Path) -> Vec<i64> {
        let document = Document::load(path).expect("open composed PDF");
        document
            .get_pages()
            .into_values()
            .map(|page_id| {
                let page = document
                    .get_dictionary(page_id)
                    .expect("read composed page dictionary");
                let media_box = page
                    .get(b"MediaBox")
                    .and_then(Object::as_array)
                    .expect("read composed page MediaBox");
                media_box[2].as_i64().expect("read page width")
            })
            .collect()
    }

    fn path_string(path: &Path) -> String {
        path.to_string_lossy().into_owned()
    }
}
