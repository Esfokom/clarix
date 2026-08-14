use std::{path::PathBuf, process::Command};

use serde_json::Value;

#[test]
fn workspace_dependency_direction_and_ffi_boundary_are_enforced() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../Cargo.toml");
    let output = Command::new(env!("CARGO"))
        .args([
            "metadata",
            "--no-deps",
            "--format-version",
            "1",
            "--manifest-path",
        ])
        .arg(manifest)
        .output()
        .expect("cargo metadata must run");
    assert!(output.status.success());
    let metadata: Value = serde_json::from_slice(&output.stdout).unwrap();
    let packages = metadata["packages"].as_array().unwrap();

    let package = |name: &str| {
        packages
            .iter()
            .find(|package| package["name"] == name)
            .unwrap_or_else(|| panic!("missing workspace package {name}"))
    };
    let dependency_names = |package: &Value| -> Vec<String> {
        package["dependencies"]
            .as_array()
            .unwrap()
            .iter()
            .map(|dependency| dependency["name"].as_str().unwrap().to_owned())
            .collect()
    };

    let core_dependencies = dependency_names(package("clarix_editing_core"));
    for forbidden in [
        "flutter_rust_bridge",
        "pdf_oxide",
        "lopdf",
        "clarix_pdf_adapter",
        "clarix_agent_core",
        "clarix_pdf_oxide",
    ] {
        assert!(
            !core_dependencies.iter().any(|name| name == forbidden),
            "editing core depends on forbidden crate {forbidden}"
        );
    }

    let agent_dependencies = dependency_names(package("clarix_agent_core"));
    assert!(agent_dependencies
        .iter()
        .any(|name| name == "clarix_editing_core"));
    for forbidden in ["clarix_pdf_adapter", "clarix_pdf_oxide"] {
        assert!(
            !agent_dependencies.iter().any(|name| name == forbidden),
            "agent core depends on forbidden crate {forbidden}"
        );
    }

    let mut facade_cdylib_found = false;
    for workspace_package in packages {
        for target in workspace_package["targets"].as_array().unwrap() {
            let crate_types = target["crate_types"].as_array().unwrap();
            if crate_types.iter().any(|crate_type| crate_type == "cdylib") {
                assert_eq!(workspace_package["name"], "clarix_pdf_oxide");
                facade_cdylib_found = true;
            }
        }
    }
    assert!(
        facade_cdylib_found,
        "facade must expose the workspace cdylib"
    );
}
