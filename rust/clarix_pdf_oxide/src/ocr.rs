use image::{DynamicImage, RgbaImage};
use ocr_rs::{DetOptions, OcrEngine, OcrEngineConfig, RecOptions};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrBox {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrWord {
    pub text: String,
    pub confidence: f32,
    pub bbox: OcrBox,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrPageResult {
    pub page_number: usize,
    pub width: u32,
    pub height: u32,
    pub words: Vec<OcrWord>,
}

pub struct OcrSession {
    engine: OcrEngine,
}

impl OcrSession {
    pub fn open(
        detection_model: String,
        recognition_model: String,
        charset: String,
        threads: usize,
    ) -> Result<Self, String> {
        let config = OcrEngineConfig::new()
            .with_threads(threads.clamp(1, 8))
            .with_det_options(DetOptions::new().with_max_side_len(1920))
            .with_rec_options(RecOptions::new().with_min_score(0.5).with_batch_size(16));
        let engine = OcrEngine::new(detection_model, recognition_model, charset, Some(config))
            .map_err(|error| error.to_string())?;
        Ok(Self { engine })
    }

    pub fn recognize_bgra(
        &self,
        page_number: usize,
        pixels: Vec<u8>,
        width: u32,
        height: u32,
        stride: u32,
    ) -> Result<OcrPageResult, String> {
        let row_bytes = width
            .checked_mul(4)
            .ok_or_else(|| "OCR image width overflowed.".to_string())?;
        if stride < row_bytes {
            return Err("OCR stride is smaller than a BGRA row.".to_string());
        }
        let required = stride as usize * height as usize;
        if pixels.len() < required {
            return Err("OCR pixel buffer is shorter than the declared image.".to_string());
        }
        let packed = if stride == row_bytes {
            pixels[..required].to_vec()
        } else {
            let mut output = Vec::with_capacity(row_bytes as usize * height as usize);
            for row in 0..height as usize {
                let start = row * stride as usize;
                output.extend_from_slice(&pixels[start..start + row_bytes as usize]);
            }
            output
        };
        let mut rgba = packed;
        for pixel in rgba.chunks_exact_mut(4) {
            pixel.swap(0, 2);
        }
        let image = RgbaImage::from_raw(width, height, rgba)
            .ok_or_else(|| "Could not construct the OCR image.".to_string())?;
        let results = self
            .engine
            .recognize(&DynamicImage::ImageRgba8(image))
            .map_err(|error| error.to_string())?;
        let words = results
            .into_iter()
            .map(|item| OcrWord {
                text: item.text,
                confidence: item.confidence,
                bbox: OcrBox {
                    left: item.bbox.rect.left() as f32,
                    top: item.bbox.rect.top() as f32,
                    right: item.bbox.rect.right() as f32,
                    bottom: item.bbox.rect.bottom() as f32,
                },
            })
            .collect();
        Ok(OcrPageResult {
            page_number,
            width,
            height,
            words,
        })
    }
}
