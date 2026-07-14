# Phase 1 Reader Performance Gate

## Measurement profile

Run on a Windows x64 release build with logging enabled and network disabled after required models are installed. Record the device CPU, RAM, GPU, Flutter version, Rust toolchain, PDF fixture hash, and model IDs with each result.

## Required measurements

| Area | Metric | Gate |
|---|---|---|
| Open | First page visible | Record median and p95 for small, medium, and large PDFs |
| Interaction | Mouse-anchored zoom error | At most 1 logical pixel after the transform settles |
| Interaction | Pan/zoom frame time | No full workspace rebuild for controller matrix updates; investigate p95 over 16.7 ms |
| Rendering | pdfrx image cache | Configured at 64 MiB or less |
| Extraction | Text cache | 32 pages and 8 MiB per Rust session |
| Indexing | Batch size | At most 32 chunks passed from extraction to persistence |
| OCR | Pending rendered pages | At most 2 once the generated native adapter is enabled |
| OCR | Accuracy and latency | PP-OCRv6 small must be no worse in CER/WER and faster than the recorded Tesseract baseline on the Clarix corpus |
| Lifecycle | Repeated use | Working set must not increase monotonically over 10 open/scroll/close cycles |

## OCR benchmark corpus

Use born-digital control pages plus scanned pages containing English, mixed Latin scripts, rotation, low contrast, tables, and 150/200/300 DPI inputs. Record model load time, per-page median/p95, peak working set, CER, WER, and bounding-box intersection quality.

Tesseract is a benchmark-only dependency. PP-OCRv6 model files and character dictionaries are installed locally and are never bundled with credentials.
