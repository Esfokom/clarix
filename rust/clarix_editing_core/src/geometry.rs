use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct PdfBox {
    pub left: f64,
    pub bottom: f64,
    pub right: f64,
    pub top: f64,
}

impl PdfBox {
    pub fn new(left: f64, bottom: f64, right: f64, top: f64) -> Result<Self, GeometryError> {
        if ![left, bottom, right, top].into_iter().all(f64::is_finite) {
            return Err(GeometryError::NonFinite);
        }
        if right < left || top < bottom {
            return Err(GeometryError::InvertedBounds);
        }
        Ok(Self {
            left,
            bottom,
            right,
            top,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct AffineTransform {
    pub a: f64,
    pub b: f64,
    pub c: f64,
    pub d: f64,
    pub e: f64,
    pub f: f64,
}

impl AffineTransform {
    pub const IDENTITY: Self = Self {
        a: 1.0,
        b: 0.0,
        c: 0.0,
        d: 1.0,
        e: 0.0,
        f: 0.0,
    };

    pub fn new(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) -> Result<Self, GeometryError> {
        if ![a, b, c, d, e, f].into_iter().all(f64::is_finite) {
            return Err(GeometryError::NonFinite);
        }
        Ok(Self { a, b, c, d, e, f })
    }

    pub fn determinant(self) -> f64 {
        self.a * self.d - self.b * self.c
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
pub enum GeometryError {
    #[error("geometry contains a non-finite value")]
    NonFinite,
    #[error("geometry bounds are inverted")]
    InvertedBounds,
}
