class Triki
  # Shared parsing logic for dialects that use semicolon-terminated INSERT statements.
  #
  # Included by `Mysql` and `SqlServer`.
  module InsertStatementParser
    # Iterates over the dump, parsing each INSERT statement and applying obfuscation.
    def parse(obfuscator : Triki, config : ConfigHash, input_io : IO, output_io : IO) : Nil
      while statement = input_io.gets(";\n")
        if table_data = parse_insert_statement(statement)
          table_name = table_data[:table_name]
          columns = table_data[:column_names]
          ignore = table_data["ignore"]?

          if config[table_name]?
            output_io.puts obfuscator.obfuscate_bulk_insert_statement(statement, table_name, columns, ignore)
          else
            Log.warn { "Deprecated: #{table_name} #{DEPRECATION_WARNING}" }
            output_io.print(statement)
          end
        else
          output_io.print(statement)
        end
      end
    end
  end
end
