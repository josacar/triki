class Triki
  module CopyStatementParser
    # Postgres uses COPY statements instead of INSERT and look like:
    #
    #   COPY some_table (a, b, c, d) FROM stdin;
    #   1	2	3	4
    #   5	6	7	8
    #   \.
    #
    # This requires the parse methods to persist data (table name and
    # column names) across multiple lines.
    #
    def parse(obfuscator, config, input_io, output_io)
      current_table_name = String.new
      current_columns = ColumnList.new
      inside_copy_statement = false

      input_io.each_line(chomp: false) do |line|
        if parse_insert_statement(line)
          raise RuntimeError.new("Cannot obfuscate Postgres dumps containing INSERT statements. Please use COPY statments.")
        elsif table_data = parse_copy_statement(line)
          inside_copy_statement = true

          current_table_name = table_data["table_name"].as(String)
          current_columns = table_data["column_names"].as(ColumnList)

          if !config[current_table_name]
            Log.warn { "Deprecated: #{current_table_name} was not specified in the config.  A future release will cause this to be an error.  Please specify the table definition or set it to :keep." }
          end

          output_io.print(line)
        elsif line.match /^\\\.$/
          inside_copy_statement = false

          output_io.print(line)
        elsif inside_copy_statement
          obfuscated_line = obfuscator.obfuscate_bulk_insert_statement(line, current_table_name, current_columns)
          output_io.puts(obfuscated_line) unless obfuscated_line.empty?
        else
          output_io.print(line)
        end
      end
    end
  end
end
