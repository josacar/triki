class Triki
  # Abstract base for database-specific dump parsers.
  #
  # Concrete implementations (`Mysql`, `Postgres`, `SqlServer`) handle
  # parsing INSERT/COPY statements, extracting rows, reassembling output,
  # and quoting values for their respective dialects.
  abstract struct Base
    # Parses the full dump stream, applying obfuscation rules.
    abstract def parse(obfuscator : Triki, config : ConfigHash, input_io : IO, output_io : IO) : Nil

    # Reassembles an INSERT/COPY statement from the given rows.
    abstract def make_insert_statement(table_name : String, column_names : ColumnList, values : Array(Array(RowContent)), ignore = false) : String

    # Extracts rows of values from a single INSERT/COPY line.
    abstract def rows_to_be_inserted(line : String) : Array(Array(String?))

    # Quotes or formats a single value for the target database dialect.
    abstract def make_valid_value_string(value : RowContent) : RowContent
  end
end
