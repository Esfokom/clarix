#[test]
fn facade_links_all_phase_zero_crates() {
    assert_eq!(clarix_editing_core::EDITOR_CORE_SCHEMA_VERSION, 1);
    assert_eq!(clarix_pdf_adapter::PDF_ADAPTER_SCHEMA_VERSION, 1);
    assert_eq!(clarix_agent_core::AGENT_CORE_SCHEMA_VERSION, 1);
}
