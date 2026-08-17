use regex::Regex;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use unicode_normalization::UnicodeNormalization;
use unicode_segmentation::UnicodeSegmentation;

use crate::{DocumentModel, DocumentObject, DocumentRevision, ObjectId, PageId};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SearchMode {
    Exact,
    CaseFolded,
    Normalized,
    Regex,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchRequest {
    pub query: String,
    pub mode: SearchMode,
    pub whole_word: bool,
    pub offset: u32,
    pub limit: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextRangeRef {
    pub object_id: ObjectId,
    pub page_id: PageId,
    pub page_number: u32,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub quoted_text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchPage {
    pub revision: DocumentRevision,
    pub matches: Vec<TextRangeRef>,
    pub total_matches: u32,
    pub indexed_pages: u32,
    pub page_count: u32,
    pub is_complete: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum SearchError {
    #[error("search query must not be empty")]
    EmptyQuery,
    #[error("search query must not exceed 4096 bytes")]
    QueryTooLong,
    #[error("search limit must be between 1 and 500")]
    InvalidLimit,
    #[error("invalid regular expression: {0}")]
    InvalidRegex(String),
    #[error("search result count exceeds supported range")]
    ResultOverflow,
}

#[derive(Debug, Clone)]
struct IndexedText {
    object_id: ObjectId,
    page_id: PageId,
    page_number: u32,
    text: String,
}

#[derive(Debug, Clone)]
pub struct SearchIndex {
    revision: DocumentRevision,
    page_count: u32,
    entries: Vec<IndexedText>,
}

impl SearchIndex {
    pub fn from_document(document: &DocumentModel) -> Self {
        let mut entries = Vec::new();
        for page in &document.pages {
            for object in &page.objects {
                if let DocumentObject::Text(text) = object {
                    entries.push(IndexedText {
                        object_id: object.id(),
                        page_id: page.id,
                        page_number: page.page_number,
                        text: text.text.clone(),
                    });
                }
            }
        }
        Self {
            revision: document.revision,
            page_count: document.pages.len() as u32,
            entries,
        }
    }

    pub fn search(&self, request: SearchRequest) -> Result<SearchPage, SearchError> {
        validate_request(&request)?;
        let mut matches = Vec::new();
        let query = match request.mode {
            SearchMode::Exact | SearchMode::Regex => request.query.clone(),
            SearchMode::CaseFolded => fold(&request.query),
            SearchMode::Normalized => normalize(&request.query),
        };
        let regex = if request.mode == SearchMode::Regex {
            Some(Regex::new(&query).map_err(|error| SearchError::InvalidRegex(error.to_string()))?)
        } else {
            None
        };

        for entry in &self.entries {
            let ranges = match request.mode {
                SearchMode::Exact => find_ranges(&entry.text, &query),
                SearchMode::CaseFolded => find_mapped_ranges(&entry.text, &query, fold),
                SearchMode::Normalized => find_mapped_ranges(&entry.text, &query, normalize),
                SearchMode::Regex => regex
                    .as_ref()
                    .expect("regex is created for regex search")
                    .find_iter(&entry.text)
                    .filter(|found| !found.is_empty())
                    .map(|found| found.start()..found.end())
                    .collect(),
            };
            for range in ranges {
                if request.whole_word && !is_whole_word(&entry.text, &range) {
                    continue;
                }
                matches.push(TextRangeRef {
                    object_id: entry.object_id,
                    page_id: entry.page_id,
                    page_number: entry.page_number,
                    start_utf16: utf16_offset(&entry.text, range.start),
                    end_utf16: utf16_offset(&entry.text, range.end),
                    quoted_text: entry.text[range].to_owned(),
                });
            }
        }

        let total_matches =
            u32::try_from(matches.len()).map_err(|_| SearchError::ResultOverflow)?;
        let start = usize::try_from(request.offset).unwrap_or(usize::MAX);
        let end = start
            .saturating_add(request.limit as usize)
            .min(matches.len());
        let page_matches = if start >= matches.len() {
            Vec::new()
        } else {
            matches.drain(start..end).collect()
        };
        Ok(SearchPage {
            revision: self.revision,
            matches: page_matches,
            total_matches,
            indexed_pages: self.page_count,
            page_count: self.page_count,
            is_complete: true,
        })
    }
}

fn validate_request(request: &SearchRequest) -> Result<(), SearchError> {
    if request.query.is_empty() {
        return Err(SearchError::EmptyQuery);
    }
    if request.query.len() > 4096 {
        return Err(SearchError::QueryTooLong);
    }
    if !(1..=500).contains(&request.limit) {
        return Err(SearchError::InvalidLimit);
    }
    Ok(())
}

fn find_ranges(text: &str, query: &str) -> Vec<std::ops::Range<usize>> {
    text.match_indices(query)
        .map(|(start, found)| start..start + found.len())
        .collect()
}

fn find_mapped_ranges(
    text: &str,
    query: &str,
    transform: fn(&str) -> String,
) -> Vec<std::ops::Range<usize>> {
    let mapped = transformed_with_source_ranges(text, transform);
    mapped
        .value
        .match_indices(query)
        .filter_map(|(start, found)| mapped.source_range(start..start + found.len()))
        .collect()
}

#[derive(Debug)]
struct TransformedText {
    value: String,
    source_ranges: Vec<(std::ops::Range<usize>, std::ops::Range<usize>)>,
}

impl TransformedText {
    fn source_range(&self, range: std::ops::Range<usize>) -> Option<std::ops::Range<usize>> {
        let first = self.source_ranges.iter().find(|(transformed, _)| {
            transformed.start <= range.start && range.start < transformed.end
        })?;
        let last = self.source_ranges.iter().rev().find(|(transformed, _)| {
            transformed.start < range.end && range.end <= transformed.end
        })?;
        Some(first.1.start..last.1.end)
    }
}

fn transformed_with_source_ranges(text: &str, transform: fn(&str) -> String) -> TransformedText {
    let mut value = String::new();
    let mut source_ranges = Vec::new();
    for (start, grapheme) in text.grapheme_indices(true) {
        let transformed_start = value.len();
        value.push_str(&transform(grapheme));
        let transformed_end = value.len();
        if transformed_start != transformed_end {
            source_ranges.push((
                transformed_start..transformed_end,
                start..start + grapheme.len(),
            ));
        }
    }
    TransformedText {
        value,
        source_ranges,
    }
}

fn fold(value: &str) -> String {
    value.chars().flat_map(char::to_lowercase).collect()
}

fn normalize(value: &str) -> String {
    value.nfkc().flat_map(char::to_lowercase).collect()
}

fn utf16_offset(text: &str, byte_offset: usize) -> u32 {
    text[..byte_offset].encode_utf16().count() as u32
}

fn is_whole_word(text: &str, range: &std::ops::Range<usize>) -> bool {
    let before = text[..range.start].chars().next_back();
    let after = text[range.end..].chars().next();
    !before.is_some_and(is_word_character) && !after.is_some_and(is_word_character)
}

fn is_word_character(character: char) -> bool {
    character == '_' || character.is_alphanumeric()
}
