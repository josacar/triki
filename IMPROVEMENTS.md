# Triki Improvements Audit

## Bugs

### ~~BUG-1~~: Dead code `Array(Array(String?))` in `sql_server.cr:17` — **FIXED** (`7b53888`)
Moved from a bare type expression on line 17 to a proper return type annotation on the `def` line.

### ~~BUG-2~~: Long column names lose `:` prefix in scaffold output — **FIXED** (`e2971c2`)
`src/triki/config_scaffold_generator.cr:98` — In `formatted_line`, the `else` branch (long column names >= 40 chars) uses raw `definition` instead of `colon_string`, so Symbol definitions like `:keep` render as `keep` without the colon:
```crystal
# Line 96 (short columns) — correct:
%{    #{column_name.ljust(40)}  => #{colon_string},   #{comment}}
# Line 98 (long columns) — bug: uses `definition` instead of `colon_string`
%{    #{column_name} => #{definition},  #{comment}}
```
Fix: replace `definition` with `colon_string` on line 98.

### ~~BUG-3~~: `RuntimeError.new` with no message in `config_applicator.cr:134` — **FIXED** (`4d9fcd4`)`
```crystal
raise RuntimeError.new  # no message — debugging is impossible
```
Should include a descriptive message, e.g.:
```crystal
raise RuntimeError.new("Unknown conditional method: #{conditional_method}")
```

## Typos — **ALL FIXED** (`abe70c7`)

| File | Line | Typo | Fix |
|------|------|------|-----|
| `src/triki/config_applicator.cr` | 149 | `es not` | ~~`is not`~~ |
| `src/triki/mysql.cr` | 77 | `begginning` | ~~`beginning`~~ |
| `src/triki/postgres.cr` | 22 | `statments` | ~~`statements`~~ |
| `src/triki.cr` | 3 | Comment says only "MySQL dumps" | ~~Add Postgres and SQL Server~~ |

## Code Duplication

### ~~DUP-1~~: Deprecation warning string — **FIXED** (`0ce59ea`)`

### ~~DUP-2~~: `config_table_close` unused parameter — **FIXED** (`26fc8aa`)
`src/triki/config_scaffold_generator.cr:56` — `table_name` parameter accepted but never used in the body.

### ~~DUP-3~~: `ignore` parameter unused in Postgres and SqlServer — **FIXED** (`9bb923f`)
- `src/triki/postgres.cr:81`: `ignore = nil` — accepted but unused
- `src/triki/sql_server.cr:32`: `ignore = nil` — accepted but unused

Neither dialect supports INSERT IGNORE. Consider using separate method signatures or explicitly rejecting.

