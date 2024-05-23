class Triki
  struct Postgres < Base
    alias Table = NamedTuple(table_name: String, column_names: ColumnList)
    include Triki::ConfigScaffoldGenerator

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
        raise RuntimeError.new("Cannot obfuscate Postgres dumps containing INSERT statements. Please use COPY statments.") if parse_insert_statement(line)

        if table_data = parse_copy_statement(line)
          inside_copy_statement = true

          current_table_name = table_data[:table_name]
          current_columns = table_data[:column_names]

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

    # Copy statements contain the column values tab separated like so:
    #   blah	blah	blah	blah
    # which we want to turn into:
    #   [['blah','blah','blah','blah']]
    #
    # We wrap it in an array to keep it consistent with MySql bulk
    # obfuscation (multiple rows per insert statement)
    def rows_to_be_inserted(line) : Array(Array(String?))
      row = line.split(/\t/)

      last = row.size - 1
      row[last] = row[last].strip

      row = row.map do |value|
        if value == "\\N"
          nil
        else
          value
        end
      end

      [row]
    end

    def parse_copy_statement(line)
      return unless regex_match = /^\s*COPY (.*?) \((.*?)\) FROM\s*/i.match(line)

      Table.new(
        table_name: regex_match[1],
        column_names: regex_match[2].split(/\s*,\s*/),
      )
    end

    def make_insert_statement(table_name, column_names, values, ignore = nil)
      values.flatten.join('\t')
    end

    def make_valid_value_string(value)
      if value.nil?
        "\\N"
      else
        value
      end
    end

    def parse_insert_statement(line)
      /^\s*INSERT INTO/i.match(line)
    end
  end
end
