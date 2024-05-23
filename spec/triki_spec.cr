require "./spec_helper"
require "log/spec"

describe Triki do
  describe "Triki.reassembling_each_insert" do
    it "should yield each subinsert and reassemble the result" do
      column_names = ["a", "b", "c", "d"]
      test_insert = "INSERT INTO `some_table` (`a`, `b`, `c`, `d`) VALUES ('(\\'bob@bob.com','b()ob','some(thingelse1','25)('),('joe@joe.com','joe','somethingelse2','54');"
      test_insert_passes = [
        ["(\\'bob@bob.com", "b()ob", "some(thingelse1", "25)("],
        ["joe@joe.com", "joe", "somethingelse2", "54"],
      ]

      count = 0
      reassembled = Triki.new.reassembling_each_insert(test_insert, "some_table", column_names) do |sub_insert|
        sub_insert.should eq(test_insert_passes.shift)
        count += 1
        sub_insert
      end
      count.should eq(2)
      reassembled.should eq(test_insert)
    end
  end

  describe "#obfuscate" do
    describe "when using Postgres" do
      dump = IO::Memory.new(<<-'SQL')
        COPY some_table (id, email, name, something, age) FROM stdin;
        1	hello	monkey	moose	14
        \.

        COPY single_column_table (id) FROM stdin;
        1
        2
        \N
        \.

        COPY another_table (a, b, c, d) FROM stdin;
        1	2	3	4
        1	2	3	4
        \.

        COPY some_table_to_keep (a, b) FROM stdin;
        5	6
        \.
        SQL

      obfuscator = Triki.new({
        "some_table" => {
          "email" => {
            :type         => :email,
            :skip_regexes => [
              /^[\w\.\_]+@honk\.com$/i,
              /^dontmurderme@direwolf.com$/,
            ],
          },
          "name" => {
            :type   => :string,
            :length => 8,
            :chars  => Triki::USERNAME_CHARS,
          },
          "age" => {
            :type    => :integer,
            :between => 10...80,
            :unless  => :nil,
          },
        },
        "single_column_table" => {
          "id" => {
            :type    => :integer,
            :between => 2..9,
            :unless  => :nil,
          },
        },
        "another_table"      => :truncate,
        "some_table_to_keep" => :keep,
      }).tap do |my_obfuscator|
        my_obfuscator.database_type = :postgres
      end

      output = IO::Memory.new
      dump.rewind
      obfuscator.obfuscate(dump, output)
      output.rewind
      output_string = output.gets_to_end

      scaffolder = Triki.new({
        "some_other_table" => {
          "email" => {
            :type         => :email,
            :skip_regexes => [/^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/],
          },
          "name" => {
            :type   => :string,
            :length => 8,
            :chars  => Triki::USERNAME_CHARS,
          },
          "age" => {
            :type    => :integer,
            :between => 10...80,
            :unless  => :nil,
          },
        },
        "single_column_table" => {
          "id" => {
            :type    => :integer,
            :between => 2..9,
            :unless  => :nil,
          },
        },
        "another_table"      => :truncate,
        "some_table_to_keep" => :keep,
      }).tap do |my_scaffolder|
        my_scaffolder.database_type = :postgres
        my_scaffolder.globally_kept_columns = %w[age]
      end

      output = IO::Memory.new
      dump.rewind
      scaffolder.scaffold(dump, output)
      output.rewind
      scaffold_output_string = output.gets_to_end

      it "is able to obfuscate single column tables" do
        output_string.should_not contain("1\n2\n")
        output_string.should match(/\d\n\d\n/)
      end

      it "is able to truncate tables" do
        output_string.should_not contain("1\t2\t3\t4")
      end

      it "can obfuscate the tables" do
        output_string.should contain("COPY some_table (id, email, name, something, age) FROM stdin;\n")
        output_string.should match(/1\t.*\t\S{8}\tmoose\t\d{2}\n/)
      end

      it "can skip nils" do
        output_string.should match(/\d\n\d\n\\N/)
      end

      it "is able to keep tables" do
        output_string.should contain("5\t6")
      end

      context "when dump contains INSERT statement" do
        error_dump = IO::Memory.new(<<-SQL)
          INSERT INTO some_table (email, name, something, age) VALUES ('','', '', 25);
          SQL

        it "raises an error if using postgres with insert statements" do
          expect_raises(RuntimeError) do
            obfuscator = Triki.new({
              "some_table" => {
                "email" => {
                  :type         => :email,
                  :skip_regexes => [
                    /^[\w\.\_]+@honk\.com$/i,
                    /^dontmurderme@direwolf.com$/,
                  ],
                },
                "name" => {
                  :type   => :string,
                  :length => 8,
                  :chars  => Triki::USERNAME_CHARS,
                },
                "age" => {
                  :type    => :integer,
                  :between => 10...80,
                  :unless  => :nil,
                },
              },
              "single_column_table" => {
                "id" => {
                  :type    => :integer,
                  :between => 2..9,
                  :unless  => :nil,
                },
              },
              "another_table"      => :truncate,
              "some_table_to_keep" => :keep,
            }).tap do |my_obfuscator|
              my_obfuscator.database_type = :postgres
            end

            output = IO::Memory.new
            obfuscator.obfuscate(error_dump, output)
            output.rewind
            output.gets_to_end
          end
        end
      end

      it "when there is no existing config, should scaffold all the columns that are not globally kept" do
        scaffold_output_string.should match(/"email"\s+=>\s+:keep.+scaffold/)
        scaffold_output_string.should match(/"name"\s+=>\s+:keep.+scaffold/)
      end

      it "should not scaffold a columns that is globally kept" do
        scaffold_output_string.should_not match(/"age"\s+=>\s+:keep.+scaffold/)
      end

      context "when dump contains a '.' at the end of the line" do
        dump = IO::Memory.new(<<-'SQL')
            COPY another_table (a, b, c, d) FROM stdin;
            1    2       3       4
            1    2       3       .
            \.
            SQL

        it "should not fail if a insert statement ends in a '.''" do
          output_string.should_not match(/1\t2\t3\t\./)
        end
      end
    end

    describe "when using MySQL" do
      context "when there is nothing to obfuscate" do
        it "should accept an IO object for input and output, and copy the input to the output" do
          ddo = Triki.new
          string = "hello, world\nsup?"
          input = IO::Memory.new(string)
          output = IO::Memory.new
          ddo.obfuscate(input, output)
          input.rewind
          output.rewind
          output.gets_to_end.should eq(string)
        end
      end

      context "when the dump to obfuscate is missing columns" do
        it "should raise an error if a column name can't be found" do
          string = <<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new({
            "some_table" => {
              "email" => {
                :type            => :email,
                :honk_email_skip => true,
              },
              "name" => {
                :type   => :string,
                :length => 8,
                :chars  => Triki::USERNAME_CHARS,
              },
              "gender" => {
                :type   => :fixed,
                :string => "m",
              },
            },
          })
          output = IO::Memory.new

          expect_raises(RuntimeError) do
            ddo.obfuscate(database_dump, output)
          end
        end
      end

      context "when there is something to obfuscate" do
        string = <<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin;ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54),('dontmurderme@direwolf.com','direwolf', 'somethingelse3', 44);
          INSERT INTO `another_table` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4), (5,6,7,8);
          INSERT INTO `some_table_to_keep` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4), (5,6,7,8);
          INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh', 'aawefjkafe', 'wadus'), ('hello1','kjhj!', 892938, 'tradus'), ('hello2','moose!!', NULL, NULL);
          INSERT INTO `an_ignored_table` (`col`, `col2`) VALUES ('hello','kjhjd^&dkjh'), ('hello1','kjhj!'), ('hello2','moose!!');
          SQL
        database_dump = IO::Memory.new(string)

        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type         => :email,
              :skip_regexes => [
                /^[\w\.\_]+@honk\.com$/i,
                /^dontmurderme@direwolf.com$/,
              ],
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
            "age" => {
              :type    => :integer,
              :between => 10...80,
            },
          },
          "another_table"      => :truncate,
          "some_table_to_keep" => :keep,
          "one_more_table"     => {
            # Note: fixed strings must be pre-SQL escaped!
            "password" => {
              :type   => :fixed,
              :string => "monkey",
            },
            "c" => {
              :type => :null,
            },
          },
        })
        output = IO::Memory.new
        ddo.obfuscate(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should be able to truncate tables" do
          output_string.should_not contain("INSERT INTO `another_table`")
          output_string.should contain("INSERT INTO `one_more_table`")
        end

        it "should be able to declare tables to keep" do
          output_string.should contain("INSERT INTO `some_table_to_keep` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4), (5,6,7,8);")
        end

        it "should ignore tables that it doesn't know about, but should warn" do
          error_output_log = Log.capture("triki") do
            ddo = Triki.new({
              "some_table" => {
                "email" => {
                  :type         => :email,
                  :skip_regexes => [
                    /^[\w\.\_]+@honk\.com$/i,
                    /^dontmurderme@direwolf.com$/,
                  ],
                },
                "name" => {
                  :type   => :string,
                  :length => 8,
                  :chars  => Triki::USERNAME_CHARS,
                },
                "age" => {
                  :type    => :integer,
                  :between => 10...80,
                },
              },
              "another_table"      => :truncate,
              "some_table_to_keep" => :keep,
              "one_more_table"     => {
                # Note: fixed strings must be pre-SQL escaped!
                "password" => {
                  :type   => :fixed,
                  :string => "monkey",
                },
                "c" => {
                  :type => :null,
                },
              },
            })
            output = IO::Memory.new
            database_dump.rewind
            ddo.obfuscate(database_dump, output)
            output.rewind
            output_string = output.gets_to_end

            output_string.should contain("INSERT INTO `an_ignored_table` (`col`, `col2`) VALUES ('hello','kjhjd^&dkjh'), ('hello1','kjhj!'), ('hello2','moose!!');")
          end

          error_output_log.check(:warn, /an_ignored_table was not specified in the config/)
        end

        it "should obfuscate the tables" do
          output_string.should contain("INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES (")
          output_string.should contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES (")
          output_string.should contain("'some\\'thin;ge())lse1'")
          output_string.should contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','monkey',NULL,'wadus'),('hello1','monkey',NULL,'tradus'),('hello2','monkey',NULL,NULL);")
          output_string.should_not contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh',NULL, 'wadus'),('hello1','kjhj!',NULL, 'tradus'),('hello2','moose!!',NULL, NULL);")
          output_string.should_not contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh',NULL,'wadus'),('hello1','kjhj!',NULL,'tradus'),('hello2','moose!!',NULL,NULL);")
          output_string.should_not contain("INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin;ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);")
        end

        context "with MariaDB >= 10.7.1 dump" do
          it "should obfuscate the tables and remove newlines" do
            string = <<-SQL
              INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),
              ('joe@joe.com','joe', 'somethingelse2', 54),
              ('dontmurderme@direwolf.com','direwolf', 'somethingelse3', 44);
              INSERT INTO `another_table` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4),
              (5,6,7,8);
              INSERT INTO `some_table_to_keep` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4),
              (5,6,7,8);
              INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh', 'aawefjkafe', 'wadus'),
              ('hello1','kjhj!', 892938, 'tradus'),
              ('hello2','moose!!', NULL, NULL);
              INSERT INTO `an_ignored_table` (`col`, `col2`) VALUES ('hello','kjhjd^&dkjh'),
              ('hello1','kjhj!'),
              ('hello2','moose!!');
            SQL

            output_string.should contain("INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES (")
            output_string.should contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES (")
            output_string.should contain("'some\\'thin;ge())lse1'")
            output_string.should contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','monkey',NULL,'wadus'),('hello1','monkey',NULL,'tradus'),('hello2','monkey',NULL,NULL);")
            output_string.should_not contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh',NULL, 'wadus'),('hello1','kjhj!',NULL, 'tradus'),('hello2','moose!!',NULL, NULL);")
            output_string.should_not contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh',NULL,'wadus'),('hello1','kjhj!',NULL,'tradus'),('hello2','moose!!',NULL,NULL);")
            output_string.should_not contain("INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin;ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);")
          end
        end

        it "honors a special case: on the people table, rows with skip_regexes that match are skipped" do
          output_string.should contain("('bob@honk.com',")
          output_string.should contain("('dontmurderme@direwolf.com',")
          output_string.should_not contain("joe@joe.com")
          output_string.should contain("example.com")
        end
      end

      context "when fail_on_unspecified_columns is set to true" do
        string = <<-SQL
              INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54),('dontmurderme@direwolf.com','direwolf', 'somethingelse3', 44);
          SQL
        database_dump = IO::Memory.new(string)

        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type         => :email,
              :skip_regexes => [
                /^[\w\.\_]+@honk\.com$/i,
                /^dontmurderme@direwolf.com$/,
              ],
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
            "age" => {
              :type    => :integer,
              :between => 10...80,
            },
          },
        })
        ddo.fail_on_unspecified_columns = true

        it "should raise an exception when an unspecified column is found" do
          expect_raises(RuntimeError, /column 'something' defined/i) do
            ddo.obfuscate(database_dump, IO::Memory.new)
          end
        end

        it "should accept columns defined in globally_kept_columns" do
          ddo.globally_kept_columns = %w[something]
          ddo.obfuscate(database_dump, IO::Memory.new)
        end
      end

      context "when there is an existing config to scaffold" do
        string = <<-SQL
        INSERT IGNORE INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
        SQL
        database_dump = IO::Memory.new(string)

        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type            => :email,
              :honk_email_skip => true,
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
          },
          "another_table" => :truncate,
        })
        ddo.globally_kept_columns = %w[something]
        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should scaffold missing columns" do
          output_string.should match(/"age"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally_kept_columns" do
          output_string.should_not match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should pass through correct columns" do
          output_string.should_not match(/"email"\s+=>\s+:keep.+scaffold/)
          output_string.should match(/"email"\s+=>/)
          output_string.should_not match(/\#\s*"email"/)
        end
      end

      context "when using :secondary_address" do
        string = <<-SQL
        INSERT INTO `some_table` (`email`, `name`, `something`, `age`, `address1`, `address2`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25, '221B Baker St', 'Suite 100'),('joe@joe.com','joe', 'somethingelse2', 54, '1300 Pennsylvania Ave', '2nd floor');
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type            => :email,
              :honk_email_skip => true,
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
            "something" => :keep,
            "age"       => :keep,
            "address1"  => :street_address,
            "address2"  => :secondary_address,
          },
        })
        output = IO::Memory.new
        ddo.obfuscate(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should obfuscate address1" do
          output_string.should contain("address1")
          output_string.should_not contain("Baker St")
        end

        it "should obfuscate address2" do
          output_string.should contain("address2")
          output_string.should_not contain("Suite 100")
        end
      end

      context "when there is an existing config to scaffold" do
        string = <<-SQL
        INSERT INTO `some_table` (`email`, `name`, `something`, `age`, `address1`, `address2`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25, '221B Baker St', 'Suite 100'),('joe@joe.com','joe', 'somethingelse2', 54, '1300 Pennsylvania Ave', '2nd floor');
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type            => :email,
              :honk_email_skip => true,
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
            "something" => :keep,
            "age"       => :keep,
            "gender"    => {
              :type   => :fixed,
              :string => "m",
            },
            "address1" => :street_address,
            "address2" => :secondary_address,
          },
        })
        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should enumerate extra columns" do
          output_string.should match(/\#\s*"gender"\s+=>\s+\{:type\s*=>\s*:fixed,\s*:string.*#\s*unreferenced/)
        end

        it "should pass through existing columns" do
          output_string.should match(/"age"\s+=>\s+:keep\s*,/)
          output_string.should match(/"address2"\s+=>\s*:secondary_address/)
        end
      end

      context "when there is an existing config to scaffold with both missing and extra columns" do
        string = <<-SQL
        INSERT IGNORE INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email"  => {:type => :email, :honk_email_skip => true},
            "name"   => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "gender" => {:type => :fixed, :string => "m"},
          },
        })
        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should scaffold missing columns" do
          output_string.should match(/"age"\s+=>\s+:keep.+scaffold/)
          output_string.should match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should enumerate extra columns" do
          output_string.should match(/\#\s*"gender"/)
        end
      end

      context "when there is an existing config to scaffold and it is just right" do
        string = <<-SQL
        INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email"     => {:type => :email, :honk_email_skip => true},
            "name"      => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "something" => :keep,
            "age"       => :keep,
          },
        })
        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should say that everything is present and accounted for" do
          output_string.should match(/^\s*\#.*account/)
          output_string.should_not contain("scaffold")
          output_string.should_not contain(%{"some_table"})
        end
      end

      context "when scaffolding a table with no existing config" do
        string = <<-SQL
        INSERT INTO `some_table` (`email`, `name`, `something`, `age_of_the_individual_who_is_specified_by_this_row_of_the_table`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_other_table" => {
            "email"                                                           => {:type => :email, :honk_email_skip => true},
            "name"                                                            => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "something"                                                       => :keep,
            "age_of_the_individual_who_is_specified_by_this_row_of_the_table" => :keep,
          },
        })
        ddo.globally_kept_columns = %w[name]

        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should scaffold all the columns that are not globally kept" do
          output_string.should match(/"email"\s+=>\s+:keep.+scaffold/)
          output_string.should match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally kept columns" do
          output_string.should_not match(/"name"\s+=>\s+:keep.+scaffold/)
        end

        it "should preserve long column names" do
          output_string.should match(/"age_of_the_individual_who_is_specified_by_this_row_of_the_table"/)
        end
      end
    end

    describe "when using MS SQL Server" do
      context "when there is nothing to obfuscate" do
        it "should accept an IO object for input and output, and copy the input to the output" do
          ddo = Triki.new
          ddo.database_type = :sql_server
          string = "hello, world\nsup?"
          input = IO::Memory.new(string)
          output = IO::Memory.new
          ddo.obfuscate(input, output)
          input.rewind
          output.rewind
          output.gets_to_end.should eq(string)
        end
      end

      context "when the dump to obfuscate is missing columns" do
        string = <<-SQL
          INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)

        ddo = Triki.new({
          "some_table" => {
            "email"  => {:type => :email, :honk_email_skip => true},
            "name"   => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "gender" => {:type => :fixed, :string => "m"},
          },
        })
        ddo.database_type = :sql_server
        output = IO::Memory.new

        it "should raise an error if a column name can't be found" do
          expect_raises(RuntimeError) do
            ddo.obfuscate(database_dump, output)
          end
        end
      end

      context "when there is something to obfuscate" do
        string = <<-SQL
        INSERT [dbo].[some_table] ([email], [name], [something], [age], [bday]) VALUES (N'bob@honk.com',N'bob', N'some''thin,ge())lse1', 25, CAST(0x00009E1A00000000 AS DATETIME));
        INSERT [dbo].[some_table] ([email], [name], [something], [age], [bday]) VALUES (N'joe@joe.com',N'joe', N'somethingelse2', 54, CAST(0x00009E1A00000000 AS DATETIME));
        INSERT [dbo].[some_table] ([email], [name], [something], [age], [bday]) VALUES (N'dontmurderme@direwolf.com',N'direwolf', N'somethingelse3', 44, CAST(0x00009E1A00000000 AS DATETIME));
        INSERT [dbo].[another_table] ([a], [b], [c], [d]) VALUES (1,2,3,4);
        INSERT [dbo].[another_table] ([a], [b], [c], [d]) VALUES (5,6,7,8);
        INSERT [dbo].[some_table_to_keep] ([a], [b], [c], [d]) VALUES (1,2,3,4);
        INSERT [dbo].[some_table_to_keep] ([a], [b], [c], [d]) VALUES (5,6,7,8);
        INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello',N'kjhjd^&dkjh', N'aawefjkafe', N'wadus');
        INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello1',N'kjhj!', 892938, N'wadus');
        INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello2',N'moose!!', NULL, N'wadus');
        INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello',N'kjhjd^&dkjh');
        INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello1',N'kjhj!');
        INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello2',N'moose!!');
        SQL
        database_dump = IO::Memory.new(string)

        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type         => :email,
              :skip_regexes => [
                /^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/,
              ],
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
            "age" => {
              :type    => :integer,
              :between => 10...80,
            },
            "bday" => :keep,
          },
          "another_table"      => :truncate,
          "some_table_to_keep" => :keep,
          "one_more_table"     => {
            # Note: fixed strings must be pre-SQL escaped!
            "password" => {
              :type   => :fixed,
              :string => "monkey",
            },
            "c" => {
              :type => :null,
            },
          },
        })
        ddo.database_type = :sql_server

        output = IO::Memory.new
        ddo.obfuscate(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should be able to truncate tables" do
          output_string.should_not contain("INSERT [dbo].[another_table]")
          output_string.should contain("INSERT [dbo].[one_more_table]")
        end

        it "should be able to declare tables to keep" do
          output_string.should contain("INSERT [dbo].[some_table_to_keep] ([a], [b], [c], [d]) VALUES (1,2,3,4);")
          output_string.should contain("INSERT [dbo].[some_table_to_keep] ([a], [b], [c], [d]) VALUES (5,6,7,8);")
        end

        it "should ignore tables that it doesn't know about, but should warn" do
          error_output_log = Log.capture("triki") do
            ddo = Triki.new({
              "some_table" => {
                "email" => {
                  :type         => :email,
                  :skip_regexes => [
                    /^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/,
                  ],
                },
                "name" => {
                  :type   => :string,
                  :length => 8,
                  :chars  => Triki::USERNAME_CHARS,
                },
                "age" => {
                  :type    => :integer,
                  :between => 10...80,
                },
                "bday" => :keep,
              },
              "another_table"      => :truncate,
              "some_table_to_keep" => :keep,
              "one_more_table"     => {
                # Note: fixed strings must be pre-SQL escaped!
                "password" => {
                  :type   => :fixed,
                  :string => "monkey",
                },
                "c" => {
                  :type => :null,
                },
              },
            })
            ddo.database_type = :sql_server

            output = IO::Memory.new
            database_dump.rewind
            ddo.obfuscate(database_dump, output)
            output.rewind
            output_string = output.gets_to_end

            output_string.should contain("INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello',N'kjhjd^&dkjh');")
            output_string.should contain("INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello1',N'kjhj!');")
            output_string.should contain("INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello2',N'moose!!');")
          end

          error_output_log.check(:warn, /an_ignored_table was not specified in the config/)
        end

        it "should obfuscate the tables" do
          output_string.should contain("INSERT [dbo].[some_table] ([email], [name], [something], [age], [bday]) VALUES (")
          output_string.should contain("CAST(0x00009E1A00000000 AS DATETIME)")
          output_string.should contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (")
          output_string.should contain("'some''thin,ge())lse1'")
          output_string.should contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello',N'monkey',NULL,N'wadus');")
          output_string.should contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello1',N'monkey',NULL,N'wadus');")
          output_string.should contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello2',N'monkey',NULL,N'wadus');")
          output_string.should_not contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello',N'kjhjd^&dkjh', N'aawefjkafe');")
          output_string.should_not contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello1',N'kjhj!', 892938);")
          output_string.should_not contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello2',N'moose!!', NULL);")
          output_string.should_not contain("INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES (N'bob@honk.com',N'bob', N'some''thin,ge())lse1', 25, CAST(0x00009E1A00000000 AS DATETIME));")
          output_string.should_not contain("INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES (N'joe@joe.com',N'joe', N'somethingelse2', 54, CAST(0x00009E1A00000000 AS DATETIME));")
        end

        it "honors a special case: on the people table, rows with anything@honk.com in a slot marked with :honk_email_skip do not change this slot" do
          output_string.should contain("(N'bob@honk.com',")
          output_string.should contain("(N'dontmurderme@direwolf.com',")
          output_string.should_not contain("joe@joe.com")
        end
      end

      context "when fail_on_unspecified_columns is set to true" do
        string = <<-SQL
        INSERT INTO [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)

        ddo = Triki.new({
          "some_table" => {
            "email" => {:type => :email, :skip_regexes => [/^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/]},
            "name"  => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "age"   => {:type => :integer, :between => 10...80},
          },
        })
        ddo.database_type = :sql_server
        ddo.fail_on_unspecified_columns = true

        it "should raise an exception when an unspecified column is found" do
          expect_raises(Exception, /column 'something' defined/i) do
            ddo.obfuscate(database_dump, IO::Memory.new)
          end
        end

        it "should accept columns defined in globally_kept_columns" do
          ddo.globally_kept_columns = %w[something]
          ddo.obfuscate(database_dump, IO::Memory.new)
        end
      end

      context "when there is an existing config to scaffold and it is missing columns" do
        string = <<-SQL
        INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email" => {:type => :email, :honk_email_skip => true},
            "name"  => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
          },
        })
        ddo.database_type = :sql_server
        ddo.globally_kept_columns = %w[something]
        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should scaffold columns that can't be found" do
          output_string.should match(/"age"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally_kept_columns" do
          output_string.should_not match(/"something"\s+=>\s+:keep.+scaffold/)
        end
      end

      context "when there is an existing config to scaffold and it has extra columns" do
        string = <<-SQL
        INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email"     => {:type => :email, :honk_email_skip => true},
            "name"      => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "something" => :keep,
            "age"       => :keep,
            "gender"    => {:type => :fixed, :string => "m"},
          },
        })
        ddo.database_type = :sql_server

        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should enumerate extra columns" do
          output_string.should match(/\#\s*"gender"/)
        end
      end

      context "when there is an existing config to scaffold and it has both missing and extra columns" do
        string = <<-SQL
        INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email"  => {:type => :email, :honk_email_skip => true},
            "name"   => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "gender" => {:type => :fixed, :string => "m"},
          },
        })
        ddo.database_type = :sql_server

        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should scaffold columns that can't be found" do
          output_string.should match(/"age"\s+=>\s+:keep.+scaffold/)
          output_string.should match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should enumerate extra columns" do
          output_string.should match(/\#\s*"gender"/)
        end
      end

      context "when there is an existing config to scaffold and it is just right" do
        string = <<-SQL
        INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_table" => {
            "email" => {
              :type            => :email,
              :honk_email_skip => true,
            },
            "name" => {
              :type   => :string,
              :length => 8,
              :chars  => Triki::USERNAME_CHARS,
            },
            "something" => :keep,
            "age"       => :keep,
          },
        })
        ddo.database_type = :sql_server

        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should say that everything is present and accounted for" do
          output_string.should match(/^\s*\#.*account/)
          output_string.should_not contain("scaffold")
          output_string.should_not contain(%{"some_table"})
        end
      end

      context "when scaffolding a table with no existing config" do
        string = <<-SQL
        INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
        SQL
        database_dump = IO::Memory.new(string)
        ddo = Triki.new({
          "some_other_table" => {
            "email"     => {:type => :email, :honk_email_skip => true},
            "name"      => {:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
            "something" => :keep,
            "age"       => :keep,
          },
        })
        ddo.database_type = :sql_server
        ddo.globally_kept_columns = %w[age]

        output = IO::Memory.new
        ddo.scaffold(database_dump, output)
        output.rewind
        output_string = output.gets_to_end

        it "should scaffold all the columns that are not globally kept" do
          output_string.should match(/"email"\s+=>\s+:keep.+scaffold/)
          output_string.should match(/"name"\s+=>\s+:keep.+scaffold/)
          output_string.should match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally kept columns" do
          output_string.should_not match(/"age"\s+=>\s+:keep.+scaffold/)
        end
      end
    end
  end
end
