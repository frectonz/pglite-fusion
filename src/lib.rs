use std::time::Duration;

use pgrx::prelude::*;
use rusqlite::backup::Backup;
use rusqlite::serialize::OwnedData;
use rusqlite::Connection;
use rusqlite::{types::Value as SqliteValue, DatabaseName};
use serde::{Deserialize, Serialize};

pgrx::pg_module_magic!();

#[derive(Serialize, Deserialize, PostgresType)]
struct Sqlite {
    data: Vec<u8>,
}

impl Sqlite {
    fn load(self) -> Connection {
        let mut buf = self.data;

        let src_ptr = buf.as_mut_ptr();
        let src_len = buf.len();
        std::mem::forget(buf);

        let mut conn =
            Connection::open_in_memory().expect("couldn't open an sqlite database in memory");

        unsafe {
            // Allocate memory acording to pointer
            let res_ptr = rusqlite::ffi::sqlite3_malloc(src_len as std::ffi::c_int)
                .cast::<std::ffi::c_uchar>();
            let res_ptr: std::ptr::NonNull<u8> =
                std::ptr::NonNull::new(res_ptr).expect("ptr on db deserialization was null");

            let buf: *mut std::ffi::c_uchar = res_ptr.as_ptr();
            src_ptr.copy_to_nonoverlapping(buf, src_len);

            let data = OwnedData::from_raw_nonnull(res_ptr, src_len);

            conn.deserialize(DatabaseName::Main, data, false)
                .expect("couldn't deserialize the sqlite database");
        }

        conn
    }

    fn dump(conn: Connection) -> Self {
        let data = conn
            .serialize(DatabaseName::Main)
            .expect("couldn't serialize database")
            .to_vec();

        Self { data }
    }
}

#[pg_extern(volatile, parallel_safe)]
fn empty_sqlite() -> Sqlite {
    let conn = Connection::open_in_memory().expect("couldn't create sqlite database");
    Sqlite::dump(conn)
}

#[pg_extern(strict, volatile, parallel_safe)]
fn init_sqlite(query: &str) -> Sqlite {
    let conn = Connection::open_in_memory().expect("couldn't create sqlite database");
    conn.execute_batch(query).expect("query execution failed");
    Sqlite::dump(conn)
}

#[pg_extern(strict, volatile, parallel_unsafe)]
fn import_sqlite_from_file(path: &str) -> Sqlite {
    let conn = Connection::open(path).expect("couldn't create sqlite database");
    Sqlite::dump(conn)
}

#[pg_extern(strict, volatile, parallel_unsafe)]
fn export_sqlite_to_file(sqlite: Sqlite, path: &str) -> bool {
    let src = sqlite.load();
    let mut dest = Connection::open(path).expect("couldn't create sqlite database");

    let backup = Backup::new(&src, &mut dest).expect("couldn't create backup operation");
    backup
        .run_to_completion(5, Duration::from_millis(250), None)
        .is_ok()
}

#[pg_extern(strict, volatile, parallel_safe)]
fn execute_sqlite(sqlite: Sqlite, query: &str) -> Sqlite {
    let conn = sqlite.load();
    conn.execute_batch(query).expect("query execution failed");

    Sqlite::dump(conn)
}

#[pg_extern(strict, volatile, parallel_safe)]
fn vacuum_sqlite(sqlite: Sqlite) -> Sqlite {
    execute_sqlite(sqlite, "VACUUM")
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

#[pg_extern(strict, stable, parallel_safe)]
fn query_sqlite(sqlite: Sqlite, query: &str) -> TableIterator<'_, (name!(sqlite_row, SqliteRow),)> {
    let table = {
        let conn = sqlite.load();
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

#[pg_extern(strict, stable, parallel_safe)]
fn list_sqlite_tables(sqlite: Sqlite) -> TableIterator<'static, (name!(table_name, String),)> {
    let table = {
        let conn = sqlite.load();
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

#[pg_extern(strict, stable, parallel_safe)]
fn sqlite_schema(sqlite: Sqlite) -> TableIterator<'static, (name!(schema_sql, String),)> {
    let table = {
        let conn = sqlite.load();
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

#[pg_extern(strict, stable, parallel_safe)]
fn count_sqlite_rows(sqlite: Sqlite, table: &str) -> i32 {
    // Validate table name (only allow alphanumeric and underscores)
    if !table.chars().all(|c| c.is_alphanumeric() || c == '_') {
        panic!("Invalid table name: {}", table);
    }

    {
        let conn = sqlite.load();
        let count: i32 = conn
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), (), |row| {
                row.get(0)
            })
            .expect("couldn't query row count for given table");
        count
    }
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