### ~~DUP-4~~: `make_insert_statement` `ignore` defaults to `nil` — **FIXED** (`0ce59ea`)`
`src/triki/mysql.cr:24` — `ignore = nil`. While `nil` is falsy and works, `false` better conveys intent (it's a boolean flag):
```crystal
def make_insert_statement(table_name, column_names, rows, ignore = false)
```

## Missing Abstract Methods in `base.cr` — **FIXED** (`e02ba32`)`

`src/triki/base.cr` only declares `parse`. It should also declare the shared interface:
```crystal
abstract struct Base
  abstract def parse(obfuscator, config, input_io, output_io)
  abstract def parse_insert_statement(line)
  abstract def make_insert_statement(table_name, column_names, values, ignore = false)
  abstract def make_valid_value_string(value)
  abstract def rows_to_be_inserted(line)
end
```
This would enforce consistent signatures and prevent regressions.

## ~~Missing / Incomplete Type Annotations~~ — **FIXED**

Added explicit parameter and return types across the codebase. All abstract methods in `base.cr` are now fully typed, and every concrete implementation in `Mysql`, `Postgres`, and `SqlServer` has matching signatures. `Triki#config` and `Triki#scaffolded_tables` properties now have explicit type annotations.

## Magic Numbers — **FIXED** (`9743190`)`

| File | Line | Value | Suggested Constant |
|------|------|-------|-------------------|
| `src/triki/config_applicator.cr` | 24 | `(0..1000)` | `DEFAULT_INTEGER_RANGE` |
| `src/triki/config_applicator.cr` | 54 | `30` | `DEFAULT_STRING_LENGTH` |
| `src/triki/config_scaffold_generator.cr` | 95-96 | `40` | `COLUMN_NAME_WIDTH` |
| `src/triki/mysql.cr` | 77 | `80` | `PARSE_ERROR_PEEK_LENGTH` |

## Inconsistent Error Handling — **FIXED** (`95ddc7b`)

### `raise` style inconsistency
- `triki.cr` and `postgres.cr`: Properly use `raise RuntimeError.new("message")`
- `config_applicator.cr:19,30,38,149`: Uses raw `raise "ERROR: ..."` (creates `Exception`, not `RuntimeError`)
- `config_applicator.cr:134`: Uses `raise RuntimeError.new` with NO message
- `mysql.cr:77`: Uses raw `raise "Parse error: ..."` (creates `Exception`)

Standardize on `raise RuntimeError.new("descriptive message")`.

## ~~Inconsistent Patterns Between Database Helpers~~ — **FIXED**

| Aspect | MySQL | Postgres | SqlServer |
|--------|-------|----------|-----------|
| `insert_regex` visibility | ~~Public~~ → `private` | N/A (inline) | `private` |
| `make_valid_value_string` quoting | `'value'` | raw (tab-sep) | `N'value'` |
| `make_insert_statement` `ignore` | Used | Unused | Unused |
| `parse_insert_statement` contract | Returns `Table` | Returns `MatchData`/nil | Returns `Table` |
| Log reference | ~~`Triki::Log`~~ → `Log` | ~~`Log` (unqualified)~~ → `Log` | ~~`Triki::Log`~~ → `Log` |

1. **`insert_regex` is `private` in both MySQL and SqlServer** — already correct.
2. **Log references unified to `Log.warn`** across all files (`0ce59ea`).

## ~~Naming Improvements~~ — **FIXED**

| Current | Suggested | Reason |
|---------|-----------|--------|
| `NUMBER_CHARS` → `DIGIT_CHARS` | Contains only digits, no decimal/sign |
| `my_row` → `transformed_row` | Meaningless name |
| `reassembling_each_insert` → `reassemble_each_insert` | Awkward grammar (gerund) |

## Performance

### ~~REGEX-1~~: MySQL string parser backtracking risk — **FIXED**
`src/triki/mysql.cr:68` now uses a character-class-based regex:
```crystal
scanner.scan(/'(?:[^'\\]|\\.)*'/)
```
This eliminates the `.` alternation that caused catastrophic backtracking risk.

### ~~REGEX-2~~: SqlServer `rows_to_be_inserted` uses 4 chained `gsub` calls — **FIXED**
`src/triki/sql_server.cr:18` now uses `lstrip`/`rstrip`/`sub` instead of four sequential `gsub`s:
```crystal
values_str = values_str.lstrip('(').rstrip("; \t\n").sub(/\)$/, "")
```
This avoids allocating four intermediate strings.

## Minor

- ~~**`config_applicator.cr:14-15`**~~: `transformed_row = row.map { |v| v.as(RowContent) }` — **FIXED**
- **`triki.cr:28`**: ~~Log binding `"*"` captures ALL log sources~~ → changed to `"triki"`. **FIXED**
- **`config_scaffold_generator.cr:48`**: ~~Writes `\0` (null byte) to output~~ → removed, now writes plain newline. **FIXED**
- **`config_scaffold_generator.cr:87-91`**: ~~Type detection via `definition.to_s[0]` is fragile~~ → replaced with `case`/`is_a?` check. **FIXED**
- ~~**`postgres.cr:59`**~~: `row[last] = row[last].strip if last >= 0` — guard already present. **FIXED**
- **`config_applicator.cr:50`**: ~~`Digest::MD5` truncated to 5 hex chars~~ → `Digest::SHA256` with 10 hex chars. **FIXED**
