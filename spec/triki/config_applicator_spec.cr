require "../spec_helper"
require "spectator"
require "log/spec"

RowAsHash = Triki::ConfigApplicator::RowAsHash

Spectator.describe Triki::ConfigApplicator do
  describe ".apply_table_config" do
    it "should work on email addresses" do
      100.times do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :email}}, ["a", "b"])
        expect(new_row.size).to eq(2)
        expect(new_row.first).to match(/^[\w\.]+\@(\w+\.){2,3}[a-f0-9]{5}\.example\.com$/)
      end
    end

    it "should work on strings" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "something crazy"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :string, :length => 7}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[1].as(String).size).to eq(7)
      expect(new_row[1]).not_to eq("something_else")
    end

    describe "conditional directives" do
      it "should honor :unless conditionals" do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :unless => ->(row : RowAsHash) { row["a"] == "blah" }}}, ["a", "b", "c"])
        expect(new_row[0]).not_to eq("123")
        expect(new_row[0]).to eq("blah")

        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :unless => ->(row : RowAsHash) { row["a"] == "not blah" }}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("123")

        new_row = Triki::ConfigApplicator.apply_table_config([nil, "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :unless => :nil}, "b" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :unless => :nil}}, ["a", "b", "c"])
        expect(new_row[0]).to eq(nil)
        expect(new_row[1]).to eq("123")

        new_row = Triki::ConfigApplicator.apply_table_config(["", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :unless => :blank}, "b" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :unless => :blank}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("")
        expect(new_row[1]).to eq("123")
      end

      it "should honor :if conditionals" do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "blah" }}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("123")

        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "not blah" }}}, ["a", "b", "c"])
        expect(new_row[0]).not_to eq("123")
        expect(new_row[0]).to eq("blah")

        new_row = Triki::ConfigApplicator.apply_table_config([nil, "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => :nil}, "b" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => :nil}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("123")
        expect(new_row[1]).to eq("something_else")

        new_row = Triki::ConfigApplicator.apply_table_config(["", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => :blank}, "b" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => :blank}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("123")
        expect(new_row[1]).to eq("something_else")
      end

      it "should supply the original row values to the conditional" do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123"}, "b" => Triki::ConfigColumnHash{:type => :fixed, :string => "yup", :if => ->(row : RowAsHash) { row["a"] == "blah" }}}, ["a", "b"])
        expect(new_row[0]).to eq("123")
        expect(new_row[1]).to eq("yup")
      end

      it "should honor combined :unless and :if conditionals" do
        # both true
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "blah" }, :unless => ->(row : RowAsHash) { row["b"] == "something_else" }}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("blah")

        # both false
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "not blah" }, :unless => ->(row : RowAsHash) { row["b"] == "not something_else" }}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("blah")

        # if true, #unless false
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "blah" }, :unless => ->(row : RowAsHash) { row["b"] == "not something_else" }}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("123")

        # if false, #unless true
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :string => "123", :if => ->(row : RowAsHash) { row["a"] == "not blah" }, :unless => ->(row : RowAsHash) { row["b"] == "something_else" }}}, ["a", "b", "c"])
        expect(new_row[0]).to eq("blah")
      end
    end

    it "should be able to generate random integers in ranges" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"c" => Triki::ConfigColumnHash{:type => :integer, :between => 10..100}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[2].as(String).to_i.to_s).to eq(new_row[2]) # It should be an integer.
      expect(new_row[2]).not_to eq("5")
    end

    it "should be able to substitute fixed strings" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :fixed, :string => "hello"}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[1]).to eq("hello")
    end

    it "should be able to substitute a proc that returns a string" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :fixed, :string => ->{ "Hello World" }}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[1]).to eq("Hello World")
    end

    it "should provide the row to the proc" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :fixed, :string => ->(row : RowAsHash) { row["b"] }}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[1]).to eq("something_else")
    end

    it "should be able to substitute fixed strings from a random set" do
      looking_for = ["hello", "world"]
      original_looking_for = looking_for.dup
      guard = 0
      while !looking_for.empty? && guard < 1000
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => Triki::ConfigColumnHash{:type => :fixed, :one_of => ["hello", "world"]}}, ["a", "b", "c"])
        expect(new_row.size).to eq(3)
        expect(original_looking_for).to contain(new_row[0])
        looking_for.delete new_row[0]
        guard += 1
      end
      expect(looking_for.size).to eq(0)
    end

    it "should treat a symbol in the column definition as an implicit { :type => symbol }" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => :null, "a" => :keep}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).to eq("blah")
      expect(new_row[1]).to eq(nil)
    end

    it "should be able to set things NULL" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :null}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[1]).to eq(nil)
    end

    it "should be able to :keep the value the same" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :keep}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[1]).to eq("something_else")
    end

    it "should keep the value when given an unknown type, but should display a warning" do
      error_output = Log.capture("triki") do
        new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"b" => Triki::ConfigColumnHash{:type => :unknown_type}}, ["a", "b", "c"])
        expect(new_row.size).to eq(3)
        expect(new_row[1]).to eq("something_else")
      end
      error_output.check(:warn, /Keeping a column value by.*?unknown_type/)
    end

    it "should be able to substitute lorem ipsum text" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :lorem, "b" => Triki::ConfigColumnHash{:type => :lorem, :number => 2}}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
      expect(new_row[0]).not_to match(/\w\.(?!\Z)/)
      expect(new_row[1]).not_to eq("something_else")
      expect(new_row[1]).to match(/\w\.(?!\Z)/)
    end

    it "should be able to generate an :company" do
      new_row = Triki::ConfigApplicator.apply_table_config(["Smith and Sons", "something_else", "5"], Triki::ConfigTableHash{"a" => :company}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("Smith and Sons")
      expect(new_row[0]).to match(/\w+/)
    end

    it "should be able to generate an :url" do
      new_row = Triki::ConfigApplicator.apply_table_config(["http://mystuff.blogger.com", "something_else", "5"], Triki::ConfigTableHash{"a" => :url}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("http://mystuff.blogger.com")
      expect(new_row[0]).to match(/http:\/\/\w+/)
    end

    it "should be able to generate an :ipv4" do
      new_row = Triki::ConfigApplicator.apply_table_config(["1.2.3.4", "something_else", "5"], Triki::ConfigTableHash{"a" => :ipv4}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("1.2.3.4")
      expect(new_row[0]).to match(/\d+\.\d+\.\d+\.\d+/)
    end

    it "should be able to generate an :ipv6" do
      new_row = Triki::ConfigApplicator.apply_table_config(["fe80:0000:0000:0000:0202:b3ff:fe1e:8329", "something_else", "5"], Triki::ConfigTableHash{"a" => :ipv6}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("fe80:0000:0000:0000:0202:b3ff:fe1e:8329")
      expect(new_row[0]).to match(/[0-9a-f:]+/)
    end

    it "should be able to generate an :address" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :address}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
      expect(new_row[0]).to match(/\d+ \w/)
    end

    it "should be able to generate a :name" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :name}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
      expect(new_row[0]).to match(/ /)
    end

    it "should be able to generate just a street address" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :street_address}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
      expect(new_row[0]).to match(/\d+ \w/)
    end

    it "should be able to generate a city" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :city}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
    end

    it "should be able to generate a state" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :state}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
    end

    it "should be able to generate a zip code" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :zip_code}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
      expect(new_row[0]).to match(/\d+/)
    end

    it "should be able to generate a phone number" do
      new_row = Triki::ConfigApplicator.apply_table_config(["blah", "something_else", "5"], Triki::ConfigTableHash{"a" => :phone}, ["a", "b", "c"])
      expect(new_row.size).to eq(3)
      expect(new_row[0]).not_to eq("blah")
      expect(new_row[0]).to match(/\d+/)
    end

    describe "when faker generates values with quotes in them" do
      mock Faker::Address do
        stub city { "O'ReillyTown" }
      end

      mock Faker::Name do
        stub name { "Foo O'Reilly" }
        stub first_name { "O'Foo" }
        stub last_name { "O'Reilly" }
      end

      mock Faker::Lorem do
        stub sentences { %w[Foo bar O'Thingy] }
      end

      it "should remove single quotes from the value" do
        new_row = Triki::ConfigApplicator.apply_table_config(["address", "city", "first", "last", "fullname", "some text"],
          Triki::ConfigTableHash{"a" => :address, "b" => :city, "c" => :first_name, "d" => :last_name, "e" => :name, "f" => :lorem},
          ["a", "b", "c", "d", "e", "f"])
        new_row.each { |value| expect(value).not_to contain("'") }
      end
    end
  end

  describe ".row_as_hash" do
    it "will map row values into a hash with column names as keys" do
      expect(Triki::ConfigApplicator.row_as_hash([1, 2, 3, 4], ["a", "b", "c", "d"])).to eq({"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    end
  end

  describe ".random_english_sentences" do
    mock File do
      stub read { "hello 2" }
    end

    it "should only load file data once" do
      Triki::ConfigApplicator.random_english_sentences(1)
      Triki::ConfigApplicator.random_english_sentences(1)
    end

    it "should make random sentences" do
      sentences = Triki::ConfigApplicator.random_english_sentences(2)

      expect(sentences).to match(/^([\w|']{1,}( [\w|']{1,})+\.\s*){2}$/)

      regex_match = sentences.match(/^([\w|']{1,}( [\w|']{1,})+\.\s*){2}$/)

      expect(regex_match).to_not be_nil

      expect(regex_match.as(Regex::MatchData)[1]).to eq(regex_match.as(Regex::MatchData)[1].capitalize)
      expect(regex_match.as(Regex::MatchData)[2]).to eq(regex_match.as(Regex::MatchData)[2].capitalize)
    end
  end
end
