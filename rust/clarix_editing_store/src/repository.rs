use std::sync::Mutex;

use clarix_editing_core::{
    CheckpointKind, DocumentId, DocumentObject, DurableCommit, DurableSnapshot, EditorCommand,
    ImportedPage, MaterializationRecord, PageIndexRepository, PersistenceError, ProjectCheckpoint,
    ProjectRepository, RecoveredCommand, RecoveredProject, RecoveryRequest,
};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use unicode_normalization::UnicodeNormalization;

use crate::{schema, FaultPoint, ProjectLocation, ProjectSeed, StoreError, StoreTable};

const WAL_CHECKPOINT_MARKER_ENV: &str = "CLARIX_PHASE1_WAL_CHECKPOINT_MARKER";
const WAL_CHECKPOINT_PAUSE_MS_ENV: &str = "CLARIX_PHASE1_WAL_CHECKPOINT_PAUSE_MS";

pub struct SqliteProjectRepository {
    connection: Mutex<Connection>,
    fault: Mutex<Option<FaultPoint>>,
}

impl SqliteProjectRepository {
    pub fn open(location: ProjectLocation, seed: ProjectSeed) -> Result<Self, StoreError> {
        location.create_directories()?;
        let connection = Connection::open(&location.database)?;
        schema::initialize(&connection)?;
        let existing: Option<(String, String)> = connection
            .query_row(
                "SELECT document_id, source_fingerprint FROM project WHERE singleton = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;
        if let Some((document_id, fingerprint)) = existing {
            if document_id != seed.model.id.to_string() {
                return Err(StoreError::DocumentMismatch);
            }
            if fingerprint != seed.model.source_fingerprint {
                return Err(StoreError::SourceMismatch);
            }
        } else {
            let model_json = serde_json::to_string(&seed.model)?;
            let model_sha256 = sha256_hex(model_json.as_bytes());
            connection.execute(
                "INSERT INTO project (singleton, document_id, source_fingerprint, revision, model_json, model_sha256, undo_cursor, materialized_revision) VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    seed.model.id.to_string(),
                    seed.model.source_fingerprint,
                    i64_revision(seed.model.revision)?,
                    model_json,
                    model_sha256,
                    i64::try_from(seed.undo_cursor).map_err(|_| StoreError::IntegerRange)?,
                    seed.materialized_revision.map(i64_revision).transpose()?,
                ],
            )?;
            connection.execute(
                "INSERT INTO snapshots (revision, model_json, model_sha256, undo_cursor) VALUES (?1, ?2, ?3, ?4)",
                params![
                    i64_revision(seed.model.revision)?,
                    model_json,
                    model_sha256,
                    i64::try_from(seed.undo_cursor).map_err(|_| StoreError::IntegerRange)?,
                ],
            )?;
        }
        Ok(Self {
            connection: Mutex::new(connection),
            fault: Mutex::new(None),
        })
    }

    pub fn inject_once(&self, point: FaultPoint) {
        *self.fault.lock().expect("fault lock must be available") = Some(point);
    }

    pub fn row_count(&self, table: StoreTable) -> Result<u64, StoreError> {
        let connection = self.connection.lock().map_err(|_| StoreError::Poisoned)?;
        let sql = format!("SELECT COUNT(*) FROM {}", table.sql_name());
        let count: i64 = connection.query_row(&sql, [], |row| row.get(0))?;
        u64::try_from(count).map_err(|_| StoreError::IntegerRange)
    }

    fn take_fault(&self, point: FaultPoint) -> bool {
        let mut fault = self.fault.lock().expect("fault lock must be available");
        if fault.as_ref() == Some(&point) {
            fault.take();
            true
        } else {
            false
        }
    }

    fn checkpoint_wal(&self, connection: &Connection) -> Result<(), PersistenceError> {
        connection
            .execute_batch("PRAGMA wal_checkpoint(PASSIVE);")
            .map_err(map_persistence)?;
        if self.take_fault(FaultPoint::DuringWalCheckpoint) {
            return Err(PersistenceError::Transaction(
                "injected failure during WAL checkpoint".into(),
            ));
        }
        if let Some(marker) = std::env::var_os(WAL_CHECKPOINT_MARKER_ENV) {
            std::fs::write(marker, b"passive_checkpoint_complete\n").map_err(|error| {
                PersistenceError::Unavailable(format!(
                    "WAL checkpoint probe marker could not be written: {error}"
                ))
            })?;
            let pause_ms = std::env::var(WAL_CHECKPOINT_PAUSE_MS_ENV)
                .ok()
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or(30_000);
            std::thread::sleep(std::time::Duration::from_millis(pause_ms));
        }
        connection
            .execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")
            .map_err(map_persistence)
    }
}

