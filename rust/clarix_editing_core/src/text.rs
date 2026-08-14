use serde::{Deserialize, Serialize};
use thiserror::Error;

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
    #[error("text is too long to address with a 32-bit UTF-16 offset")]
    LengthOverflow,
}
