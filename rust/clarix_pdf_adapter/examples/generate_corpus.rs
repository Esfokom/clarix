use std::error::Error;
use std::path::{Path, PathBuf};

use lopdf::{dictionary, Dictionary, Document, Object, ObjectId, Stream};

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let output = args
        .next()
        .map(PathBuf::from)
        .ok_or("usage: generate_corpus <generated-output> [--private-font-path <ttf>] [--private-output <dir>]")?;
    let mut private_font_path = None;
    let mut private_output = None;
    while let Some(flag) = args.next() {
        match flag.as_str() {
            "--private-font-path" => {
                private_font_path = Some(PathBuf::from(
                    args.next().ok_or("--private-font-path needs a value")?,
                ));
            }
            "--private-output" => {
                private_output = Some(PathBuf::from(
                    args.next().ok_or("--private-output needs a value")?,
                ));
            }
            _ => return Err(format!("unknown argument: {flag}").into()),
        }
    }

    std::fs::create_dir_all(&output)?;
    write_text_pdf(
        &output.join("standard-latin.pdf"),
        b"BT /F1 18 Tf 72 700 Td (Clarix standard Latin text) Tj ET".to_vec(),
        Dictionary::new(),
    )?;
    write_text_pdf(
        &output.join("rotated-text.pdf"),
        b"BT /F1 18 Tf 0 1 -1 0 300 200 Tm (Clarix rotated text) Tj ET".to_vec(),
        Dictionary::new(),
    )?;
    write_text_pdf(
        &output.join("multi-run-text.pdf"),
        b"BT /F1 12 Tf 72 700 Td (First run) Tj /F1 20 Tf 0 -30 Td (Second run) Tj ET".to_vec(),
        Dictionary::new(),
    )?;
    write_mixed_page(&output.join("mixed-page.pdf"))?;
    write_form_xobject(&output.join("form-xobject.pdf"))?;
    write_scanned_page(&output.join("scanned-page.pdf"))?;
    std::fs::write(
        output.join("malformed.pdf"),
        b"not a PDF\0clarix malformed fixture",
    )?;

    match (private_font_path, private_output) {
        (Some(font), Some(private_output)) => {
            std::fs::create_dir_all(&private_output)?;
            let font_bytes = std::fs::read(font)?;
            write_embedded_font_pdf(
                &private_output.join("embedded-truetype.pdf"),
                &font_bytes,
                "Arial",
            )?;
            let mut remapper = subsetter::GlyphRemapper::new();
            for glyph_id in 0..=255 {
                remapper.remap(glyph_id);
            }
            let subset_font = subsetter::subset(&font_bytes, 0, &remapper)?;
            write_embedded_font_pdf(
                &private_output.join("subset-font.pdf"),
                &subset_font,
                "CLARIX+Arial",
            )?;
        }
        (None, None) => {}
        _ => {
            return Err("--private-font-path and --private-output must be supplied together".into())
        }
    }
    Ok(())
}

fn base_document() -> (Document, ObjectId, ObjectId) {
    let mut document = Document::with_version("1.7");
    let pages_id = document.new_object_id();
    let font_id = document.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "Type1",
        "BaseFont" => "Helvetica",
        "Encoding" => "WinAnsiEncoding",
    });
    (document, pages_id, font_id)
}

fn write_text_pdf(
    path: &Path,
    content: Vec<u8>,
    extra_resources: Dictionary,
) -> Result<(), Box<dyn Error>> {
    let (mut document, pages_id, font_id) = base_document();
    let mut resources = dictionary! {
        "Font" => dictionary! { "F1" => font_id },
    };
    for (key, value) in extra_resources.iter() {
        resources.set(key.to_vec(), value.clone());
    }
    add_single_page(&mut document, pages_id, resources, content);
    finish_document(document, pages_id, path)
}

fn write_mixed_page(path: &Path) -> Result<(), Box<dyn Error>> {
    let (mut document, pages_id, font_id) = base_document();
    let image_id = document.add_object(Stream::new(
        dictionary! {
            "Type" => "XObject",
            "Subtype" => "Image",
            "Width" => 1,
            "Height" => 1,
            "ColorSpace" => "DeviceRGB",
            "BitsPerComponent" => 8,
        },
        vec![255, 0, 0],
    ));
    let resources = dictionary! {
        "Font" => dictionary! { "F1" => font_id },
        "XObject" => dictionary! { "Im1" => image_id },
    };
    let content = b"BT /F1 16 Tf 72 700 Td (Mixed page text) Tj ET \
        0 0 1 rg 100 500 120 40 re f \
        q 80 0 0 80 300 500 cm /Im1 Do Q"
        .to_vec();
    add_single_page(&mut document, pages_id, resources, content);
    finish_document(document, pages_id, path)
}