impl ProjectRepository for SqliteProjectRepository {
    fn recover(&self, request: RecoveryRequest) -> Result<RecoveredProject, PersistenceError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        let row: (String, String, i64, String, String, i64, Option<i64>) = connection
            .query_row(
                "SELECT document_id, source_fingerprint, revision, model_json, model_sha256, undo_cursor, materialized_revision FROM project WHERE singleton = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?, row.get(5)?, row.get(6)?)),
            )
            .map_err(map_persistence)?;
        if row.0 != request.document_id.to_string() || row.1 != request.source_fingerprint {
            return Err(PersistenceError::SourceMismatch);
        }
        let (model, warnings) = if sha256_hex(row.3.as_bytes()) == row.4 {
            (
                serde_json::from_str(&row.3)
                    .map_err(|error| PersistenceError::Corrupt(error.to_string()))?,
                Vec::new(),
            )
        } else {
            (
                recover_snapshot_and_journal(&connection, row.2)?,
                vec!["current model checksum invalid; recovered from snapshot and journal".into()],
            )
        };
        Ok(RecoveredProject {
            model,
            undo_cursor: u64::try_from(row.5)
                .map_err(|_| PersistenceError::Corrupt("negative undo cursor".into()))?,
            materialized_revision: row
                .6
                .map(|value| {
                    u64::try_from(value)
                        .map(clarix_editing_core::DocumentRevision::from_value)
                        .map_err(|_| {
                            PersistenceError::Corrupt("negative materialized revision".into())
                        })
                })
                .transpose()?,
            warnings,
            commands: recovered_commands(&connection)?,
        })
    }

    fn append(&self, commit: &DurableCommit) -> Result<(), PersistenceError> {
        if self.take_fault(FaultPoint::BeforeBegin) {
            return Err(PersistenceError::Transaction(
                "injected failure before transaction".into(),
            ));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        let transaction = connection.transaction().map_err(map_persistence)?;
        let current_revision: i64 = transaction
            .query_row(
                "SELECT revision FROM project WHERE singleton = 1",
                [],
                |row| row.get(0),
            )
            .map_err(map_persistence)?;
        if current_revision
            != i64_revision(commit.previous_revision).map_err(map_store_persistence)?
        {
            return Err(PersistenceError::Transaction(
                "sidecar revision conflict".into(),
            ));
        }
        let command_id = commit.envelope.command_id.to_string();
        transaction
            .execute(
                "INSERT INTO commands (command_id, previous_revision, committed_revision, envelope_json, before_json, after_json, after_sha256) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    command_id,
                    i64_revision(commit.previous_revision).map_err(map_store_persistence)?,
                    i64_revision(commit.committed_revision).map_err(map_store_persistence)?,
                    json(&commit.envelope).map_err(map_store_persistence)?,
                    json(&commit.before_objects).map_err(map_store_persistence)?,
                    json(&commit.after_objects).map_err(map_store_persistence)?,
                    sha256_hex(json(&commit.after_objects).map_err(map_store_persistence)?.as_bytes()),
                ],
            )
            .map_err(map_persistence)?;
        if self.take_fault(FaultPoint::AfterCommandInsert) {
            return Err(PersistenceError::Transaction(
                "injected failure after command insert".into(),
            ));
        }
        transaction
            .execute(
                "INSERT INTO inverse_operations (command_id, inverse_json) VALUES (?1, ?2)",
                params![
                    command_id,
                    json(&commit.inverse).map_err(map_store_persistence)?
                ],
            )
            .map_err(map_persistence)?;
        if self.take_fault(FaultPoint::AfterInverseInsert) {
            return Err(PersistenceError::Transaction(
                "injected failure after inverse insert".into(),
            ));
        }
        let model_json = json(&commit.resulting_model).map_err(map_store_persistence)?;
        transaction
            .execute(
                "UPDATE project SET revision = ?1, model_json = ?2, model_sha256 = ?3, undo_cursor = ?4 WHERE singleton = 1",
                params![
                    i64_revision(commit.committed_revision).map_err(map_store_persistence)?,
                    model_json,
                    sha256_hex(model_json.as_bytes()),
                    i64::try_from(commit.undo_cursor).map_err(|_| PersistenceError::Transaction("undo cursor exceeds SQLite range".into()))?,
                ],
            )
            .map_err(map_persistence)?;
        if let EditorCommand::CreateCheckpoint { label } = &commit.envelope.payload {
            transaction
                .execute(
                    "INSERT OR REPLACE INTO checkpoints (label, revision, kind) VALUES (?1, ?2, ?3)",
                    params![
                        label,
                        i64_revision(commit.committed_revision).map_err(map_store_persistence)?,
                        format!("{:?}", CheckpointKind::User),
                    ],
                )
                .map_err(map_persistence)?;
            transaction
                .execute(
                    "INSERT OR REPLACE INTO snapshots (revision, model_json, model_sha256, undo_cursor) VALUES (?1, ?2, ?3, ?4)",
                    params![
                        i64_revision(commit.committed_revision).map_err(map_store_persistence)?,
                        model_json,
                        sha256_hex(model_json.as_bytes()),
                        i64::try_from(commit.undo_cursor).map_err(|_| PersistenceError::Transaction("undo cursor exceeds SQLite range".into()))?,
                    ],
                )
                .map_err(map_persistence)?;
        }
        if self.take_fault(FaultPoint::AfterModelUpdate) {
            return Err(PersistenceError::Transaction(
                "injected failure after model update".into(),
            ));
        }
        if self.take_fault(FaultPoint::BeforeCommit) {
            return Err(PersistenceError::Transaction(
                "injected failure before commit".into(),
            ));
        }
        transaction.commit().map_err(map_persistence)?;
        let _ = self.take_fault(FaultPoint::AfterCommit);
        Ok(())
    }

    fn write_snapshot(&self, snapshot: &DurableSnapshot) -> Result<(), PersistenceError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        let model_json = json(&snapshot.model).map_err(map_store_persistence)?;
        connection.execute(
            "INSERT OR REPLACE INTO snapshots (revision, model_json, model_sha256, undo_cursor) VALUES (?1, ?2, ?3, ?4)",
            params![i64_revision(snapshot.revision).map_err(map_store_persistence)?, model_json, sha256_hex(model_json.as_bytes()), i64::try_from(snapshot.undo_cursor).map_err(|_| PersistenceError::Transaction("undo cursor exceeds SQLite range".into()))?],
        ).map_err(map_persistence)?;
        Ok(())
    }

    fn checkpoint(&self, checkpoint: &ProjectCheckpoint) -> Result<(), PersistenceError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        connection
            .execute(
                "INSERT OR REPLACE INTO checkpoints (label, revision, kind) VALUES (?1, ?2, ?3)",
                params![
                    checkpoint.label,
                    i64_revision(checkpoint.revision).map_err(map_store_persistence)?,
                    format!("{:?}", checkpoint.kind)
                ],
            )
            .map_err(map_persistence)?;
        Ok(())
    }

    fn record_materialization(
        &self,
        record: MaterializationRecord,
    ) -> Result<(), PersistenceError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        let revision = i64_revision(record.revision).map_err(map_store_persistence)?;
        let transaction = connection
            .unchecked_transaction()
            .map_err(map_persistence)?;
        transaction.execute(
            "INSERT OR REPLACE INTO materializations (revision, output_sha256, target_path) VALUES (?1, ?2, ?3)",
            params![revision, record.output_sha256, record.target_path],
        ).map_err(map_persistence)?;
        transaction
            .execute(
                "UPDATE project SET materialized_revision = ?1 WHERE singleton = 1",
                params![revision],
            )
            .map_err(map_persistence)?;
        transaction.commit().map_err(map_persistence)
    }

    fn close(&self) -> Result<(), PersistenceError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        self.checkpoint_wal(&connection)
    }
}

