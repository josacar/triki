class Triki
  module ConfigScaffoldGenerator
    def generate_config(obfuscator, config, input_io, output_io)
      buffer = IO::Memory.new

      input_io.each_line(chomp: false) do |line|
        if obfuscator.database_type == :postgres
          parse_copy_statement = ->(statement_line : String) do
            if regex_match = /^\s*COPY (.*?) \((.*?)\) FROM\s*/i.match(statement_line)
              {
                "table_name"   => regex_match[1],
                "column_names" => regex_match[2].split(/\s*,\s*/),
              }
            end
          end
          table_data = parse_copy_statement.call(line)
        else
          table_data = parse_insert_statement(line)
        end
        next unless table_data

        table_name = table_data["table_name"].as(String)
        next if obfuscator.scaffolded_tables[table_name]? # only process each table_name once

        columns = table_data["column_names"].as(Array(String))
        table_config = config[table_name]?
        next if table_config == :truncate || table_config == :keep

        missing_columns = obfuscator.missing_column_list(table_name, columns)
        extra_columns = obfuscator.extra_column_list(table_name, columns)

        if buffer.pos != 0
          buffer.to_s(output_io)
          buffer.clear
        end

        if missing_columns.size == 0 && extra_columns.size == 0
          # all columns are accounted for
          buffer.puts("\n# All columns in the config for #{table_name.upcase} are present and accounted for.")
        else
          # there are columns missing (or perhaps the whole table is missing); show a scaffold
          emit_scaffold(table_name, table_config.as(ConfigTableHash?), extra_columns, missing_columns, buffer)
        end

        # Now that this table_name has been processed, remember it so we don't scaffold it again
        obfuscator.scaffolded_tables[table_name] = 1
      end

      buffer.seek(-1, IO::Seek::Current)
      buffer.puts("\0")
      buffer.to_s(output_io)
    end

    def config_table_open(table_name)
      %(\n  "#{table_name}" => {)
    end

    def config_table_close(table_name)
      "  },"
    end

    def emit_scaffold(table_name, existing_config, extra_columns, columns_to_scaffold, output_io)
      # header block: contains table name and any existing config
      if existing_config
        output_io.puts(config_table_open(table_name))
        existing_config.each do |column, definition|
          unless extra_columns.includes?(column)
            output_io.puts formatted_line(column, definition)
          end
        end

        extra_columns.each do |column|
          output_string = formatted_line(column, existing_config[column], "# unreferenced config")
          output_io.puts "#  #{output_string}"
        end
      end

      # scaffold block: contains any config that's not already present
      output_io.puts config_table_open(table_name) unless existing_config

      scaffold = columns_to_scaffold.map do |column|
        formatted_line(column, "keep", "# scaffold")
      end.join("\n").chomp(',')
      output_io.puts scaffold
      output_io.print config_table_close(table_name)
    end

    def formatted_line(column, definition, comment = nil)
      colon_string = if definition.to_s[0] == '{' || definition.to_s[0] == ':'
                       definition.to_s
                     else
                       ":#{definition}"
                     end

      column_name = %{"#{column}"}

      if column.size < 40
        %{    #{column_name.ljust(40)}  => #{colon_string},   #{comment}}
      else
        %{    #{column_name} => #{definition},  #{comment}}
      end
    end
  end
end
