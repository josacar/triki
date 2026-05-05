require "walker_method"

class Triki
  # Abstract interface for text generators used by the `:like_english` type.
  abstract class DictionaryInterface
    module ClassMethods
      abstract def random_sentences(num : Int32)
    end

    macro inherited
      extend ClassMethods
    end
  end

  # Generates random English-like sentences using a word-frequency list.
  class EnglishDictionary < DictionaryInterface
    def self.random_sentences(num : Int32)
      sentences = Array(String).new
      num.times do
        words = Array(String).new
        rand(3..7).times { words << walker_method.random }
        sentence = words.join(" ") + "."
        sentences << sentence.capitalize
      end
      sentences.join(" ")
    end

    private def self.walker_method
      @@walker_method ||= begin
        words = Array(String).new
        counts = Array(Int32).new
        File.read(File.expand_path(File.join(__DIR__, "data", "en_50K.txt"))).each_line do |line|
          word, count = line.split(/\s+/)
          words << word
          counts << count.to_i
        end
        WalkerMethod.new(words, counts)
      end
    end
  end
end
