use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};
use serde::{Deserialize, Serialize};
use std::fmt::{Display, Formatter};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use usearch::{new_index, Index, IndexOptions, MetricKind, ScalarKind};

const MANIFEST_VERSION: u32 = 1;
pub const MODEL_ID: &str = "sentence-transformers/all-MiniLM-L6-v2";
pub const MODEL_DIMENSIONS: usize = 384;
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
            validate_index(
                &paths.index_path,
                self.embeddings.dimensions(),
                manifest.chunk_ids.len(),
            )?;
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
        document_fingerprint: &str,
        paths: &RagIndexPaths,
        chunks: &[RagChunk],
        query: &str,
        limit: usize,
    ) -> Result<Vec<RagSearchResult>, RagError> {
        if query.trim().is_empty() || limit == 0 {
            return Ok(Vec::new());
        }
        let manifest = read_manifest(&paths.manifest_path)?;
        validate_manifest(
            &manifest,
            document_fingerprint,
            self.embeddings.model_id(),
            self.embeddings.dimensions(),
            chunks,
        )?;
        validate_index(
            &paths.index_path,
            self.embeddings.dimensions(),
            manifest.chunk_ids.len(),
        )?;
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
        save_index_atomically(&index, &paths.index_path)?;
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
    let temporary_path = temporary_path(path)?;
    fs::write(&temporary_path, contents).map_err(|error| {
        RagError::Storage(format!(
            "write temporary manifest {}: {error}",
            temporary_path.display()
        ))
    })?;
    replace_atomically(&temporary_path, path)
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

fn validate_index(path: &Path, dimensions: usize, expected_count: usize) -> Result<(), RagError> {
    let metadata =
        Index::metadata(path_as_str(path)?).map_err(|error| RagError::RebuildRequired {
            reason: format!("cannot read index {}: {error}", path.display()),
        })?;
    if metadata.dimensions != dimensions as u64
        || metadata.metric != MetricKind::Cos
        || metadata.quantization != ScalarKind::F32
        || metadata.multi
        || metadata.count_present != expected_count as u64
    {
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

fn save_index_atomically(index: &Index, path: &Path) -> Result<(), RagError> {
    let temporary_path = temporary_path(path)?;
    index.save(path_as_str(&temporary_path)?).map_err(|error| {
        RagError::Storage(format!(
            "save temporary index {}: {error}",
            temporary_path.display()
        ))
    })?;
    replace_atomically(&temporary_path, path)
}

fn temporary_path(path: &Path) -> Result<PathBuf, RagError> {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            RagError::Storage(format!("path {} has no UTF-8 file name", path.display()))
        })?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| RagError::Storage(format!("read system clock: {error}")))?
        .as_nanos();
    Ok(path.with_file_name(format!(".{file_name}.{}.{}.tmp", std::process::id(), nonce)))
}

fn replace_atomically(temporary_path: &Path, destination_path: &Path) -> Result<(), RagError> {
    fs::rename(temporary_path, destination_path).map_err(|error| {
        RagError::Storage(format!(
            "replace {} with {}: {error}",
            destination_path.display(),
            temporary_path.display()
        ))
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
#[allow(clippy::items_after_test_module)]
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
            .query("fingerprint-a", &paths, &chunks, "where do apples grow", 2)
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

        engine
            .index_or_load("fingerprint-b", &paths, &chunks)
            .expect("matching persisted index should build");
        let mut manifest =
            super::read_manifest(&paths.manifest_path).expect("fresh manifest should be readable");
        manifest.dimensions = 3;
        super::write_manifest(&paths.manifest_path, &manifest)
            .expect("altered manifest should be written");

        let error = engine
            .index_or_load("fingerprint-b", &paths, &chunks)
            .expect_err("wrong dimensions must be rejected");

        assert!(matches!(error, super::RagError::RebuildRequired { .. }));
    }

    #[test]
    fn rag_rejects_a_persisted_index_with_the_wrong_vector_count() {
        let root = temporary_root();
        let paths = RagIndexPaths::for_document(&root, "fingerprint-c");
        let embeddings = DeterministicEmbeddings::new([
            ("passage: a", vec![1.0, 0.0]),
            ("passage: b", vec![0.0, 1.0]),
        ]);
        let engine = VectorRagEngine::new(&embeddings);
        let first_chunks = vec![RagChunk::new("a", "a")];
        let current_chunks = vec![RagChunk::new("a", "a"), RagChunk::new("b", "b")];

        engine
            .index_or_load("fingerprint-c", &paths, &first_chunks)
            .expect("first index should build");
        let mut manifest =
            super::read_manifest(&paths.manifest_path).expect("fresh manifest should be readable");
        manifest.chunk_ids = current_chunks
            .iter()
            .map(|chunk| chunk.id.clone())
            .collect();
        super::write_manifest(&paths.manifest_path, &manifest)
            .expect("matching-but-wrong-count manifest should be written");

        let error = engine
            .index_or_load("fingerprint-c", &paths, &current_chunks)
            .expect_err("wrong vector count must require a rebuild");

        assert!(matches!(error, super::RagError::RebuildRequired { .. }));
    }

    #[test]
    fn rag_query_rejects_a_different_document_identity() {
        let root = temporary_root();
        let paths = RagIndexPaths::for_document(&root, "fingerprint-d");
        let embeddings = DeterministicEmbeddings::new([
            ("passage: a", vec![1.0, 0.0]),
            ("passage: b", vec![0.0, 1.0]),
            ("query: find a", vec![1.0, 0.0]),
        ]);
        let engine = VectorRagEngine::new(&embeddings);
        let indexed_chunks = vec![RagChunk::new("a", "a")];
        let other_chunks = vec![RagChunk::new("b", "b")];

        engine
            .index_or_load("fingerprint-d", &paths, &indexed_chunks)
            .expect("index should build");
        let error = engine
            .query("different-document", &paths, &other_chunks, "find a", 1)
            .expect_err("query must validate the current document identity");

        assert!(matches!(error, super::RagError::RebuildRequired { .. }));
    }

    #[test]
    fn validation_reuses_a_matching_persisted_index_without_embeddings() {
        let root = temporary_root();
        let paths = RagIndexPaths::for_document(&root, "fingerprint-e");
        let embeddings = DeterministicEmbeddings::new([
            ("passage: a", vec![1.0, 0.0]),
            ("passage: b", vec![0.0, 1.0]),
        ]);
        let engine = VectorRagEngine::new(&embeddings);
        let chunks = vec![RagChunk::new("a", "a"), RagChunk::new("b", "b")];

        engine
            .index_or_load("fingerprint-e", &paths, &chunks)
            .expect("index should build");

        super::validate_existing_index(
            "fingerprint-e",
            &paths,
            embeddings.model_id(),
            embeddings.dimensions(),
            &chunks,
        )
        .expect("matching persisted index should validate");
    }
}

pub fn validate_existing_index(
    document_fingerprint: &str,
    paths: &RagIndexPaths,
    model_id: &str,
    dimensions: usize,
    chunks: &[RagChunk],
) -> Result<(), RagError> {
    let manifest = read_manifest(&paths.manifest_path)?;
    validate_manifest(
        &manifest,
        document_fingerprint,
        model_id,
        dimensions,
        chunks,
    )?;
    validate_index(&paths.index_path, dimensions, manifest.chunk_ids.len())
}