#[derive(Serialize, Deserialize)]
struct StoredIndexedPage {
    page: clarix_editing_core::PageNode,
    warnings: Vec<String>,
}

impl PageIndexRepository for SqliteProjectRepository {
    fn load_indexed_page(
        &self,
        document_id: DocumentId,
        source_fingerprint: &str,
        page_number: u32,
    ) -> Result<Option<ImportedPage>, PersistenceError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        verify_project_identity(&connection, document_id, source_fingerprint)?;
        let payload: Option<String> = connection
            .query_row(
                "SELECT payload_json FROM pages WHERE page_number = ?1",
                params![page_number],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence)?;
        payload
            .map(|payload| {
                serde_json::from_str::<StoredIndexedPage>(&payload)
                    .map(|stored| ImportedPage {
                        page: stored.page,
                        warnings: stored.warnings,
                    })
                    .map_err(|error| PersistenceError::Corrupt(error.to_string()))
            })
            .transpose()
    }

    fn store_indexed_page(
        &self,
        document_id: DocumentId,
        source_fingerprint: &str,
        imported: &ImportedPage,
    ) -> Result<(), PersistenceError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| PersistenceError::Unavailable("repository lock poisoned".into()))?;
        verify_project_identity(&connection, document_id, source_fingerprint)?;
        let transaction = connection.transaction().map_err(map_persistence)?;
        let old_object_ids = {
            let mut statement = transaction
                .prepare("SELECT object_id FROM objects WHERE page_id = ?1")
                .map_err(map_persistence)?;
            let object_ids = statement
                .query_map(params![imported.page.id.to_string()], |row| {
                    row.get::<_, String>(0)
                })
                .map_err(map_persistence)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(map_persistence)?;
            object_ids
        };
        for object_id in old_object_ids {
            transaction
                .execute(
                    "DELETE FROM text_runs WHERE object_id = ?1",
                    params![object_id],
                )
                .map_err(map_persistence)?;
            transaction
                .execute(
                    "DELETE FROM source_bindings WHERE object_id = ?1",
                    params![object_id],
                )
                .map_err(map_persistence)?;
            transaction
                .execute(
                    "DELETE FROM text_index WHERE object_id = ?1",
                    params![object_id],
                )
                .map_err(map_persistence)?;
        }
        transaction
            .execute(
                "DELETE FROM objects WHERE page_id = ?1",
                params![imported.page.id.to_string()],
            )
            .map_err(map_persistence)?;
        let stored = StoredIndexedPage {
            page: imported.page.clone(),
            warnings: imported.warnings.clone(),
        };
        transaction
            .execute(
                "INSERT OR REPLACE INTO pages (page_id, page_number, payload_json) VALUES (?1, ?2, ?3)",
                params![
                    imported.page.id.to_string(),
                    imported.page.page_number,
                    json(&stored).map_err(map_store_persistence)?,
                ],
            )
            .map_err(map_persistence)?;
        transaction
            .execute(
                "INSERT OR REPLACE INTO page_index_state (page_id, state) VALUES (?1, 'Indexed')",
                params![imported.page.id.to_string()],
            )
            .map_err(map_persistence)?;
        for object in &imported.page.objects {
            let object_id = object.id().to_string();
            transaction
                .execute(
                    "INSERT INTO objects (object_id, page_id, payload_json) VALUES (?1, ?2, ?3)",
                    params![
                        object_id,
                        imported.page.id.to_string(),
                        json(object).map_err(map_store_persistence)?,
                    ],
                )
                .map_err(map_persistence)?;
            if let Some(binding) = object.source_binding() {
                transaction
                    .execute(
                        "INSERT INTO source_bindings (object_id, payload_json) VALUES (?1, ?2)",
                        params![object_id, json(binding).map_err(map_store_persistence)?,],
                    )
                    .map_err(map_persistence)?;
            }
            if let DocumentObject::Text(text) = object {
                for (ordinal, run) in text.runs.iter().enumerate() {
                    transaction
                        .execute(
                            "INSERT INTO text_runs (object_id, ordinal, payload_json) VALUES (?1, ?2, ?3)",
                            params![
                                object_id,
                                i64::try_from(ordinal).map_err(|_| PersistenceError::Transaction("text run ordinal exceeds SQLite range".into()))?,
                                json(run).map_err(map_store_persistence)?,
                            ],
                        )
                        .map_err(map_persistence)?;
                }
                transaction
                    .execute(
                        "INSERT INTO text_index (object_id, normalized_text) VALUES (?1, ?2)",
                        params![object_id, normalized_text(&text.text)],
                    )
                    .map_err(map_persistence)?;
            }
        }
        transaction.commit().map_err(map_persistence)
    }
}

