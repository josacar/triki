class Triki
  module InsertStatementParser
    def parse(obfuscator, config, input_io, output_io)
      while statement = input_io.gets(";\n")
        if table_data = parse_insert_statement(statement)
          table_name = table_data[:table_name]
          columns = table_data[:column_names]
          ignore = table_data["ignore"]?

          if config[table_name]?
            output_io.puts obfuscator.obfuscate_bulk_insert_statement(statement, table_name, columns, ignore)
          else
            Triki::Log.warn { "Deprecated: #{table_name} was not specified in the config.  A future release will cause this to be an error.  Please specify the table definition or set it to :keep." }
            output_io.print(statement)
          end
        else
          output_io.print(statement)
        end
      end
    end
  end
end
