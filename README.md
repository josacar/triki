# Triki

[![Build Status](https://github.com/josacar/triki/workflows/Crystal%20CI/badge.svg)](https://github.com/josacar/triki/actions)
[![GitHub release](https://img.shields.io/github/v/release/josacar/triki)](https://github.com/josacar/triki/releases)

You want to develop against real production data, but you don't want to violate your users' privacy.  Enter Triki: standalone Crystal code for the selective rewriting of SQL dumps in order to protect user privacy.

# Documentation

API documentation is available at <https://josacar.github.io/triki/>.

# Table of Contents

- [Supported databases and versions](#supported-databases-and-versions)
- [Install](#install)
- [Quick Start](#quick-start)
- [Column Types & Configuration Options](#column-types--configuration-options)
- [Error Handling & Troubleshooting](#error-handling--troubleshooting)
- [Scaffolding](#scaffolding)
- [Speed](#speed)
- [Contributing](#contributing)
- [Thanks](#thanks)
- [License](#license)

# Supported databases and versions

## Servers

- MySQL
- Postgres
- SQL Server

## Clients

- `pg_dump` ( Postgresql ) up to 15.x
- `mysqldump` ( MySQL ) up to 8.2
- `mysqldump` ( MariaDB ) aka `mariadb-dump` ( since v0.3.0 ) up to 10.11

**Note**: Clients may break current SQL dump parsing as by now there is no proper integration testing in CI with all combinations of servers and clients versions, above versions have been partially manually tested.

# Install

Add this in your `shard.yml`

```
dependencies:
  triki:
    github: josacar/triki
```

And then run `shards install`

# Quick Start

### 1. Create an obfuscator script

```crystal
# obfuscator.cr
require "triki"

obfuscator = Triki.new({
  "users" => {
    "email"    => :email,
    "password" => { :type => :fixed, :string => "password123" },
    "name"     => :name,
  },
  "sessions" => :truncate,
  "roles"    => :keep,
})

obfuscator.obfuscate(STDIN, STDOUT)
```

### 2. Pipe a database dump through it

```bash
mysqldump -c -u user -ppassword mydb | crystal run obfuscator.cr > obfuscated.sql
```

That's it — every row in `users` gets anonymized, `sessions` is emptied, and `roles` passes through unchanged.

**Tip:** For large dumps, compile once and use the binary for much faster processing:

```bash
crystal build --release obfuscator.cr
mysqldump -c -u user -ppassword mydb | ./obfuscator > obfuscated.sql
```

# Example Usage

Make an obfuscator.cr script:

```crystal
require "triki"

obfuscator = Triki.new({
  "people" => {
    "email"                     => { :type => :email, :skip_regexes => [/^[\w\.\_]+@my_company\.com$/i] },
    "ethnicity"                 => :keep,
    "crypted_password"          => { :type => :fixed, :string => "SOME_FIXED_PASSWORD_FOR_EASE_OF_DEBUGGING" },
    "bank_account"              => { :type => :fixed, :string =>  ->(row : Triki::RowAsHash) { "#{row["bank_account"].to_s[0..4]}#{"*" * (row["email"].to_s.size - 5)}".as(Triki::RowContent) } },
    "salt"                      => { :type => :fixed, :string => "SOME_THING" },
    "remember_token"            => :null,
    "remember_token_expires_at" => :null,
    "age"                       => { :type => :null, :unless => ->(row : Triki::RowAsHash) { row["email"] == "hello@example.com" } },
    "photo_file_name"           => :null,
    "photo_content_type"        => :null,
    "photo_file_size"           => :null,
    "photo_updated_at"          => :null,
    "postal_code"               => { :type => :fixed, :string => "94109", :unless => ->(person : Triki::RowAsHash) { person["postal_code"] == "12345"} },
    "name"                      => :name,
    "full_address"              => :address,
    "bio"                       => { :type => :lorem, :number => 4 },
    "relationship_status"       => { :type => :fixed, :one_of => ["Single", "Divorced", "Married", "Engaged", "In a Relationship"] },
    "has_children"              => { :type => :integer, :between => 0..1 },
  },
  "invites"                     => :truncate,
  "invite_requests"             => :truncate,
  "tags"                        => :keep,
  "relationships" => {
    "account_id"                => :keep,
    "code"                      => { :type => :string, :length => 8, :chars => Triki::USERNAME_CHARS }
  }
})
obfuscator.fail_on_unspecified_columns = true # if you want it to require every column in the table to be in the above definition
obfuscator.globally_kept_columns = %w[id created_at updated_at] # if you set fail_on_unspecified_columns, you may want this as well

obfuscator.obfuscate(STDIN, STDOUT)
```

And to get an obfuscated dump:

```
mysqldump -c --add-drop-table --hex-blob -u user -ppassword database | obfuscator > obfuscated_dump.sql
```

For details on required mysqldump flags and troubleshooting common issues, see [Error Handling & Troubleshooting](#error-handling--troubleshooting) below.

## PostgreSQL & SQL Server

By default the database type is assumed to be MySQL, but you can use the builtin SQL Server and Postgres support by specifying:

```crystal
obfuscator.database_type = :sql_server
obfuscator.database_type = :postgres
```

If using Postgres, use `pg_dump` to get a dump:

```
pg_dump database | obfuscator > obfuscated_dump.sql
```

## Column Types & Configuration Options

### Simple types (shorthand)

Use the symbol directly: `"column_name" => :email`

### Table of all types

| Type | Description | Options | Example |
|------|-------------|---------|---------|
| `:email` | Generates a random email | `:skip_regexes` | `{ :type => :email, :skip_regexes => [/@mycompany\.com$/i] }` |
| `:string` | Random string of given length | `:length`, `:chars` | `{ :type => :string, :length => 8, :chars => Triki::USERNAME_CHARS }` |
| `:lorem` | Lorem ipsum text | `:number` (sentences) | `{ :type => :lorem, :number => 4 }` |
| `:like_english` | Real English sentences | `:number` (sentences) | `{ :type => :like_english, :number => 3 }` |
| `:name` | Full random name | — | `:name` |
| `:first_name` | First name only | — | `:first_name` |
| `:last_name` | Last name only | — | `:last_name` |
| `:address` | Full address (street, city, state, zip) | — | `:address` |
| `:street_address` | Street address only | — | `:street_address` |
| `:secondary_address` | Apt/Suite number | — | `:secondary_address` |
| `:city` | City name | — | `:city` |
| `:state` | State abbreviation | — | `:state` |
| `:zip_code` | US zip code | — | `:zip_code` |
| `:phone` | Phone number | — | `:phone` |
| `:company` | Company name | — | `:company` |
| `:ipv4` | IPv4 address | — | `:ipv4` |
| `:ipv6` | IPv6 address | — | `:ipv6` |
| `:url` | URL | — | `:url` |
| `:integer` | Random integer | `:between` (range) | `{ :type => :integer, :between => 18..65 }` |
| `:fixed` | Always the same value | `:string` or `:one_of` | `{ :type => :fixed, :string => "secret" }` or `{ :type => :fixed, :one_of => ["A", "B"] }` |
| `:null` | Sets value to NULL | — | `:null` |
| `:keep` | Keeps the original value | — | `:keep` |

### Conditional options

These options can be combined with any type above:

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `:skip_regexes` | `Array(Regex)` | Skip obfuscation if value matches any regex | `{ :type => :email, :skip_regexes => [/@internal\.com$/] }` |
| `:unless` | `Proc` or `:nil` or `:blank` | Skip obfuscation when condition is true | `{ :type => :null, :unless => :nil }` (only nullify non-null values) |
| `:if` | `Proc` or `:nil` or `:blank` | Only obfuscate when condition is true | `{ :type => :email, :if => :blank }` (only fill blank emails) |

The `:fixed` type also supports `:one_of` to randomly pick from an array:

```crystal
"status" => { :type => :fixed, :one_of => ["active", "inactive", "pending"] }
```

And `:fixed` supports procs for dynamic values based on the row:

```crystal
"masked_ssn" => { :type => :fixed, :string => ->(row) { "***-**-" + row["ssn"].to_s[-4..-1] } }
```

### Table-level actions

Instead of a column hash, use a symbol for the entire table:

| Action | Description |
|--------|-------------|
| `:truncate` | Remove all rows from the table |
| `:keep` | Pass the table through unchanged |

## Error Handling & Troubleshooting

### Configuration errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Column 'X' could not be found in table 'Y'` | A column in your config doesn't exist in the dump | Check your config for typos, or use `scaffold` to see the actual column names |
| `Column 'X' defined in table 'Y', but not found in table definition` | `fail_on_unspecified_columns = true` and a dump column has no config entry | Add the missing column to your config or add it to `globally_kept_columns` |
| `ERROR: Column X does not exist` | The config references a column not present in the INSERT statement | Same as above — verify column names match the dump |
| `ERROR: 'unless' definition does not return Bool or Symbol` | `:unless` value isn't a `Proc`, `:nil`, or `:blank` | Use one of the supported conditional values |
| `ERROR: 'if' definition does not return Bool or Symbol` | Same for `:if` | Same fix |
| `ERROR: 'length' or 'range' es not an Integer or a Range` | `:length` on a `:string` type isn't an integer or range | Pass an integer or range (e.g. `5..15`) |
| `table_config is not a hash` | Internal error — a table config is neither `:truncate`, `:keep`, nor a hash | Check your config structure |
| Unknown type warning | You used a `:type` symbol that isn't recognized | Replace with a valid type from the [Column Types](#column-types--configuration-options) table, or use `:keep` |

### Parsing errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Parse error: unexpected token begginning at …` | The MySQL dump wasn't generated with `-c` (column names) flag | Always use `mysqldump -c` |
| `Cannot obfuscate Postgres dumps containing INSERT statements` | Postgres dump used `INSERT` instead of `COPY` | Use `pg_dump` without `--inserts` or `--column-inserts` |

### Warnings (logged to STDERR)

| Warning | Cause | Fix |
|---------|-------|-----|
| `X was not specified in the config` | A table in the dump has no config entry and isn't `:keep` | Add the table to your config, or set it to `:keep` or `:truncate`. A future release may treat this as an error |

### Common issues

**mysqldump without `-c` won't work**
Triki relies on knowing column names to decide what to obfuscate. The `-c` flag (`--complete-insert`) is mandatory:
```bash
mysqldump -c --hex-blob -u user -ppassword database | obfuscator > out.sql
```

**Special characters in strings causing parse issues**
Use `--hex-blob` with mysqldump to hex-encode binary/blob content, which avoids quote-escaping edge cases:
```bash
mysqldump -c --hex-blob -u user -ppassword database | obfuscator > out.sql
```

**Very long lines causing MySQL errors**
For large dumps with many rows per INSERT, try:
```bash
mysqldump -c --hex-blob --max_allowed_packet=128M --single-transaction --skip-extended-insert --quick -u user -ppassword database | obfuscator > out.sql
```

**Newlines in MariaDB >= 10.7.1 dumps**
Triki handles newlines within INSERT statements automatically (since v0.3.0). No extra flags needed.

## Scaffolding

If you don't want to type all those table names and column names into your obfuscator.cr script,
you can use triki to do some of that work for you. It can consume your database dump file and create a "scaffold" for the script.
To run triki in this mode, start with an "empty" scaffolder.cr script as follows:

```crystal
obfuscator = Triki.new
obfuscator.scaffold(STDIN, STDOUT)
```

Then feed in your database dump:

```
mysqldump -c --hex-blob -u user -ppassword database | scaffolder > obfuscator_scaffold_snippet
pg_dump database | scaffolder > obfuscator_scaffold_snippet
```

The output will be a series of configuration statements of the form:

```crystal
  "table_name" => {
    "column1_name" => :keep   # scaffold
    "column2_name" => :keep   # scaffold
    ... etc.
```

Scaffolding also works if you have a partial configuration.  If your configuration is missing some tables or some columns, a call to 'scaffold' will pass through the configuration that exists and augment it with scaffolding for the missing tables or columns.

## Speed

The main motivation to rewrite this from Ruby to Crystal was speed, here is an example obfuscating 16 tables and 15 columns in total.

### MySQL dump 160MB (gzip'ed)

#### Ruby

```
real    1m56.980s
user    1m57.080s
sys     0m2.660s
```

#### Crystal

```
real    0m26.579s
user    0m28.220s
sys     0m1.748s
```

### MySQL dump 1.4G

#### Ruby

```
real    1m52.974s
user    1m49.824s
sys     0m4.560s
```

#### Crystal

```
real    0m17.642s
user    0m17.952s
sys     0m2.192s
```

That's about 6.40x speedup compared to the Ruby version.

## Contributing

1. Fork the project.
2. Create a feature branch for your change.
3. Add tests for any new functionality.
4. Run the test suite (`crystal spec`) and make sure everything passes.
5. Run the linter (`crystal bin/ameba`) and fix any issues.
6. Send a pull request.

## Thanks

Forked from [https://github.com/cantino/my_obfuscate](https://github.com/cantino/my_obfuscate)

Thanks to all of the authors and contributors of the original Ruby gem

## LICENSE

This work is provided under the MIT License.  See the included LICENSE file.

The included English word frequency list used for generating random text is provided under the Creative Commons – Attribution / ShareAlike 3.0 license by http://invokeit.wordpress.com/frequency-word-lists/