fn json(value: &impl Serialize) -> Result<String, StoreError> {
    serde_json::to_string(value).map_err(StoreError::from)
}

fn i64_revision(revision: clarix_editing_core::DocumentRevision) -> Result<i64, StoreError> {
    i64::try_from(revision.value()).map_err(|_| StoreError::IntegerRange)
}

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn normalized_text(text: &str) -> String {
    text.nfkc().flat_map(char::to_lowercase).collect()
}

fn map_persistence(error: rusqlite::Error) -> PersistenceError {
    PersistenceError::Transaction(error.to_string())
}

fn map_store_persistence(error: StoreError) -> PersistenceError {
    PersistenceError::Transaction(error.to_string())
}

fn verify_project_identity(
    connection: &Connection,
    document_id: DocumentId,
    source_fingerprint: &str,
) -> Result<(), PersistenceError> {
    let identity: (String, String) = connection
        .query_row(
            "SELECT document_id, source_fingerprint FROM project WHERE singleton = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(map_persistence)?;
    if identity.0 != document_id.to_string() || identity.1 != source_fingerprint {
        return Err(PersistenceError::SourceMismatch);
    }
    Ok(())
}

fn recovered_commands(connection: &Connection) -> Result<Vec<RecoveredCommand>, PersistenceError> {
    let mut statement = connection
        .prepare(
            "SELECT previous_revision, committed_revision, envelope_json, before_json, after_json, after_sha256 FROM commands ORDER BY committed_revision ASC",
        )
        .map_err(map_persistence)?;
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
            ))
        })
        .map_err(map_persistence)?;
    let mut commands = Vec::new();
    for row in rows {
        let (previous, committed, envelope, before, after, after_checksum) =
            row.map_err(map_persistence)?;
        if sha256_hex(after.as_bytes()) != after_checksum {
            return Err(PersistenceError::Corrupt(format!(
                "command revision {committed} checksum mismatch"
            )));
        }
        commands.push(RecoveredCommand {
            envelope: serde_json::from_str(&envelope)
                .map_err(|error| PersistenceError::Corrupt(error.to_string()))?,
            previous_revision: database_revision(previous)?,
            committed_revision: database_revision(committed)?,
            before_objects: serde_json::from_str(&before)
                .map_err(|error| PersistenceError::Corrupt(error.to_string()))?,
            after_objects: serde_json::from_str(&after)
                .map_err(|error| PersistenceError::Corrupt(error.to_string()))?,
        });
    }
    Ok(commands)
}

