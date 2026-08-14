use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

const CLARIX_NAMESPACE: Uuid = Uuid::from_bytes([
    0x63, 0x6c, 0x61, 0x72, 0x69, 0x78, 0x45, 0x44, 0x91, 0x54, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
]);

macro_rules! uuid_id {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
        #[serde(transparent)]
        pub struct $name(Uuid);

        impl $name {
            pub fn new() -> Self {
                Self(Uuid::new_v4())
            }

            pub fn from_source_key(source_key: &str) -> Self {
                Self(Uuid::new_v5(&CLARIX_NAMESPACE, source_key.as_bytes()))
            }
        }

        impl Default for $name {
            fn default() -> Self {
                Self::new()
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                self.0.hyphenated().fmt(formatter)
            }
        }

        impl FromStr for $name {
            type Err = uuid::Error;

            fn from_str(value: &str) -> Result<Self, Self::Err> {
                Uuid::parse_str(value).map(Self)
            }
        }
    };
}

uuid_id!(DocumentId);
uuid_id!(PageId);
uuid_id!(ObjectId);
uuid_id!(SessionId);
uuid_id!(CommandId);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct DocumentRevision(u64);

impl DocumentRevision {
    pub const INITIAL: Self = Self(0);

    pub const fn value(self) -> u64 {
        self.0
    }

    pub fn next(self) -> Result<Self, RevisionOverflow> {
        self.0.checked_add(1).map(Self).ok_or(RevisionOverflow)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
#[error("document revision overflow")]
pub struct RevisionOverflow;
