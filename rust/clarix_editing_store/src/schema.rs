use rusqlite::Connection;

use crate::StoreError;

pub const SCHEMA_VERSION: i64 = 1;

pub fn initialize(connection: &Connection) -> Result<(), StoreError> {
    connection.execute_batch(
        r#"
        PRAGMA foreign_keys = ON;
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = FULL;
        PRAGMA busy_timeout = 5000;
        "#,
    )?;
    let current: i64 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if current > SCHEMA_VERSION {
        return Err(StoreError::SchemaTooNew(current));
    }
    if current == 0 {
        connection.execute_batch(
            r#"
            BEGIN IMMEDIATE;
            CREATE TABLE project (
                singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                document_id TEXT NOT NULL,
                source_fingerprint TEXT NOT NULL,
                revision INTEGER NOT NULL,
                model_json TEXT NOT NULL,
                model_sha256 TEXT NOT NULL,
                undo_cursor INTEGER NOT NULL,
                materialized_revision INTEGER
            );
            CREATE TABLE source_revisions (revision INTEGER PRIMARY KEY, fingerprint TEXT NOT NULL);
            CREATE TABLE pages (page_id TEXT PRIMARY KEY, page_number INTEGER NOT NULL, payload_json TEXT NOT NULL);
            CREATE TABLE page_index_state (page_id TEXT PRIMARY KEY, state TEXT NOT NULL);
            CREATE TABLE objects (object_id TEXT PRIMARY KEY, page_id TEXT NOT NULL, payload_json TEXT NOT NULL);
            CREATE TABLE text_runs (object_id TEXT NOT NULL, ordinal INTEGER NOT NULL, payload_json TEXT NOT NULL, PRIMARY KEY(object_id, ordinal));
            CREATE TABLE styles (style_id TEXT PRIMARY KEY, payload_json TEXT NOT NULL);
            CREATE TABLE source_bindings (object_id TEXT PRIMARY KEY, payload_json TEXT NOT NULL);
            CREATE TABLE text_index (object_id TEXT PRIMARY KEY, normalized_text TEXT NOT NULL);
            CREATE TABLE commands (
                command_id TEXT PRIMARY KEY,
                previous_revision INTEGER NOT NULL,
                committed_revision INTEGER NOT NULL UNIQUE,
                envelope_json TEXT NOT NULL,
                before_json TEXT NOT NULL,
                after_json TEXT NOT NULL,
                after_sha256 TEXT NOT NULL
            );
            CREATE TABLE inverse_operations (
                command_id TEXT PRIMARY KEY REFERENCES commands(command_id) ON DELETE CASCADE,
                inverse_json TEXT NOT NULL
            );
            CREATE TABLE snapshots (
                revision INTEGER PRIMARY KEY,
                model_json TEXT NOT NULL,
                model_sha256 TEXT NOT NULL,
                undo_cursor INTEGER NOT NULL
            );
            CREATE TABLE selections (selection_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, payload_json TEXT NOT NULL);
            CREATE TABLE checkpoints (label TEXT NOT NULL, revision INTEGER NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(label, revision));
            CREATE TABLE materializations (revision INTEGER PRIMARY KEY, output_sha256 TEXT NOT NULL, target_path TEXT NOT NULL);
            CREATE TABLE assets (sha256 TEXT PRIMARY KEY, metadata_json TEXT NOT NULL);
            CREATE TABLE previews (cache_key TEXT PRIMARY KEY, metadata_json TEXT NOT NULL);
            CREATE TABLE migration_log (from_version INTEGER NOT NULL, to_version INTEGER NOT NULL, completed_at TEXT NOT NULL);
            PRAGMA user_version = 1;
            COMMIT;
            "#,
        )?;
    }
    Ok(())
}
