# pglite-fusion

Embed an SQLite database in your PostgreSQL table. AKA multitenancy has been solved.

## Usage

Run a PostgreSQL 17 database that has `pglite-fusion` already installed.

```bash
docker run --network=host frectonz/pglite-fusion
```

`pglite-fusion` is also distributed with other PostgreSQL versions.

### PostgreSQL 12

```bash
docker run --network=host frectonz/pglite-fusion:pg12
```

### PostgreSQL 13

```bash
docker run --network=host frectonz/pglite-fusion:pg13
```

### PostgreSQL 14

```bash
docker run --network=host frectonz/pglite-fusion:pg14
```

### PostgreSQL 15

```bash
docker run --network=host frectonz/pglite-fusion:pg15
```

### PostgreSQL 16

```bash
docker run --network=host frectonz/pglite-fusion:pg16
```

### PostgreSQL 17

```bash
docker run --network=host frectonz/pglite-fusion:pg17
```

Connect to the PostgreSQL database using `psql`.

```bash
psql postgresql://postgres@localhost:5432/
```

Here's some demo usage.

```sql
-- Load PG extension
CREATE EXTENSION pglite_fusion;

-- Create a table with an SQLite column
CREATE TABLE people (
    name     TEXT NOT NULL,
    database SQLITE DEFAULT init_sqlite('CREATE TABLE todos (task TEXT)')
);

-- Insert a row into the people table
INSERT INTO people VALUES ('frectonz');

-- Create a todo for "frectonz"
UPDATE people
SET database = execute_sqlite(
    database,
    'INSERT INTO todos VALUES (''solve multitenancy'')'
)
WHERE name = 'frectonz';

-- Create a todo for "frectonz"
UPDATE people
SET database = execute_sqlite(
    database,
    'INSERT INTO todos VALUES (''buy milk'')'
)
WHERE name = 'frectonz';

-- Fetch frectonz's info
SELECT 
    name, 
    (
        SELECT json_agg(get_sqlite_text(sqlite_row, 0))
        FROM query_sqlite(
            database, 
            'SELECT * FROM todos'
        )
    ) AS todos
FROM 
    people 
WHERE 
    name = 'frectonz';
```

## Build it from source

```bash
git clone git@github.com:frectonz/pglite-fusion.git 
cd pglite-fusion
nix develop
cargo pgrx init --pg13 download # this will take some time, since you are compiling postgres from source
cargo pgrx run # this will drop you into a psql repl, you can then follow the example shown above
```

## API Documentation

Every function is parallel-safe except for `import_sqlite_from_file` and `export_sqlite_to_file`.

### `empty_sqlite`

Creates an empty SQLite database and returns it as a binary object. This can be used to initialize an empty SQLite database in a PostgreSQL column.

#### Example Usage:

```sql
SELECT empty_sqlite();
```

-----

### `query_sqlite`

Executes a SQL query on a SQLite database stored as a binary object and returns the result as a table of JSON-encoded rows. This function is useful for querying SQLite databases stored in PostgreSQL columns.

#### Parameters:

- `sqlite`: The SQLite database to query, stored as a binary object.
- `query`: The SQL query string to execute on the SQLite database.

#### Example Usage:

```sql
SELECT * FROM query_sqlite(
    database, 
    'SELECT * FROM todos'
);
```

-----

### `execute_sqlite`

Executes a SQL statement (such as `INSERT`, `UPDATE`, or `DELETE`) on a SQLite database stored as a binary object. The updated SQLite database is returned as a binary object, allowing further operations on it.

#### Parameters:

- `sqlite`: The SQLite database to execute the SQL query on, stored as a binary object.
- `query`: The SQL statement to execute on the SQLite database.

#### Example Usage:

```sql
UPDATE people
SET database = execute_sqlite(
    database,
    'INSERT INTO todos VALUES (''solve multitenancy'')'
)
WHERE name = 'frectonz';
```

-----

### `init_sqlite`

Creates an SQLite database with an initialization query already applied on it. This can be used to initialize a SQLite database with the expected tables already created.

#### Parameters:

- `query`: The SQL statement to execute on the SQLite database.

#### Example Usage:

```sql

CREATE TABLE people (
    name     TEXT NOT NULL,
    database SQLITE DEFAULT init_sqlite('CREATE TABLE todos (task TEXT)')
);
```

-----

### `get_sqlite_text`
Extracts a text value from a specific column in a row returned by `query_sqlite`. Use this function to retrieve text values from query results.

#### Parameters:

- `sqlite_row`: A row from the results of `query_sqlite`.
- `index`: The index of the column to extract from the row.

#### Example Usage:

```sql
SELECT get_sqlite_text(sqlite_row, 0) 
FROM query_sqlite(database, 'SELECT * FROM todos');
```

----

### `get_sqlite_integer`

Extracts an integer value from a specific column in a row returned by `query_sqlite`. Use this function to retrieve integer values from query results.

#### Parameters:

- `sqlite_row`: A row from the results of `query_sqlite`.
- `index`: The index of the column to extract from the row.

#### Example Usage:

```sql
SELECT get_sqlite_integer(sqlite_row, 1) 
FROM query_sqlite(database, 'SELECT * FROM todos');
```

----

### `get_sqlite_real`

Extracts a real (floating-point) value from a specific column in a row returned by `query_sqlite`. Use this function to retrieve real number values from query results.

#### Parameters:

- `sqlite_row`: A row from the results of `query_sqlite`.
- `index`: The index of the column to extract from the row.

#### Example Usage:

```sql
SELECT get_sqlite_real(sqlite_row, 2) 
FROM query_sqlite(database, 'SELECT * FROM todos');
```

---

### `list_sqlite_tables`

Lists all table names present in the SQLite database.

#### Parameters:

- `sqlite`: A SQLite database stored as a binary blob.

#### Example Usage:

```sql
SELECT table_name FROM list_sqlite_tables(database);
```

---

### `sqlite_schema`

Retrieves the SQL schema of each table in the SQLite database, the CREATE TABLE statements for each table in the SQLite database.

#### Parameters:

- `sqlite`: A SQLite database stored as a binary blob.

#### Example Usage:

```sql
SELECT schema_sql FROM sqlite_schema(database);
```

---

### `import_sqlite_from_file`

Loads a SQLite database from a file into PostgreSQL.

#### Parameters:

- `path`: The file path of the SQLite database to load.

#### Example Usage:

```sql
SELECT import_sqlite_from_file('/tmp/mydb.sqlite');
```

---

### `export_sqlite_to_file`

Saves the SQLite database to a file on disk.

#### Parameters:

- `sqlite`: The SQLite database.
- `path`: The file path where the database should be saved.

#### Example Usage:

```sql
SELECT export_sqlite_to_file(database, '/tmp/mydb.sqlite');
```

---

### `vacuum_sqlite`

Runs the SQLite `VACUUM` command to optimize storage by reclaiming unused space.

#### Parameters:

- `sqlite`: The SQLite database.

#### Example Usage:

```sql
SELECT vacuum_sqlite(database);
```

---

### `count_sqlite_rows`

Counts the number of rows in a specified table within the SQLite database.

#### Parameters:

- `sqlite`: The SQLite database.
- `table`: The name of the table to count rows from.

#### Example Usage:

```sql
SELECT count_sqlite_rows(database, 'users');
```
