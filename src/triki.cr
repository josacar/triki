require "digest/md5"
require "faker"
require "walker_method"
require "log"

# Class for obfuscating MySQL dumps. This can parse mysqldump outputs when using the -c option, which includes
# column names in the insert statements.
class Triki
  property config, globally_kept_columns = Array(String).new, fail_on_unspecified_columns = false, database_type = :mysql, scaffolded_tables

  NUMBER_CHARS = "1234567890"
  USERNAME_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" + NUMBER_CHARS
  SENSIBLE_CHARS = USERNAME_CHARS + "+-=[{]}/?|!@#$%^&*()`~"

  Log = begin
          backend = ::Log::IOBackend.new(STDERR)
          ::Log.builder.bind("*", :warning, backend)
          ::Log.for(self)
        end

  # Make a new Triki object.  Pass in a configuration structure to define how the obfuscation should be
  # performed.  See the README.rdoc file for more information.
  alias TableName = String
  alias ColumnName = String
  alias TruncateOrKeepTable = Symbol
  alias ColumnAction = Symbol
  alias Between = Range(Int32,Int32)
  alias ConfigColumnHash = Hash(Symbol,
                                Array(Regex) |
                                Array(String) |
                                Int32 |
                                Symbol |
                                Proc(Hash(ColumnName, String | Int32 | Nil), Bool) |
                                Proc(Hash(ColumnName, String | Int32 | Nil), String | Int32 | Nil) |
                                Proc(String) |
                                String |
                                Between |
                                Bool
                               )
  alias ConfigColumn = ConfigColumnHash | ColumnAction
  alias ConfigTableHash = Hash(ColumnName, ConfigColumn)
  alias ConfigTable = ConfigTableHash | TruncateOrKeepTable
  alias ConfigHash = Hash(TableName, ConfigTable)
  alias ColumnList = Array(String)

  def initialize(configuration = ConfigHash.new)
    @config = ConfigParser.cast_bindings(configuration)
    @scaffolded_tables = {} of String => Int32
  end

  def fail_on_unspecified_columns?
    @fail_on_unspecified_columns
  end

  def database_helper
    @database_helper ||= case @database_type
                         when :sql_server
                           SqlServer.new
                         when :postgres
                           Postgres.new
                         else
                           Mysql.new
                         end
  end

  # Read an input stream and dump out an obfuscated output stream.  These streams could be any class implementing IO abstract class.
  # or STDIN and STDOUT.
  def obfuscate(input_io, output_io)
    database_helper.parse(self, config, input_io, output_io)
  end

  # Read an input stream and dump out a config file scaffold.  These streams could be any class implementing IO abstract class.
  # or STDIN and STDOUT.
  def scaffold(input_io, output_io)
    database_helper.generate_config(self, config, input_io, output_io)
  end

  def reassembling_each_insert(line : String, table_name : String, columns, ignore = false)
    output = database_helper.rows_to_be_inserted(line).map do |sub_insert|
      result = yield(sub_insert)
      result = result.map do |i|
        database_helper.make_valid_value_string(i)
      end
    end
    database_helper.make_insert_statement(table_name, columns, output, ignore)
  end

  def extra_column_list(table_name : String, columns : Array(String))
    config_table = (config[table_name]? || ConfigTableHash.new).as(ConfigTableHash)
    config_columns = config_table.keys
    config_columns ||= [] of String
    config_columns - columns
  end

  def check_for_defined_columns_not_in_table(table_name, columns)
    missing_columns = extra_column_list(table_name, columns)
    unless missing_columns.size == 0
      error_message = missing_columns.map do |missing_column|
        "Column '#{missing_column}' could not be found in table '#{table_name}', please fix your obfuscator config."
      end.join("\n")
      raise RuntimeError.new(error_message)
    end
  end

  def missing_column_list(table_name : String, columns : Array(String)) : Array
    config_table = (config[table_name]? || ConfigTableHash.new).as(ConfigTableHash)
    config_columns = config_table.keys
    columns - (config_columns + globally_kept_columns).uniq
  end

  def check_for_table_columns_not_in_definition(table_name, columns)
    missing_columns = missing_column_list(table_name, columns)
    unless missing_columns.size == 0
      error_message = missing_columns.map do |missing_column|
        "Column '#{missing_column}' defined in table '#{table_name}', but not found in table definition, please fix your obfuscator config."
      end.join("\n")
      raise RuntimeError.new(error_message)
    end
  end

  def obfuscate_bulk_insert_line(line, table_name : String, columns : ColumnList, ignore = false)
    table_config = config[table_name]

    case table_config
    when :truncate
      ""
    when :keep
      line
    else
      raise RuntimeError.new("table_config is not a hash") unless table_config.is_a?(ConfigTableHash)

      check_for_defined_columns_not_in_table(table_name, columns)
      check_for_table_columns_not_in_definition(table_name, columns) if fail_on_unspecified_columns?
      # Note: Remember to SQL escape strings in what you pass back.
      reassembling_each_insert(line, table_name, columns, ignore) do |row|
        ConfigApplicator.apply_table_config(row, table_config, columns)
      end
    end
  end
end

require "./triki/*"
