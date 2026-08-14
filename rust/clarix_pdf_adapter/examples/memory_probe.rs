use std::{env, fs, path::PathBuf};

use clarix_pdf_adapter::{PdfImporter, PdfOxideImporter, SourceRef};
use serde::Serialize;
use sysinfo::{get_current_pid, ProcessesToUpdate, System};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MemoryProbeReport {
    schema_version: u32,
    iterations: usize,
    warmup_bytes: u64,
    peak_bytes: u64,
    final_bytes: u64,
    tail_slope_bytes_per_iteration: f64,
}

fn argument(name: &str) -> Option<String> {
    let arguments: Vec<_> = env::args().collect();
    arguments
        .iter()
        .position(|argument| argument == name)
        .and_then(|index| arguments.get(index + 1))
        .cloned()
}

fn valid_fixtures() -> Vec<PathBuf> {
    let corpus = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("test_fixtures/editing_corpus/generated");
    let mut fixtures: Vec<_> = fs::read_dir(corpus)
        .expect("generated corpus must exist")
        .map(|entry| entry.expect("corpus entry must be readable").path())
        .filter(|path| {
            path.extension().and_then(|value| value.to_str()) == Some("pdf")
                && path.file_name().and_then(|value| value.to_str()) != Some("malformed.pdf")
        })
        .collect();
    fixtures.sort();
    fixtures
}

fn tail_slope(samples: &[u64]) -> f64 {
    let tail = &samples[samples.len().saturating_sub(50)..];
    if tail.len() < 2 {
        return 0.0;
    }
    let count = tail.len() as f64;
    let mean_x = (tail.len() - 1) as f64 / 2.0;
    let mean_y = tail.iter().map(|value| *value as f64).sum::<f64>() / count;
    let mut numerator = 0.0;
    let mut denominator = 0.0;
    for (index, value) in tail.iter().enumerate() {
        let x_delta = index as f64 - mean_x;
        numerator += x_delta * (*value as f64 - mean_y);
        denominator += x_delta * x_delta;
    }
    if denominator == 0.0 {
        0.0
    } else {
        numerator / denominator
    }
}

fn working_set(system: &mut System) -> u64 {
    let pid = get_current_pid().expect("current process id must be available");
    system.refresh_processes(ProcessesToUpdate::Some(&[pid]), true);
    system
        .process(pid)
        .expect("current process must be observable")
        .memory()
}

fn main() {
    let iterations = argument("--iterations")
        .map(|value| {
            value
                .parse::<usize>()
                .expect("iterations must be an integer")
        })
        .unwrap_or(100);
    assert!(iterations > 0, "iterations must be positive");
    let output = argument("--output").expect("--output <path> is required");
    let fixtures = valid_fixtures();
    let importer = PdfOxideImporter;
    let mut system = System::new();
    let mut samples = Vec::with_capacity(iterations);

    for _ in 0..iterations {
        for path in &fixtures {
            let source = SourceRef::from_path(path).expect("fixture fingerprint must load");
            let document = importer
                .inspect_document(&source)
                .expect("fixture document must import");
            for page_number in 1..=document.page_count {
                let page = importer
                    .inspect_page(&source, page_number)
                    .expect("fixture page must import");
                drop(page);
            }
        }
        samples.push(working_set(&mut system));
    }

    let report = MemoryProbeReport {
        schema_version: 1,
        iterations,
        warmup_bytes: samples[0],
        peak_bytes: *samples.iter().max().unwrap(),
        final_bytes: *samples.last().unwrap(),
        tail_slope_bytes_per_iteration: tail_slope(&samples),
    };
    let output = PathBuf::from(output);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).expect("output directory must be creatable");
    }
    fs::write(
        output,
        format!("{}\n", serde_json::to_string_pretty(&report).unwrap()),
    )
    .expect("memory report must be writable");
}
