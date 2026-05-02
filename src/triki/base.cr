class Triki
  abstract struct Base
    abstract def parse(obfuscator : Triki, config : ConfigHash, input_io : IO, output_io : IO)
    abstract def make_insert_statement(table_name : String, column_names : ColumnList, values : Array(Array(RowContent)), ignore = false) : String
    abstract def rows_to_be_inserted(line : String) : Array(Array(String?))
    abstract def make_valid_value_string(value : RowContent) : RowContent
  end
end
