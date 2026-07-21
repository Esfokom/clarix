use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};
use serde::{Deserialize, Serialize};
use std::fmt::{Display, Formatter};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use usearch::{new_index, Index, IndexOptions, MetricKind, ScalarKind};

const MANIFEST_VERSION: u32 = 1;
const MODEL_ID: &str = "sentence-transformers/all-MiniLM-L6-v2";
const MODEL_DIMENSIONS: usize = 384;
const EMBEDDING_BATCH_SIZE: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RagChunk {
    pub id: String,
    pub text: String,
}

impl RagChunk {
    pub fn new(id: impl Into<String>, text: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            text: text.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RagIndexPaths {
    pub index_path: PathBuf,
    pub manifest_path: PathBuf,
}

impl RagIndexPaths {
    pub fn for_document(root: impl AsRef<Path>, document_fingerprint: &str) -> Self {
        let stem = safe_file_stem(document_fingerprint);
        let root = root.as_ref();
        Self {
            index_path: root.join(format!("{stem}.usearch")),
            manifest_path: root.join(format!("{stem}.manifest.json")),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RagSearchResult {
    pub chunk_id: String,
    pub score: f32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RagIndexOutcome {
    Built,
    Loaded,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RagError {
    Embedding(String),
    Storage(String),
    RebuildRequired { reason: String },
}

impl Display for RagError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Embedding(message) => write!(formatter, "embedding failed: {message}"),
            Self::Storage(message) => write!(formatter, "RAG storage failed: {message}"),
            Self::RebuildRequired { reason } => {
                write!(formatter, "RAG index must be rebuilt: {reason}")
            }
        }
    }
}

impl std::error::Error for RagError {}

pub trait EmbeddingBackend: Send + Sync {
    fn model_id(&self) -> &str;
    fn dimensions(&self) -> usize;
    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, RagError>;
}

pub struct FastEmbedBackend {
    model: Mutex<TextEmbedding>,
}

impl FastEmbedBackend {
    pub fn new(cache_dir: impl AsRef<Path>) -> Result<Self, RagError> {
        let options = TextInitOptions::new(EmbeddingModel::AllMiniLML6V2)
            .with_cache_dir(cache_dir.as_ref().to_path_buf());
        let model = TextEmbedding::try_new(options)
            .map_err(|error| RagError::Embedding(error.to_string()))?;
        Ok(Self {
            model: Mutex::new(model),
        })
    }
}

impl EmbeddingBackend for FastEmbedBackend {
    fn model_id(&self) -> &str {
        MODEL_ID
    }

    fn dimensions(&self) -> usize {
        MODEL_DIMENSIONS
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, RagError> {
        let mut model = self
            .model
            .lock()
            .map_err(|_| RagError::Embedding("embedding model lock was poisoned".to_string()))?;
        model
            .embed(texts, Some(EMBEDDING_BATCH_SIZE))
            .map_err(|error| RagError::Embedding(error.to_string()))
    }
}

pub struct VectorRagEngine<'a> {
    embeddings: &'a dyn EmbeddingBackend,
}

impl<'a> VectorRagEngine<'a> {
    pub fn new(embeddings: &'a dyn EmbeddingBackend) -> Self {
        Self { embeddings }
    }

    pub fn index_or_load(
        &self,
        document_fingerprint: &str,
        paths: &RagIndexPaths,
        chunks: &[RagChunk],
    ) -> Result<RagIndexOutcome, RagError> {
        let index_exists = paths.index_path.exists();
        let manifest_exists = paths.manifest_path.exists();
        if index_exists || manifest_exists {
            if !(index_exists && manifest_exists) {
                return Err(RagError::RebuildRequired {
                    reason: "the persisted index and manifest are incomplete".to_string(),
                });
            }
            let manifest = read_manifest(&paths.manifest_path)?;
            validate_manifest(
                &manifest,
                document_fingerprint,
                self.embeddings.model_id(),
                self.embeddings.dimensions(),
                chunks,
            )?;
            validate_index(&paths.index_path, self.embeddings.dimensions())?;
            return Ok(RagIndexOutcome::Loaded);
        }
        self.build(document_fingerprint, paths, chunks)
    }

    pub fn rebuild(
        &self,
        document_fingerprint: &str,
        paths: &RagIndexPaths,
        chunks: &[RagChunk],
    ) -> Result<RagIndexOutcome, RagError> {
        self.build(document_fingerprint, paths, chunks)
    }

    pub fn query(
        &self,
        paths: &RagIndexPaths,
        query: &str,
        limit: usize,
    ) -> Result<Vec<RagSearchResult>, RagError> {
        if query.trim().is_empty() || limit == 0 {
            return Ok(Vec::new());
        }
        let manifest = read_manifest(&paths.manifest_path)?;
        if manifest.version != MANIFEST_VERSION || manifest.model_id != self.embeddings.model_id() {
            return Err(RagError::RebuildRequired {
                reason: "the persisted model identity is not current".to_string(),
            });
        }
        if manifest.dimensions != self.embeddings.dimensions() {
            return Err(RagError::RebuildRequired {
                reason: "the persisted vector dimensions are not current".to_string(),
            });
        }
        let index = restore_index(&paths.index_path)?;
        let query_vector = self.embed_one(&format!("query: {}", query.trim()))?;
        validate_vector_dimensions(&query_vector, manifest.dimensions)?;
        let matches = index
            .search(&query_vector, limit.min(manifest.chunk_ids.len()))
            .map_err(|error| {
                RagError::Storage(format!("search {}: {error}", paths.index_path.display()))
            })?;
        Ok(matches
            .keys
            .iter()
            .zip(matches.distances.iter())
            .filter_map(|(key, distance)| {
                manifest
                    .chunk_ids
                    .get(*key as usize)
                    .map(|chunk_id| RagSearchResult {
                        chunk_id: chunk_id.clone(),
                        score: 1.0 - *distance,
                    })
            })
            .collect())
    }

    fn build(
        &self,
        document_fingerprint: &str,
        paths: &RagIndexPaths,
        chunks: &[RagChunk],
    ) -> Result<RagIndexOutcome, RagError> {
        if chunks.is_empty() {
            return Err(RagError::RebuildRequired {
                reason: "there are no text chunks to index".to_string(),
            });
        }
        ensure_parent_directory(paths)?;
        let texts = chunks
            .iter()
            .map(|chunk| format!("passage: {}", chunk.text))
            .collect::<Vec<_>>();
        let vectors = self.embeddings.embed(&texts)?;
        if vectors.len() != chunks.len() {
            return Err(RagError::Embedding(format!(
                "expected {} vectors but received {}",
                chunks.len(),
                vectors.len()
            )));
        }
        let dimensions = self.embeddings.dimensions();
        let index = create_index(dimensions)?;
        index
            .reserve(vectors.len())
            .map_err(|error| RagError::Storage(format!("reserve index: {error}")))?;
        for (key, vector) in vectors.iter().enumerate() {
            validate_vector_dimensions(vector, dimensions)?;
            index
                .add(key as u64, vector)
                .map_err(|error| RagError::Storage(format!("add vector {key}: {error}")))?;
        }
        index
            .save(path_as_str(&paths.index_path)?)
            .map_err(|error| {
                RagError::Storage(format!("save {}: {error}", paths.index_path.display()))
            })?;
        let manifest = RagManifest {
            version: MANIFEST_VERSION,
            document_fingerprint: document_fingerprint.to_string(),
            model_id: self.embeddings.model_id().to_string(),
            dimensions,
            chunk_ids: chunks.iter().map(|chunk| chunk.id.clone()).collect(),
        };
        write_manifest(&paths.manifest_path, &manifest)?;
        Ok(RagIndexOutcome::Built)
    }

    fn embed_one(&self, text: &str) -> Result<Vec<f32>, RagError> {
        let vectors = self.embeddings.embed(&[text.to_string()])?;
        vectors.into_iter().next().ok_or_else(|| {
            RagError::Embedding("embedding backend returned no query vector".to_string())
        })
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct RagManifest {
    version: u32,
    document_fingerprint: String,
    model_id: String,
    dimensions: usize,
    chunk_ids: Vec<String>,
}

fn read_manifest(path: &Path) -> Result<RagManifest, RagError> {
    let contents = fs::read_to_string(path).map_err(|error| RagError::RebuildRequired {
        reason: format!("cannot read manifest {}: {error}", path.display()),
    })?;
    serde_json::from_str(&contents).map_err(|error| RagError::RebuildRequired {
        reason: format!("cannot parse manifest {}: {error}", path.display()),
    })
}

fn write_manifest(path: &Path, manifest: &RagManifest) -> Result<(), RagError> {
    let contents = serde_json::to_vec_pretty(manifest)
        .map_err(|error| RagError::Storage(format!("serialize manifest: {error}")))?;
    fs::write(path, contents)
        .map_err(|error| RagError::Storage(format!("write manifest {}: {error}", path.display())))
}

fn validate_manifest(
    manifest: &RagManifest,
    document_fingerprint: &str,
    model_id: &str,
    dimensions: usize,
    chunks: &[RagChunk],
) -> Result<(), RagError> {
    let expected_chunk_ids = chunks.iter().map(|chunk| &chunk.id).collect::<Vec<_>>();
    let actual_chunk_ids = manifest.chunk_ids.iter().collect::<Vec<_>>();
    let mismatch = if manifest.version != MANIFEST_VERSION {
        Some("the manifest version changed")
    } else if manifest.document_fingerprint != document_fingerprint {
        Some("the document fingerprint changed")
    } else if manifest.model_id != model_id {
        Some("the embedding model changed")
    } else if manifest.dimensions != dimensions {
        Some("the vector dimensions changed")
    } else if actual_chunk_ids != expected_chunk_ids {
        Some("the indexed chunks changed")
    } else {
        None
    };
    mismatch.map_or(Ok(()), |reason| {
        Err(RagError::RebuildRequired {
            reason: reason.to_string(),
        })
    })
}

fn validate_index(path: &Path, dimensions: usize) -> Result<(), RagError> {
    let metadata =
        Index::metadata(path_as_str(path)?).map_err(|error| RagError::RebuildRequired {
            reason: format!("cannot read index {}: {error}", path.display()),
        })?;
    if metadata.dimensions != dimensions as u64 || metadata.metric != MetricKind::Cos {
        return Err(RagError::RebuildRequired {
            reason: "the persisted index configuration is not current".to_string(),
        });
    }
    Ok(())
}

fn create_index(dimensions: usize) -> Result<Index, RagError> {
    let options = IndexOptions {
        dimensions,
        metric: MetricKind::Cos,
        quantization: ScalarKind::F32,
        connectivity: 0,
        expansion_add: 0,
        expansion_search: 0,
        multi: false,
    };
    new_index(&options).map_err(|error| RagError::Storage(format!("create index: {error}")))
}

fn restore_index(path: &Path) -> Result<Index, RagError> {
    Index::restore(path_as_str(path)?).map_err(|error| RagError::RebuildRequired {
        reason: format!("cannot restore index {}: {error}", path.display()),
    })
}

fn validate_vector_dimensions(vector: &[f32], dimensions: usize) -> Result<(), RagError> {
    if vector.len() == dimensions {
        Ok(())
    } else {
        Err(RagError::Embedding(format!(
            "expected {dimensions} dimensions but received {}",
            vector.len()
        )))
    }
}

fn ensure_parent_directory(paths: &RagIndexPaths) -> Result<(), RagError> {
    let parent = paths.index_path.parent().ok_or_else(|| {
        RagError::Storage(format!(
            "index path {} has no parent",
            paths.index_path.display()
        ))
    })?;
    fs::create_dir_all(parent).map_err(|error| {
        RagError::Storage(format!(
            "create index directory {}: {error}",
            parent.display()
        ))
    })
}

fn path_as_str(path: &Path) -> Result<&str, RagError> {
    path.to_str()
        .ok_or_else(|| RagError::Storage(format!("path {} is not valid UTF-8", path.display())))
}

fn safe_file_stem(value: &str) -> String {
    let stem = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '-' || character == '_' {
                character
            } else {
                '_'
            }
        })
        .collect::<String>();
    if stem.is_empty() {
        "document".to_string()
    } else {
        stem
    }
}

#[cfg(test)]
mod tests {
    use super::{EmbeddingBackend, RagChunk, RagIndexPaths, VectorRagEngine};
    use std::collections::HashMap;
    use std::path::PathBuf;
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct DeterministicEmbeddings {
        vectors: Mutex<HashMap<String, Vec<f32>>>,
    }

    impl DeterministicEmbeddings {
        fn new(entries: impl IntoIterator<Item = (&'static str, Vec<f32>)>) -> Self {
            Self {
                vectors: Mutex::new(
                    entries
                        .into_iter()
                        .map(|(text, vector)| (text.to_string(), vector))
                        .collect(),
                ),
            }
        }
    }

    impl EmbeddingBackend for DeterministicEmbeddings {
        fn model_id(&self) -> &str {
            "deterministic-test"
        }

        fn dimensions(&self) -> usize {
            2
        }

        fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, super::RagError> {
            let vectors = self.vectors.lock().unwrap();
            texts
                .iter()
                .map(|text| {
                    vectors.get(text).cloned().ok_or_else(|| {
                        super::RagError::Embedding(format!("missing test vector: {text}"))
                    })
                })
                .collect()
        }
    }

    fn temporary_root() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be after the Unix epoch")
            .as_nanos();
        std::env::temp_dir().join(format!("clarix-rag-{}-{nonce}", std::process::id()))
    }

    #[test]
    fn rag_ranks_the_semantically_matching_chunk() {
        let root = temporary_root();
        let paths = RagIndexPaths::for_document(&root, "fingerprint-a");
        let embeddings = DeterministicEmbeddings::new([
            ("passage: apples grow on trees", vec![1.0, 0.0]),
            ("passage: trains run on rails", vec![0.0, 1.0]),
            ("query: where do apples grow", vec![0.98, 0.02]),
        ]);
        let engine = VectorRagEngine::new(&embeddings);
        let chunks = vec![
            RagChunk::new("fruit", "apples grow on trees"),
            RagChunk::new("train", "trains run on rails"),
        ];

        engine
            .index_or_load("fingerprint-a", &paths, &chunks)
            .expect("index should build");
        let results = engine
            .query(&paths, "where do apples grow", 2)
            .expect("query should work");

        assert_eq!(results[0].chunk_id, "fruit");
        assert!(results[0].score > results[1].score);
    }

    #[test]
    fn rag_rejects_a_manifest_with_wrong_dimensions() {
        let root = temporary_root();
        let paths = RagIndexPaths::for_document(&root, "fingerprint-b");
        let embeddings = DeterministicEmbeddings::new([("passage: a", vec![1.0, 0.0])]);
        let engine = VectorRagEngine::new(&embeddings);
        let chunks = vec![RagChunk::new("a", "a")];

        std::fs::create_dir_all(&root).expect("temporary root should exist");
        std::fs::write(
            &paths.manifest_path,
            r#"{"version":1,"document_fingerprint":"fingerprint-b","model_id":"deterministic-test","dimensions":3,"chunk_ids":["a"]}"#,
        )
        .expect("manifest should be written");

        let error = engine
            .index_or_load("fingerprint-b", &paths, &chunks)
            .expect_err("wrong dimensions must be rejected");

        assert!(matches!(error, super::RagError::RebuildRequired { .. }));
    }
}
