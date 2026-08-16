use serde::{Deserialize, Serialize};
use thiserror::Error;
use unicode_segmentation::UnicodeSegmentation;

use crate::{ObjectId, PdfBox};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Utf16Range {
    pub start: u32,
    pub end: u32,
}

impl Utf16Range {
    pub fn new(start: u32, end: u32) -> Result<Self, TextRangeError> {
        if end < start {
            return Err(TextRangeError::Reversed { start, end });
        }
        Ok(Self { start, end })
    }

    pub const fn len(self) -> u32 {
        self.end - self.start
    }

    pub const fn is_empty(self) -> bool {
        self.start == self.end
    }
}

pub fn validate_utf16_range(text: &str, range: Utf16Range) -> Result<(), TextRangeError> {
    let mut boundaries = Vec::with_capacity(text.chars().count() + 1);
    let mut offset = 0_u32;
    boundaries.push(offset);
    for character in text.chars() {
        offset = offset
            .checked_add(character.len_utf16() as u32)
            .ok_or(TextRangeError::LengthOverflow)?;
        boundaries.push(offset);
    }
    if range.end > offset {
        return Err(TextRangeError::OutOfBounds {
            end: range.end,
            length: offset,
        });
    }
    if !boundaries.contains(&range.start) || !boundaries.contains(&range.end) {
        return Err(TextRangeError::SplitsSurrogatePair);
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TextAffinity {
    Upstream,
    Downstream,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextAnchor {
    pub object_id: ObjectId,
    pub utf16_offset: u32,
    pub affinity: TextAffinity,
}

impl TextAnchor {
    pub fn new(
        object_id: ObjectId,
        text: &str,
        utf16_offset: u32,
        affinity: TextAffinity,
    ) -> Result<Self, TextRangeError> {
        let byte_offset =
            utf16_range_to_byte_range(text, Utf16Range::new(utf16_offset, utf16_offset)?)?.start;
        let is_grapheme_boundary = byte_offset == text.len()
            || text
                .grapheme_indices(true)
                .any(|(boundary, _)| boundary == byte_offset);
        if !is_grapheme_boundary {
            return Err(TextRangeError::SplitsGraphemeCluster);
        }
        Ok(Self {
            object_id,
            utf16_offset,
            affinity,
        })
    }
}

pub(crate) fn utf16_range_to_byte_range(
    text: &str,
    range: Utf16Range,
) -> Result<std::ops::Range<usize>, TextRangeError> {
    validate_utf16_range(text, range)?;
    let mut utf16_offset = 0_u32;
    let mut start = None;
    let mut end = None;
    for (byte_offset, character) in text.char_indices() {
        if utf16_offset == range.start {
            start = Some(byte_offset);
        }
        if utf16_offset == range.end {
            end = Some(byte_offset);
            break;
        }
        utf16_offset += character.len_utf16() as u32;
    }
    if utf16_offset == range.start {
        start.get_or_insert(text.len());
    }
    if utf16_offset == range.end {
        end.get_or_insert(text.len());
    }
    Ok(start.expect("validated start boundary")..end.expect("validated end boundary"))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextStyle {
    pub font_family: Option<String>,
    pub font_size: f64,
    pub font_weight: u16,
    pub italic: bool,
    pub color_rgba: [u8; 4],
}

impl Default for TextStyle {
    fn default() -> Self {
        Self {
            font_family: None,
            font_size: 12.0,
            font_weight: 400,
            italic: false,
            color_rgba: [0, 0, 0, 255],
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FontSource {
    Embedded,
    Installed,
    ApprovedFallback,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FontRef {
    pub postscript_name: String,
    pub bytes_sha256: String,
    pub asset_id: Option<String>,
    pub source: FontSource,
    pub embeddable: bool,
}

impl FontRef {
    pub fn is_valid(&self) -> bool {
        !self.postscript_name.trim().is_empty()
            && self.bytes_sha256.len() == 64
            && self
                .bytes_sha256
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TextAlignment {
    Left,
    Center,
    Right,
    Justify,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WritingDirection {
    LeftToRight,
    RightToLeft,
    TopToBottom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OverflowPolicy {
    Reject,
    IncreaseBounds,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ParagraphStyle {
    pub alignment: TextAlignment,
    pub line_spacing: f64,
}

impl Default for ParagraphStyle {
    fn default() -> Self {
        Self {
            alignment: TextAlignment::Left,
            line_spacing: 1.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextLayoutRecipe {
    pub paragraph: ParagraphStyle,
    pub baseline: f64,
    pub line_height: f64,
    pub character_spacing: f64,
    pub horizontal_scale: f64,
    pub direction: WritingDirection,
    pub overflow: OverflowPolicy,
}

impl Default for TextLayoutRecipe {
    fn default() -> Self {
        Self {
            paragraph: ParagraphStyle::default(),
            baseline: 0.0,
            line_height: 12.0,
            character_spacing: 0.0,
            horizontal_scale: 1.0,
            direction: WritingDirection::LeftToRight,
            overflow: OverflowPolicy::Reject,
        }
    }
}

impl TextLayoutRecipe {
    pub fn is_valid(&self) -> bool {
        self.baseline.is_finite()
            && self.line_height.is_finite()
            && self.line_height > 0.0
            && self.character_spacing.is_finite()
            && self.horizontal_scale.is_finite()
            && self.horizontal_scale > 0.0
            && self.paragraph.line_spacing.is_finite()
            && self.paragraph.line_spacing > 0.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceGlyph {
    pub utf16_start: u32,
    pub utf16_end: u32,
    pub character_code: u32,
    pub glyph_id: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextCharacterBox {
    pub range: Utf16Range,
    pub bounds: PdfBox,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextRun {
    pub range: Utf16Range,
    pub style: TextStyle,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum TextRangeError {
    #[error("UTF-16 range is reversed: {start}..{end}")]
    Reversed { start: u32, end: u32 },
    #[error("UTF-16 range ends at {end}, beyond text length {length}")]
    OutOfBounds { end: u32, length: u32 },
    #[error("UTF-16 range splits a surrogate pair")]
    SplitsSurrogatePair,
    #[error("UTF-16 offset splits a grapheme cluster")]
    SplitsGraphemeCluster,
    #[error("text is too long to address with a 32-bit UTF-16 offset")]
    LengthOverflow,
}

impl TextRangeError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::SplitsGraphemeCluster => "invalid_grapheme_boundary",
            Self::Reversed { .. }
            | Self::OutOfBounds { .. }
            | Self::SplitsSurrogatePair
            | Self::LengthOverflow => "invalid_text_boundary",
        }
    }
}