fn database_revision(
    value: i64,
) -> Result<clarix_editing_core::DocumentRevision, PersistenceError> {
    u64::try_from(value)
        .map(clarix_editing_core::DocumentRevision::from_value)
        .map_err(|_| PersistenceError::Corrupt("negative command revision".into()))
}

fn recover_snapshot_and_journal(
    connection: &Connection,
    target_revision: i64,
) -> Result<clarix_editing_core::DocumentModel, PersistenceError> {
    let mut snapshot_statement = connection
        .prepare(
            "SELECT revision, model_json, model_sha256 FROM snapshots WHERE revision <= ?1 ORDER BY revision DESC",
        )
        .map_err(map_persistence)?;
    let snapshots = snapshot_statement
        .query_map(params![target_revision], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .map_err(map_persistence)?;
    let mut selected = None;
    for snapshot in snapshots {
        let (revision, model_json, checksum) = snapshot.map_err(map_persistence)?;
        if sha256_hex(model_json.as_bytes()) != checksum {
            continue;
        }
        if let Ok(model) = serde_json::from_str::<clarix_editing_core::DocumentModel>(&model_json) {
            selected = Some((revision, model));
            break;
        }
    }
    let (snapshot_revision, mut model) = selected.ok_or_else(|| {
        PersistenceError::Corrupt("no checksum-valid snapshot is available".into())
    })?;
    let mut command_statement = connection
        .prepare(
            "SELECT committed_revision, after_json, after_sha256 FROM commands WHERE committed_revision > ?1 AND committed_revision <= ?2 ORDER BY committed_revision ASC",
        )
        .map_err(map_persistence)?;
    let commands = command_statement
        .query_map(params![snapshot_revision, target_revision], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .map_err(map_persistence)?;
    for command in commands {
        let (revision, after_json, checksum) = command.map_err(map_persistence)?;
        if sha256_hex(after_json.as_bytes()) != checksum {
            return Err(PersistenceError::Corrupt(format!(
                "command revision {revision} checksum mismatch"
            )));
        }
        let objects = serde_json::from_str::<Vec<clarix_editing_core::DocumentObject>>(&after_json)
            .map_err(|error| PersistenceError::Corrupt(error.to_string()))?;
        let revision = u64::try_from(revision)
            .map(clarix_editing_core::DocumentRevision::from_value)
            .map_err(|_| PersistenceError::Corrupt("negative command revision".into()))?;
        model = model
            .replay_objects(objects, revision)
            .map_err(|error| PersistenceError::Corrupt(error.to_string()))?;
    }
    if model.revision.value()
        != u64::try_from(target_revision)
            .map_err(|_| PersistenceError::Corrupt("negative target revision".into()))?
    {
        return Err(PersistenceError::Corrupt(
            "journal does not reach the project revision".into(),
        ));
    }
    Ok(model)
}