fn write_form_xobject(path: &Path) -> Result<(), Box<dyn Error>> {
    let (mut document, pages_id, font_id) = base_document();
    let form_id = document.add_object(Stream::new(
        dictionary! {
            "Type" => "XObject",
            "Subtype" => "Form",
            "BBox" => vec![0.into(), 0.into(), 300.into(), 100.into()],
            "Resources" => dictionary! { "Font" => dictionary! { "F1" => font_id } },
        },
        b"BT /F1 18 Tf 10 50 Td (Text inside a Form XObject) Tj ET".to_vec(),
    ));
    let resources = dictionary! {
        "Font" => dictionary! { "F1" => font_id },
        "XObject" => dictionary! { "Fm1" => form_id },
    };
    add_single_page(
        &mut document,
        pages_id,
        resources,
        b"q 1 0 0 1 72 600 cm /Fm1 Do Q".to_vec(),
    );
    finish_document(document, pages_id, path)
}

fn write_scanned_page(path: &Path) -> Result<(), Box<dyn Error>> {
    let (mut document, pages_id, _) = base_document();
    let image_id = document.add_object(Stream::new(
        dictionary! {
            "Type" => "XObject",
            "Subtype" => "Image",
            "Width" => 2,
            "Height" => 2,
            "ColorSpace" => "DeviceGray",
            "BitsPerComponent" => 8,
        },
        vec![0, 255, 255, 0],
    ));
    let resources = dictionary! {
        "XObject" => dictionary! { "Scan" => image_id },
    };
    add_single_page(
        &mut document,
        pages_id,
        resources,
        b"q 468 0 0 648 72 72 cm /Scan Do Q".to_vec(),
    );
    finish_document(document, pages_id, path)
}

fn write_embedded_font_pdf(
    path: &Path,
    font_bytes: &[u8],
    base_font: &str,
) -> Result<(), Box<dyn Error>> {
    let mut document = Document::with_version("1.7");
    let pages_id = document.new_object_id();
    let font_file_id = document.add_object(Stream::new(
        dictionary! { "Length1" => font_bytes.len() as i64 },
        font_bytes.to_vec(),
    ));
    let descriptor_id = document.add_object(dictionary! {
        "Type" => "FontDescriptor",
        "FontName" => Object::Name(base_font.as_bytes().to_vec()),
        "Flags" => 32,
        "FontBBox" => vec![(-665).into(), (-325).into(), 2000.into(), 1056.into()],
        "ItalicAngle" => 0,
        "Ascent" => 905,
        "Descent" => -212,
        "CapHeight" => 728,
        "StemV" => 80,
        "FontFile2" => font_file_id,
    });
    let widths: Vec<Object> = (32..=126).map(|_| 600.into()).collect();
    let font_id = document.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "TrueType",
        "BaseFont" => Object::Name(base_font.as_bytes().to_vec()),
        "FirstChar" => 32,
        "LastChar" => 126,
        "Widths" => widths,
        "Encoding" => "WinAnsiEncoding",
        "FontDescriptor" => descriptor_id,
    });
    let resources = dictionary! { "Font" => dictionary! { "F1" => font_id } };
    add_single_page(
        &mut document,
        pages_id,
        resources,
        b"BT /F1 18 Tf 72 700 Td (Private embedded font case) Tj ET".to_vec(),
    );
    finish_document(document, pages_id, path)
}

fn add_single_page(
    document: &mut Document,
    pages_id: ObjectId,
    resources: Dictionary,
    content: Vec<u8>,
) {
    let resources_id = document.add_object(resources);
    let content_id = document.add_object(Stream::new(dictionary! {}, content));
    let page_id = document.add_object(dictionary! {
        "Type" => "Page",
        "Parent" => pages_id,
        "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()],
        "Resources" => resources_id,
        "Contents" => content_id,
    });
    document.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => vec![Object::Reference(page_id)],
            "Count" => 1,
        }),
    );
}

fn finish_document(
    mut document: Document,
    pages_id: ObjectId,
    path: &Path,
) -> Result<(), Box<dyn Error>> {
    let catalog_id = document.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    document.trailer.set("Root", catalog_id);
    document.save(path)?;
    Ok(())
}
