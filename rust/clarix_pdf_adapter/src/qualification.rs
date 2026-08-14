use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::CapabilityReport;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QualificationCaseResult {
    pub case_id: String,
    pub source_sha256: String,
    pub adapter_id: String,
    pub duration_micros: u64,
    pub page_count: u32,
    pub object_counts: BTreeMap<String, u32>,
    pub capabilities: CapabilityReport,
    pub warnings: Vec<String>,
    pub stable_error_code: Option<String>,
}
