class Triki
  class ConfigParser
    def self.cast_bindings(bindings) : ConfigHash
      type_hash = ConfigHash.new
      bindings.each do |k, v|
        type_hash[k] = cast_table(v)
      end
      type_hash
    end

    def self.cast_table(table)
      type_table = ConfigTableHash.new
      if table.is_a?(Hash)
        table.each do |k, v|
          type_table[k] = cast_column(v)
        end
        type_table
      else
        table
      end
    end

    def self.cast_column(column)
      if column.is_a?(Hash)
        type_column = ConfigColumnHash.new
        column.each do |k, v|
          type_column[k] = v
        end
        type_column
      else
        column
      end
    end
  end
end
