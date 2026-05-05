# AGENTS.md — Triki Developer Guide

## Project Overview

**Triki** is a Crystal library for selectively rewriting (obfuscating/anonymizing) SQL dumps to protect user privacy. It parses dumps from MySQL, PostgreSQL, and SQL Server and rewrites sensitive columns with fake data.

- **Version**: 0.3.2
- **Language**: Crystal ~> 1.0
- **License**: MIT
- **Repository**: <https://github.com/josacar/triki>

## Quick Start

```bash
# Install dependencies
shards install

# Run tests
crystal spec

# Run linter
bin/ameba

# Build (compile a custom script that uses triki)
crystal build --release obfuscator.cr
```

## Project Structure

```
src/
├── triki.cr                        # Main entry point – Triki class
└── triki/
    ├── base.cr                     # Abstract base class for database helpers
    ├── mysql.cr                    # MySQL dump parser & writer
    ├── postgres.cr                 # PostgreSQL COPY parser & writer
    ├── sql_server.cr               # SQL Server parser & writer
    ├── config_applicator.cr        # Applies obfuscation rules to rows
    ├── config_parser.cr            # Parses/validates configuration hashes
    ├── config_scaffold_generator.cr# Generates scaffold configs from dumps
    ├── insert_statement_parser.cr  # Shared INSERT parsing mixin
    ├── english_dictionary.cr       # Word list for lorem generation
    ├── faker.cr                    # Faker wrapper for fake data generation
    └── version.cr                  # VERSION constant

spec/
├── spec_helper.cr
├── triki_spec.cr                   # Main spec (~1100 lines)
└── triki/
    ├── config_applicator_spec.cr
    ├── mysql_spec.cr
    ├── postgres_spec.cr
    └── sql_server_spec.cr

IMPROVEMENTS.md                     # Living audit of bugs, duplication, and style issues
```

## Architecture

### Core Flow

1. **`Triki.new(config)`** – Accepts a configuration hash defining per-table, per-column obfuscation rules.
2. **`obfuscate(input_io, output_io)`** – Delegates to a `database_helper` (MySQL/Postgres/SqlServer) based on `database_type`.
3. **Database Helper** – Parses INSERT/COPY statements line-by-line, yields rows to `ConfigApplicator`, which applies transformations using `Faker`, then reassembles the output.

### Configuration Types

Each table can be:
- `:truncate` – Remove all rows
- `:keep` – Pass through unchanged
- A hash of column → action

Column actions include: `:email`, `:name`, `:first_name`, `:last_name`, `:address`, `:string`, `:integer`, `:fixed`, `:null`, `:lorem`, `:keep`, and more. See README for full list.

### Key Classes

| Class | Purpose |
|-------|---------|
| `Triki` | Main facade; holds config, delegates to database helper |
| `Base` | Abstract database helper interface |
| `Mysql` / `Postgres` / `SqlServer` | Concrete parsers for each dump format |
| `ConfigApplicator` | Applies column rules to each row |
| `ConfigParser` | Casts & validates configuration bindings |
| `ConfigScaffoldGenerator` | Generates config scaffolds from real dumps |

## Conventions

### Code Style

- **Crystal idiomatic style** – follow `crystal tool format` output
- **Ameba linter** – config in `.ameba.yml` (GuardClause enabled). Run `bin/ameba` and `crystal tool format` before every commit.
- **Indentation**: 2 spaces (see `.editorconfig`)
- **Naming**: `snake_case` for methods/variables, `PascalCase` for types
- **Error raising**: Use `raise RuntimeError.new("descriptive message")` consistently — avoid bare `raise "string"` or `raise RuntimeError.new` without a message

### Testing

- Framework: `crystal spec` (built-in)
- Specs live in `spec/`
- Use `Log.capture("triki")` to test log output
- Use `expect_raises(RuntimeError)` for error expectations
- Avoid duplicating large config hashes across nested contexts — extract shared configs to variables in the parent `describe`/`context` block
- For repetitive spec calls, define a file-private helper (e.g., `spec/triki/config_applicator_spec.cr` uses a top-level `apply` method to wrap `ConfigApplicator.apply_table_config` with default row/columns)

### Type Aliases

The main `Triki` class defines many type aliases (`RowAsHash`, `ConfigColumn`, etc.). Use these in new code rather than raw types.

## Adding a New Database Type

1. Create `src/triki/new_database.cr` extending `Base`
2. Implement: `parse_insert_statement`, `make_insert_statement`, `rows_to_be_inserted`, `make_valid_value_string`, `insert_regex`
3. Add a `when` branch in `database_helper` method in `triki.cr`
4. Add specs in `spec/triki/new_database_spec.cr`

## Adding a New Obfuscation Type

1. Add the type symbol in `ConfigApplicator.apply_table_config`
2. Implement the generation logic (use `Faker` where applicable)
3. Document in README
4. Add specs

## Useful Commands

| Command | Description |
|---------|-------------|
| `crystal spec` | Run all tests |
| `crystal spec spec/triki/triki_spec.cr` | Run main spec |
| `bin/ameba` | Run linter |
| `crystal tool format` | Format code |
| `crystal docs` | Generate API docs |

## Dependencies

- **walker_method** – Helper for walking/traversing structures
- **faker** – Fake data generation (names, emails, addresses, etc.)
- **ameba** (dev) – Static analysis / linting

## Known Issues & Improvements

See `IMPROVEMENTS.md` for a living audit of remaining bugs, code duplication, missing type annotations, and style inconsistencies. Update it when issues are resolved.

## CI/CD

GitHub Actions (`.github/workflows/`):
- `crystal.yml` – Runs tests on multiple Crystal versions
- `docs.yml` – Generates and deploys API documentation
