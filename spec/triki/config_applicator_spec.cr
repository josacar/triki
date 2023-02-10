require "../spec_helper"
require "log/spec"

alias RowAsHash = Triki::RowAsHash
alias RowContent = Triki::RowContent
alias ConfigColumnHash = Triki::ConfigColumnHash
alias ConfigTableHash = Triki::ConfigTableHash

class MyFaker < Triki::Faker
  def self.city
    "Foo O'City"
  end

  def self.name
    "Foo O'Reilly"
  end

  def self.first_name
    "O'Foo"
  end

  def self.last_name
    "O'Reilly"
  end

  def self.lorem
    %w[Foo bar O'Thingy]
  end
end

class MyDictionary < Triki::DictionaryInterface
  def self.random_sentences(num : Int32)
    "My first sentence. This is the second."
  end
end

describe Triki::ConfigApplicator do
  describe ".apply_table_config" do
    it "should work on email addresses" do
      100.times do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else"], ConfigTableHash{"a" => ConfigColumnHash{:type => :email}}, ["a", "b"])
        new_row.size.should eq(2)
        new_row.first.should match(/^[\w\.]+\@(\w+\.){2,3}[a-f0-9]{5}\.example\.com$/)
      end
    end

    it "should work on strings" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "something crazy"], ConfigTableHash{"b" => ConfigColumnHash{:type => :string, :length => 7}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[1].as(String).size.should eq(7)
      new_row[1].should_not eq("something_else")
    end

    describe "conditional directives" do
      it "should honor :unless conditionals" do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :unless => ->(row : RowAsHash) { row["a"] == "blah" }}}, ["a", "b", "c"])
        new_row[0].should_not eq("123")
        new_row[0].should eq("blah")

        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :unless => ->(row : RowAsHash) { row["a"] == "not blah" }}}, ["a", "b", "c"])
        new_row[0].should eq("123")

        new_row = Triki::ConfigApplicator.apply_table_config([nil, "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :unless => :nil}, "b" => ConfigColumnHash{:type => :fixed, :string => "123", :unless => :nil}}, ["a", "b", "c"])
        new_row[0].should eq(nil)
        new_row[1].should eq("123")

        new_row = Triki::ConfigApplicator.apply_table_config(["", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :unless => :blank}, "b" => ConfigColumnHash{:type => :fixed, :string => "123", :unless => :blank}}, ["a", "b", "c"])
        new_row[0].should eq("")
        new_row[1].should eq("123")
      end

      it "should honor :if conditionals" do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "blah" }}}, ["a", "b", "c"])
        new_row[0].should eq("123")

        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "not blah" }}}, ["a", "b", "c"])
        new_row[0].should_not eq("123")
        new_row[0].should eq("blah")

        new_row = Triki::ConfigApplicator.apply_table_config([nil, "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => :nil}, "b" => ConfigColumnHash{:type => :fixed, :string => "123", :if => :nil}}, ["a", "b", "c"])
        new_row[0].should eq("123")
        new_row[1].should eq("something_else")

        new_row = Triki::ConfigApplicator.apply_table_config(["", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => :blank}, "b" => ConfigColumnHash{:type => :fixed, :string => "123", :if => :blank}}, ["a", "b", "c"])
        new_row[0].should eq("123")
        new_row[1].should eq("something_else")
      end

      it "should supply the original row values to the conditional" do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123"}, "b" => ConfigColumnHash{:type => :fixed, :string => "yup", :if => ->(row : RowAsHash) { row["a"] == "blah" }}}, ["a", "b"])
        new_row[0].should eq("123")
        new_row[1].should eq("yup")
      end

      it "should honor combined :unless and :if conditionals" do
        # both true
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "blah" }, :unless => ->(row : RowAsHash) { row["b"] == "something_else" }}}, ["a", "b", "c"])
        new_row[0].should eq("blah")

        # both false
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "not blah" }, :unless => ->(row : RowAsHash) { row["b"] == "not something_else" }}}, ["a", "b", "c"])
        new_row[0].should eq("blah")

        # if true, #unless false
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "blah" }, :unless => ->(row : RowAsHash) { row["b"] == "not something_else" }}}, ["a", "b", "c"])
        new_row[0].should eq("123")

        # if false, #unless true
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "not blah" }, :unless => ->(row : RowAsHash) { row["b"] == "something_else" }}}, ["a", "b", "c"])
        new_row[0].should eq("blah")
      end
    end

    it "should be able to generate random integers in ranges" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"c" => ConfigColumnHash{:type => :integer, :between => 10..100}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[2].as(String).to_i.to_s.should eq(new_row[2]) # It should be an integer.
      new_row[2].should_not eq("5")
    end

    it "should be able to substitute fixed strings" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => ConfigColumnHash{:type => :fixed, :string => "hello"}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[1].should eq("hello")
    end

    it "should be able to substitute a proc that returns a string" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => ConfigColumnHash{:type => :fixed, :string => ->{ "Hello World" }}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[1].should eq("Hello World")
    end

    it "should provide the row to the proc" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => ConfigColumnHash{:type => :fixed, :string => ->(row : RowAsHash) { row["b"].to_s.as(RowContent) }}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[1].should eq("something_else")
    end

    it "should be able to substitute fixed strings from a random set" do
      looking_for = ["hello", "world"]
      original_looking_for = looking_for.dup
      guard = 0
      while !looking_for.empty? && guard < 1000
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => ConfigColumnHash{:type => :fixed, :one_of => ["hello", "world"]}}, ["a", "b", "c"])
        new_row.size.should eq(3)
        original_looking_for.should contain(new_row[0])
        looking_for.delete new_row[0]
        guard += 1
      end
      looking_for.size.should eq(0)
    end

    it "should treat a symbol in the column definition as an implicit { :type => symbol }" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => :null, "a" => :keep}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should eq("blah")
      new_row[1].should eq(nil)
    end

    it "should be able to set things NULL" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => ConfigColumnHash{:type => :null}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[1].should eq(nil)
    end

    it "should be able to :keep the value the same" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => ConfigColumnHash{:type => :keep}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[1].should eq("something_else")
    end

    it "should keep the value when given an unknown type, but should display a warning" do
      error_output = Log.capture("triki") do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"b" => ConfigColumnHash{:type => :unknown_type}}, ["a", "b", "c"])
        new_row.size.should eq(3)
        new_row[1].should eq("something_else")
      end
      error_output.check(:warn, /Keeping a column value by.*?unknown_type/)
    end

    it "should be able to substitute lorem ipsum text" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :lorem, "b" => ConfigColumnHash{:type => :lorem, :number => 2}}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
      new_row[0].should_not match(/\w\.(?!\Z)/)
      new_row[1].should_not eq("something_else")
      new_row[1].should match(/\w\.(?!\Z)/)
    end

    it "should be able to generate an :company" do
      new_row = Triki::ConfigApplicator.apply_table_config(["Smith and Sons", "something_else", "5"], ConfigTableHash{"a" => :company}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("Smith and Sons")
      new_row[0].should match(/\w+/)
    end

    it "should be able to generate an :url" do
      new_row = Triki::ConfigApplicator.apply_table_config(["http://mystuff.blogger.com", "something_else", "5"], ConfigTableHash{"a" => :url}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("http://mystuff.blogger.com")
      new_row[0].should match(/http:\/\/\w+/)
    end

    it "should be able to generate an :ipv4" do
      new_row = Triki::ConfigApplicator.apply_table_config(["1.2.3.4", "something_else", "5"], ConfigTableHash{"a" => :ipv4}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("1.2.3.4")
      new_row[0].should match(/\d+\.\d+\.\d+\.\d+/)
    end

    it "should be able to generate an :ipv6" do
      new_row = Triki::ConfigApplicator.apply_table_config(["fe80:0000:0000:0000:0202:b3ff:fe1e:8329", "something_else", "5"], ConfigTableHash{"a" => :ipv6}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("fe80:0000:0000:0000:0202:b3ff:fe1e:8329")
      new_row[0].should match(/[0-9a-f:]+/)
    end

    it "should be able to generate an :address" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :address}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
      new_row[0].should match(/\d+ \w/)
    end

    it "should be able to generate a :name" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :name}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
      new_row[0].should match(/ /)
    end

    it "should be able to generate just a street address" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :street_address}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
      new_row[0].should match(/\d+ \w/)
    end

    it "should be able to generate a city" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :city}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
    end

    it "should be able to generate a state" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :state}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
    end

    it "should be able to generate a zip code" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :zip_code}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
      new_row[0].should match(/\d+/)
    end

    it "should be able to generate a phone number" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], ConfigTableHash{"a" => :phone}, ["a", "b", "c"])
      new_row.size.should eq(3)
      new_row[0].should_not eq("blah")
      new_row[0].should match(/\d+/)
    end

    describe "when faker generates values with quotes in them" do
      it "should remove single quotes from the value" do
        new_row = Triki::ConfigApplicator.apply_table_config(
          row: ["address", "city", "first", "last", "fullname", "some text"],
          table_config: ConfigTableHash{"a" => :address, "b" => :city, "c" => :first_name, "d" => :last_name, "e" => :name, "f" => :lorem},
          columns:["a", "b", "c", "d", "e", "f"],
          faker: MyFaker
        )
        new_row.each { |value| value.as(String).should_not contain("'") }
      end
    end
  end

  describe ".row_as_hash" do
    it "will map row values into a hash with column names as keys" do
      Triki::ConfigApplicator.row_as_hash([1, 2, 3, 4], ["a", "b", "c", "d"]).should eq({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    end
  end

  describe ".random_english_sentences" do
    it "should only load file data once" do
      Triki::EnglishDictionary.random_sentences(1)
      Triki::EnglishDictionary.random_sentences(1)
    end

    it "should make random sentences" do
      text = Triki::EnglishDictionary.random_sentences(2)

      word = /(?:[\w|']{1,})+/
      sentence = /(?:#{word}\s)+#{word}\./
      two_sentences = /^(?:#{sentence}\s*){2}$/

      text.should match(two_sentences)

      sentences = text.scan(sentence).map(&.[0])

      sentences[0].should_not eq(sentences[1])
    end
  end
end
