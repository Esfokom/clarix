use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use ttf_parser::{name_id, Face, Permissions};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledFontRequest {
    pub preferred_family: String,
    pub weight: u16,
    pub italic: bool,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledFontFace {
    pub path: PathBuf,
    pub family: String,
    pub postscript_name: String,
    pub bytes_sha256: String,
    pub weight: u16,
    pub italic: bool,
}

#[derive(Debug, Clone)]
pub struct InstalledFontCatalog {
    roots: Vec<PathBuf>,
}

impl InstalledFontCatalog {
    pub fn windows() -> Self {
        let windows = std::env::var_os("WINDIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(r"C:\Windows"));
        let mut roots = vec![windows.join("Fonts")];
        if let Some(local_app_data) = std::env::var_os("LOCALAPPDATA") {
            roots.push(
                PathBuf::from(local_app_data)
                    .join("Microsoft")
                    .join("Windows")
                    .join("Fonts"),
            );
        }
        Self::from_roots(roots)
    }

    pub fn from_roots(roots: impl IntoIterator<Item = PathBuf>) -> Self {
        let mut roots = roots.into_iter().collect::<Vec<_>>();
        roots.sort();
        roots.dedup();
        Self { roots }
    }

    pub fn propose(&self, request: &InstalledFontRequest) -> Option<InstalledFontFace> {
        if request.text.is_empty() || !request.text.chars().all(win_ansi_byte) {
            return None;
        }
        let mut candidates = self
            .font_paths()
            .into_iter()
            .filter_map(|path| inspect_font(&path, request))
            .collect::<Vec<_>>();
        candidates.sort_by(|left, right| {
            font_score(right, request)
                .cmp(&font_score(left, request))
                .then_with(|| left.path.cmp(&right.path))
        });
        candidates.into_iter().next()
    }

    fn font_paths(&self) -> Vec<PathBuf> {
        let mut output = Vec::new();
        for root in &self.roots {
            let Ok(entries) = std::fs::read_dir(root) else {
                continue;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                if path
                    .extension()
                    .and_then(|extension| extension.to_str())
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("ttf"))
                {
                    output.push(path);
                }
            }
        }
        output.sort();
        output.dedup();
        output
    }
}

fn inspect_font(path: &Path, request: &InstalledFontRequest) -> Option<InstalledFontFace> {
    let bytes = std::fs::read(path).ok()?;
    let face = Face::parse(&bytes, 0).ok()?;
    if face.tables().glyf.is_none()
        || face.is_variable()
        || !face.is_outline_embedding_allowed()
        || !matches!(
            face.permissions(),
            Some(Permissions::Installable | Permissions::Editable)
        )
        || !request
            .text
            .chars()
            .all(|character| face.glyph_index(character).is_some())
    {
        return None;
    }
    let family = font_name(&face, name_id::TYPOGRAPHIC_FAMILY)
        .or_else(|| font_name(&face, name_id::FAMILY))?;
    let postscript_name = font_name(&face, name_id::POST_SCRIPT_NAME)?;
    Some(InstalledFontFace {
        path: path.to_owned(),
        family,
        postscript_name,
        bytes_sha256: format!("{:x}", Sha256::digest(&bytes)),
        weight: face.weight().to_number(),
        italic: face.is_italic(),
    })
}

fn font_name(face: &Face<'_>, id: u16) -> Option<String> {
    face.names()
        .into_iter()
        .filter(|name| name.name_id == id)
        .filter_map(|name| name.to_string())
        .find(|name| !name.trim().is_empty())
}

fn font_score(face: &InstalledFontFace, request: &InstalledFontRequest) -> i64 {
    let requested = normalize_family(&request.preferred_family);
    let candidate = normalize_family(&face.family);
    let family = if requested == candidate { 100_000 } else { 0 };
    let weight = 10_000_i64 - i64::from(face.weight.abs_diff(request.weight));
    let italic = if face.italic == request.italic {
        1_000
    } else {
        0
    };
    family + weight + italic
}

fn normalize_family(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

pub(crate) fn win_ansi_byte(character: char) -> bool {
    matches!(
        character as u32,
        0x20..=0x7e
            | 0xa0..=0xff
            | 0x20ac
            | 0x201a
            | 0x0192
            | 0x201e
            | 0x2026
            | 0x2020
            | 0x2021
            | 0x02c6
            | 0x2030
            | 0x0160
            | 0x2039
            | 0x0152
            | 0x017d
            | 0x2018
            | 0x2019
            | 0x201c
            | 0x201d
            | 0x2022
            | 0x2013
            | 0x2014
            | 0x02dc
            | 0x2122
            | 0x0161
            | 0x203a
            | 0x0153
            | 0x017e
            | 0x0178
    )
}
