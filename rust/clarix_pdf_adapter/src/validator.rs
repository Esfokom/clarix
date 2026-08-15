use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::{PdfAdapterError, PdfValidator, SaveExpectation, ValidationReport};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationFailure {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DetailedValidationReport {
    pub valid: bool,
    pub page_count: u32,
    pub failures: Vec<ValidationFailure>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Default, Clone, Copy)]
pub struct IndependentPdfValidator;

impl IndependentPdfValidator {
    pub fn validate_document(
        &self,
        output: &Path,
        expected_page_count: u32,
    ) -> Result<DetailedValidationReport, PdfAdapterError> {
        if !output.exists() {
            return Err(PdfAdapterError::Io(format!(
                "validation target does not exist: {}",
                output.display()
            )));
        }
        let document = match pdf_oxide::PdfDocument::open(output) {
            Ok(document) => document,
            Err(error) => {
                return Ok(DetailedValidationReport {
                    valid: false,
                    page_count: 0,
                    failures: vec![ValidationFailure {
                        code: "pdf_unreadable".into(),
                        message: error.to_string(),
                    }],
                    warnings: Vec::new(),
                });
            }
        };
        let page_count = document
            .page_count()
            .map_err(|error| PdfAdapterError::InvalidPdf(error.to_string()))?
            as u32;
        let mut failures = Vec::new();
        if page_count != expected_page_count {
            failures.push(ValidationFailure {
                code: "page_count_changed".into(),
                message: format!(
                    "expected {expected_page_count} pages but independently read {page_count}"
                ),
            });
        }
        Ok(DetailedValidationReport {
            valid: failures.is_empty(),
            page_count,
            failures,
            warnings: Vec::new(),
        })
    }
}

impl PdfValidator for IndependentPdfValidator {
    fn validate(
        &self,
        output: &Path,
        expectation: &SaveExpectation,
    ) -> Result<ValidationReport, PdfAdapterError> {
        let report = self.validate_document(output, expectation.page_count)?;
        Ok(ValidationReport {
            valid: report.valid,
            page_count: report.page_count,
            warnings: report
                .failures
                .into_iter()
                .map(|failure| format!("{}: {}", failure.code, failure.message))
                .collect(),
        })
    }
}

impl clarix_editing_core::ValidationPort for IndependentPdfValidator {
    fn validate(
        &self,
        output: &Path,
        expectation: &clarix_editing_core::ValidationExpectation,
    ) -> Result<clarix_editing_core::ValidationReport, clarix_editing_core::SaveError> {
        self.validate_document(output, expectation.page_count)
            .map(|report| clarix_editing_core::ValidationReport {
                valid: report.valid,
                warnings: report
                    .failures
                    .into_iter()
                    .map(|failure| format!("{}: {}", failure.code, failure.message))
                    .collect(),
            })
            .map_err(|error| {
                clarix_editing_core::SaveError::new(
                    clarix_editing_core::SaveStage::ValidateTemp,
                    error.code(),
                    error.to_string(),
                )
            })
    }
}
