use std::{env, fs, path::PathBuf};

use pgrx::prelude::*;
use rusqlite::types::Value as SqliteValue;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use ulid::Ulid;

pgrx::pg_module_magic!();

#[derive(Serialize, Deserialize, PostgresType)]
struct Sqlite {
    data: Vec<u8>,
}

fn temp_file() -> PathBuf {
    let temp_dir = env::temp_dir();
    let ulid = Ulid::new();
    let file_name = format!("pglite-fusion-{ulid}.sqlite3");
    temp_dir.join(file_name)
}

#[pg_extern(volatile, parallel_unsafe)]
fn empty_sqlite() -> Sqlite {
    let temp = temp_file();
    {
        Connection::open(&temp).expect("couldn't create sqlite database");
    }

    let data = fs::read(&temp).expect("couldn't read newly created sqlite database file");
    Sqlite { data }
}

#[pg_extern(volatile, parallel_unsafe)]
fn init_sqlite(query: &str) -> Sqlite {
    let temp = temp_file();
    {
        let conn = Connection::open(&temp).expect("couldn't create sqlite database");
        conn.execute_batch(query).expect("query execution failed");
    }

    let data = fs::read(&temp).expect("couldn't read newly created sqlite database file");
    Sqlite { data }
}

#[pg_extern(volatile, parallel_unsafe)]
fn execute_sqlite(sqlite: Sqlite, query: &str) -> Sqlite {
    let temp = temp_file();
    fs::write(&temp, sqlite.data).expect("failed to create a temprary sqlite database file");

    {
        let conn = Connection::open(&temp).expect("couldn't open sqlite database");
        conn.execute_batch(query).expect("query execution failed");
    }

    let data = fs::read(&temp).expect("couldn't read newly created sqlite database file");
    Sqlite { data }
}

#[pg_extern(immutable, parallel_safe)]
fn is_valid_sqlite(sqlite: Sqlite) -> bool {
    let temp = temp_file();
    if fs::write(&temp, sqlite.data).is_err() {
        return false;
    }

    Connection::open(&temp).is_ok()
}

type SqliteRow = Vec<pgrx::Json>;

#[pg_extern(strict, immutable, parallel_safe)]
fn get_sqlite_text(mut row: SqliteRow, index: i32) -> Option<String> {
    let col = row.remove(index as usize);
    if let pgrx::Json(serde_json::Value::String(text)) = col {
        Some(text)
    } else {
        None
    }
}

#[pg_extern(strict, immutable, parallel_safe)]
fn get_sqlite_integer(mut row: SqliteRow, index: i32) -> Option<i64> {
    let col = row.remove(index as usize);
    col.0.as_i64()
}

#[pg_extern(strict, immutable, parallel_safe)]
fn get_sqlite_real(mut row: SqliteRow, index: i32) -> Option<f64> {
    let col = row.remove(index as usize);
    col.0.as_f64()
}

#[pg_extern(volatile, parallel_unsafe)]
fn query_sqlite(sqlite: Sqlite, query: &str) -> TableIterator<'_, (name!(sqlite_row, SqliteRow),)> {
    let temp = temp_file();
    fs::write(&temp, sqlite.data).expect("failed to create a temprary sqlite database file");

    let table = {
        let conn = Connection::open(&temp).expect("couldn't open sqlite database");
        let mut stmt = conn.prepare(query).expect("couldn't prepare sqlite query");

        let columns_len = stmt.column_count();
        stmt.query_map((), |row| {
            let mut rows = Vec::with_capacity(columns_len);
            for i in 0..columns_len {
                let val = rusqlite_value_to_json(row.get(i)?);
                rows.push(pgrx::Json(val));
            }
            Ok((rows,))
        })
        .expect("query execution failed")
        .collect::<Result<Vec<_>, _>>()
        .expect("sqlite query returned an unexpected row")
    };

    TableIterator::new(table)
}

#[pg_extern(volatile, parallel_unsafe)]
fn list_sqlite_tables(sqlite: Sqlite) -> TableIterator<'static, (name!(table_name, String),)> {
    let temp = temp_file();
    fs::write(&temp, sqlite.data).expect("failed to create a temprary sqlite database file");

    let table = {
        let conn = Connection::open(&temp).expect("couldn't open sqlite database");
        let mut stmt = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table'")
            .expect("couldn't prepare sqlite query");

        stmt.query_map((), |row| {
            let name = row.get::<_, String>(0)?;
            Ok((name,))
        })
        .expect("query execution failed")
        .collect::<Result<Vec<_>, _>>()
        .expect("sqlite query returned an unexpected row")
    };

    TableIterator::new(table)
}

#[pg_extern(volatile, parallel_unsafe)]
fn sqlite_schema(sqlite: Sqlite) -> TableIterator<'static, (name!(schema_sql, String),)> {
    let temp = temp_file();
    fs::write(&temp, sqlite.data).expect("failed to create a temprary sqlite database file");

    let table = {
        let conn = Connection::open(&temp).expect("couldn't open sqlite database");
        let mut stmt = conn
            .prepare("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL")
            .expect("couldn't prepare sqlite query");

        stmt.query_map((), |row| {
            let sql = row.get::<_, String>(0)?;
            Ok((sql,))
        })
        .expect("query execution failed")
        .collect::<Result<Vec<_>, _>>()
        .expect("sqlite query returned an unexpected row")
    };

    TableIterator::new(table)
}

fn rusqlite_value_to_json(v: SqliteValue) -> serde_json::Value {
    use SqliteValue::*;
    match v {
        Null => serde_json::Value::Null,
        Integer(x) => serde_json::json!(x),
        Real(x) => serde_json::json!(x),
        Text(s) => serde_json::Value::String(s),
        Blob(s) => serde_json::json!(s),
    }
}

#[cfg(any(test, feature = "pg_test"))]
#[pg_schema]
mod tests {
    use pgrx::prelude::*;

    #[pg_test]
    fn test_hello_pglite_fusion() {}
}

/// This module is required by `cargo pgrx test` invocations.
/// It must be visible at the root of your extension crate.
#[cfg(test)]
pub mod pg_test {
    pub fn setup(_options: Vec<&str>) {
        // perform one-off initialization when the pg_test framework starts
    }

    pub fn postgresql_conf_options() -> Vec<&'static str> {
        // return any postgresql.conf settings that are required for your tests
        vec![]
    }
}
