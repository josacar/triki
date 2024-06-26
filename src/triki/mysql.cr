# encoding: UTF-8
require "string_scanner"

class Triki
  struct Mysql < Base
    alias Field = String?
    alias Fields = Array(Field)
    alias Rows = Array(Fields)
    alias Table = NamedTuple(ignore: Bool, table_name: String, column_names: ColumnList)

    include Triki::InsertStatementParser
    include Triki::ConfigScaffoldGenerator

    def parse_insert_statement(line)
      return unless regex_match = insert_regex.match(line)

      Table.new(
        ignore: !regex_match[1]?.nil?,
        table_name: regex_match[2],
        column_names: regex_match[3].split(/`\s*,\s*`/).map(&.gsub('`', ""))
      )
    end

    def make_insert_statement(table_name, column_names, rows, ignore = nil)
      String.build do |buffer|
        buffer << %{INSERT #{ignore ? "IGNORE " : ""}INTO `#{table_name}` (`#{column_names.join("`, `")}`) VALUES }
        write_rows(buffer, rows)
        buffer << ";"
      end
    end

    def write_rows(buffer, rows)
      rows.each_with_index do |row_values, i|
        buffer << "("
        write_row_values(buffer, row_values)
        buffer << ")"
        buffer << "," if i < rows.size - 1
      end
    end

    def write_row_values(buffer, row_values)
      row_values.each_with_index do |value, j|
        buffer << value
        buffer << "," if j < row_values.size - 1
      end
    end

    def insert_regex
      /^\s*INSERT\s*(IGNORE )?\s*INTO `(.*?)` \((.*?)\) VALUES\s*/i
    end

    def rows_to_be_inserted(line) : Rows
      scanner = StringScanner.new(line)
      scanner.scan(insert_regex)

      rows = Rows.new
      row_values = Fields.new

      until scanner.eos?
        if scanner.scan(/\(/)
          # Left paren indicates the start of a row of (val1, val2, ..., valn)
          row_values = Fields.new
        elsif scanner.scan(/\)/)
          # Right paren indicates the end of a row of (val1, val2, ..., valn)
          rows.push(row_values)
        elsif scanner.scan(/NULL/)
          row_values << nil
        elsif match = scanner.scan(/'(\\\\|\\'|.)*?'/)
          # We drop the leading and trailing quotes to extract the string
          row_values << match[1, match.size - 2]
        elsif match = scanner.scan(/[^,\)]+/)
          # All other literals.  We match these up to the "," separator or ")" closing paren.
          # Hence we rstrip to drop any whitespace between the literal and the "," or ")".
          row_values << match.rstrip
        else
          # This is minimal validation.  We're assuming valid input generated by mysqldump.
          raise "Parse error: unexpected token begginning at #{scanner.peek 80}"
        end
        # Ignore whitespace/separator after any token
        scanner.scan(/[\s,;]+/)
      end

      rows
    end

    def make_valid_value_string(value)
      if value.nil?
        "NULL"
      elsif value =~ /^0x[0-9a-fA-F]+$/
        value
      else
        "'" + value.to_s + "'"
      end
    end
  end
end
