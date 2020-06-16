require "./spec_helper"
require "log/spec"

Spectator.describe Triki do
  describe "Triki.reassembling_each_insert" do
    it "should yield each subinsert and reassemble the result" do
      column_names = ["a", "b", "c", "d"]
      test_insert = "INSERT INTO `some_table` (`a`, `b`, `c`, `d`) VALUES ('(\\'bob@bob.com','b()ob','some(thingelse1','25)('),('joe@joe.com','joe','somethingelse2','54');"
      test_insert_passes = [
        ["(\\'bob@bob.com", "b()ob", "some(thingelse1", "25)("],
        ["joe@joe.com", "joe", "somethingelse2", "54"]
      ]

      count = 0
      reassembled = Triki.new.reassembling_each_insert(test_insert, "some_table", column_names) do |sub_insert|
        expect(sub_insert).to eq(test_insert_passes.shift)
        count += 1
        sub_insert
      end
      expect(count).to eq(2)
      expect(reassembled).to eq(test_insert)
    end
  end

  describe "#obfuscate" do
    describe "when using Postgres" do
      let(dump) do
        IO::Memory.new(<<-'SQL')
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
      end

      let(obfuscator) do
        Triki.new(Triki::ConfigHash{
          "some_table" => Triki::ConfigTableHash{
            "email" => Triki::ConfigColumnHash{
              :type => :email,
              :skip_regexes => [
                /^[\w\.\_]+@honk\.com$/i,
                /^dontmurderme@direwolf.com$/
              ]
            },
            "name" => Triki::ConfigColumnHash{
              :type => :string,
              :length => 8,
              :chars => Triki::USERNAME_CHARS
            },
            "age" => Triki::ConfigColumnHash{
              :type => :integer,
              :between => 10...80,
              :unless => :nil
            },
          },
          "single_column_table" => Triki::ConfigTableHash{
            "id" => Triki::ConfigColumnHash{
              :type => :integer,
              :between => 2..9,
              :unless => :nil
            }
          },
          "another_table" => :truncate,
          "some_table_to_keep" => :keep
        }).tap do |o|
          o.database_type = :postgres
        end
      end

      let(output_string) do
        output = IO::Memory.new
        obfuscator.obfuscate(dump, output)
        output.rewind
        output.gets_to_end
      end

      let(scaffolder) do
        Triki.new(Triki::ConfigHash{
          "some_other_table" => Triki::ConfigTableHash{
            "email" => Triki::ConfigColumnHash{
              :type => :email,
              :skip_regexes => [/^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/]
            },
            "name" => Triki::ConfigColumnHash{
              :type => :string,
              :length => 8,
              :chars => Triki::USERNAME_CHARS
            },
            "age" => Triki::ConfigColumnHash{
              :type => :integer,
              :between => 10...80,
              :unless => :nil
            },
          },
          "single_column_table" => Triki::ConfigTableHash{
            "id" => Triki::ConfigColumnHash{
              :type => :integer,
              :between => 2..9,
              :unless => :nil
            }
          },
          "another_table" => :truncate,
          "some_table_to_keep" => :keep
        }).tap do |scaffolder|
          scaffolder.database_type = :postgres
          scaffolder.globally_kept_columns = %w[age]
        end
      end

      let(scaffold_output_string) do
        output = IO::Memory.new
        scaffolder.scaffold(dump, output)
        output.rewind
        output.gets_to_end
      end

      it "is able to obfuscate single column tables" do
        expect(output_string).not_to contain("1\n2\n")
        expect(output_string).to match(/\d\n\d\n/)
      end

      it "is able to truncate tables" do
        expect(output_string).not_to contain("1\t2\t3\t4")
      end

      it "can obfuscate the tables" do
        expect(output_string).to contain("COPY some_table (id, email, name, something, age) FROM stdin;\n")
        expect(output_string).to match(/1\t.*\t\S{8}\tmoose\t\d{2}\n/)
      end

      it "can skip nils" do
        expect(output_string).to match(/\d\n\d\n\\N/)
      end

      it "is able to keep tables" do
        expect(output_string).to contain("5\t6")
      end

      context "when dump contains INSERT statement" do
        let(dump) do
          IO::Memory.new(<<-SQL)
          INSERT INTO some_table (email, name, something, age) VALUES ('','', '', 25);
          SQL
        end

        it "raises an error if using postgres with insert statements" do
          expect_raises(RuntimeError) { output_string }
        end
      end

      it "when there is no existing config, should scaffold all the columns that are not globally kept" do
        expect(scaffold_output_string).to match(/"email"\s+=>\s+:keep.+scaffold/)
        expect(scaffold_output_string).to match(/"name"\s+=>\s+:keep.+scaffold/)
      end

      it "should not scaffold a columns that is globally kept" do
        expect(scaffold_output_string).not_to match(/"age"\s+=>\s+:keep.+scaffold/)
      end

      context "when dump contains a '.' at the end of the line" do
        let(dump) do
          IO::Memory.new(<<-'SQL')
            COPY another_table (a, b, c, d) FROM stdin;
            1    2       3       4
            1    2       3       .
            \.
            SQL
        end

        it "should not fail if a insert statement ends in a '.''" do
          expect(output_string).not_to match(/1\t2\t3\t\./)
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
          expect(output.gets_to_end).to eq(string)
        end
      end

      context "when the dump to obfuscate is missing columns" do
        it "should raise an error if a column name can't be found" do
          string =<<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :honk_email_skip => true
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "gender" => Triki::ConfigColumnHash{
                :type => :fixed,
                :string => "m"
              }
            }
          })
          output = IO::Memory.new

          expect_raises(RuntimeError) do
            ddo.obfuscate(database_dump, output)
          end
        end
      end

      context "when there is something to obfuscate" do
        let(output_string) do
          string =<<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54),('dontmurderme@direwolf.com','direwolf', 'somethingelse3', 44);
          INSERT INTO `another_table` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4), (5,6,7,8);
          INSERT INTO `some_table_to_keep` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4), (5,6,7,8);
          INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh', 'aawefjkafe', 'wadus'), ('hello1','kjhj!', 892938, 'tradus'), ('hello2','moose!!', NULL, NULL);
          INSERT INTO `an_ignored_table` (`col`, `col2`) VALUES ('hello','kjhjd^&dkjh'), ('hello1','kjhj!'), ('hello2','moose!!');
          SQL
          database_dump = IO::Memory.new(string)

          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :skip_regexes => [
                  /^[\w\.\_]+@honk\.com$/i,
                  /^dontmurderme@direwolf.com$/
                ]
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "age" => Triki::ConfigColumnHash{
                :type => :integer,
                :between => 10...80
              }
            },
            "another_table" => :truncate,
            "some_table_to_keep" => :keep,
            "one_more_table" => Triki::ConfigTableHash{
              # Note: fixed strings must be pre-SQL escaped!
              "password" => Triki::ConfigColumnHash{
                :type => :fixed,
                :string => "monkey"
              },
              "c" => Triki::ConfigColumnHash{
                :type => :null
              },
            }
          })
          output = IO::Memory.new
          ddo.obfuscate(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should be able to truncate tables" do
          expect(output_string).not_to contain("INSERT INTO `another_table`")
          expect(output_string).to contain("INSERT INTO `one_more_table`")
        end

        it "should be able to declare tables to keep" do
          expect(output_string).to contain("INSERT INTO `some_table_to_keep` (`a`, `b`, `c`, `d`) VALUES (1,2,3,4), (5,6,7,8);")
        end

        it "should ignore tables that it doesn't know about, but should warn" do
          error_output = Log.capture("triki") do
            expect(output_string).to contain("INSERT INTO `an_ignored_table` (`col`, `col2`) VALUES ('hello','kjhjd^&dkjh'), ('hello1','kjhj!'), ('hello2','moose!!');")
          end

          error_output.check(:warn, /an_ignored_table was not specified in the config/)
        end

        it "should obfuscate the tables" do
          expect(output_string).to contain("INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES (")
          expect(output_string).to contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES (")
          expect(output_string).to contain("'some\\'thin,ge())lse1'")
          expect(output_string).to contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','monkey',NULL,'wadus'),('hello1','monkey',NULL,'tradus'),('hello2','monkey',NULL,NULL);")
          expect(output_string).not_to contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh',NULL, 'wadus'),('hello1','kjhj!',NULL, 'tradus'),('hello2','moose!!',NULL, NULL);")
          expect(output_string).not_to contain("INSERT INTO `one_more_table` (`a`, `password`, `c`, `d,d`) VALUES ('hello','kjhjd^&dkjh',NULL,'wadus'),('hello1','kjhj!',NULL,'tradus'),('hello2','moose!!',NULL,NULL);")
          expect(output_string).not_to contain("INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);")
        end

        it "honors a special case: on the people table, rows with skip_regexes that match are skipped" do
          expect(output_string).to contain("('bob@honk.com',")
          expect(output_string).to contain("('dontmurderme@direwolf.com',")
          expect(output_string).not_to contain("joe@joe.com")
          expect(output_string).to contain("example.com")
        end
      end

      context "when fail_on_unspecified_columns is set to true" do
        let(database_dump) do
          string =<<-SQL
              INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54),('dontmurderme@direwolf.com','direwolf', 'somethingelse3', 44);
          SQL
          IO::Memory.new(string)
        end

        let(ddo) do
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :skip_regexes => [
                  /^[\w\.\_]+@honk\.com$/i,
                  /^dontmurderme@direwolf.com$/
                ]
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "age" => Triki::ConfigColumnHash{
                :type => :integer,
                :between => 10...80
              }
            }
          })
          ddo.fail_on_unspecified_columns = true
          ddo
        end

        it "should raise an exception when an unspecified column is found" do
          expect_raises(RuntimeError, /column 'something' defined/i) do
            ddo.obfuscate(database_dump, IO::Memory.new)
          end
        end

        it "should accept columns defined in globally_kept_columns" do
          ddo.globally_kept_columns = %w[something]
          expect {
            ddo.obfuscate(database_dump, IO::Memory.new)
          }.not_to raise_error
        end
      end

      context "when there is an existing config to scaffold" do
        let(database_dump) do
          string =<<-SQL
          INSERT IGNORE INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
          SQL
          IO::Memory.new(string)
        end
        let(output_string) do
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :honk_email_skip => true
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              }
            },
            "another_table" => :truncate
          })
          ddo.globally_kept_columns = %w[something]
          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should scaffold missing columns" do
          expect(output_string).to match(/"age"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally_kept_columns" do
          expect(output_string).not_to match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should pass through correct columns" do
          expect(output_string).not_to match(/"email"\s+=>\s+:keep.+scaffold/)
          expect(output_string).to match(/"email"\s+=>/)
          expect(output_string).not_to match(/\#\s*"email"/)
        end
      end

      context "when using :secondary_address" do
        let(output_string) do
          string =<<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`, `address1`, `address2`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25, '221B Baker St', 'Suite 100'),('joe@joe.com','joe', 'somethingelse2', 54, '1300 Pennsylvania Ave', '2nd floor');
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :honk_email_skip => true
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "something" => :keep,
              "age" => :keep,
              "address1" => :street_address,
              "address2" => :secondary_address
            }})
          output = IO::Memory.new
          ddo.obfuscate(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should obfuscate address1" do
          expect(output_string).to contain("address1")
          expect(output_string).not_to contain("Baker St")
        end

        it "should obfuscate address2" do
          expect(output_string).to contain("address2")
          expect(output_string).not_to contain("Suite 100")
        end
      end

      context "when there is an existing config to scaffold" do
        let(output_string) do
          string =<<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`, `address1`, `address2`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25, '221B Baker St', 'Suite 100'),('joe@joe.com','joe', 'somethingelse2', 54, '1300 Pennsylvania Ave', '2nd floor');
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :honk_email_skip => true
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "something" => :keep,
              "age" => :keep,
              "gender" => Triki::ConfigColumnHash{
                :type => :fixed,
                :string => "m"
              },
              "address1" => :street_address,
              "address2" => :secondary_address
            }})
          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should enumerate extra columns" do
          expect(output_string).to match(/\#\s*"gender"\s+=>\s+\{:type\s*=>\s*:fixed,\s*:string.*#\s*unreferenced/)
        end

        it "should pass through existing columns" do
          expect(output_string).to match(/"age"\s+=>\s+:keep\s*,/)
          expect(output_string).to match(/"address2"\s+=>\s*:secondary_address/)
        end
      end

      context "when there is an existing config to scaffold with both missing and extra columns" do
        let(output_string) do
          string =<<-SQL
          INSERT IGNORE INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "gender" => Triki::ConfigColumnHash{:type => :fixed, :string => "m"}
            }})
          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should scaffold missing columns" do
          expect(output_string).to match(/"age"\s+=>\s+:keep.+scaffold/)
          expect(output_string).to match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should enumerate extra columns" do
          expect(output_string).to match(/\#\s*"gender"/)
        end
      end

      context "when there is an existing config to scaffold and it is just right" do
        let(output_string) do
          string =<<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "something" => :keep,
              "age" => :keep
            }
          })
          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should say that everything is present and accounted for" do
          expect(output_string).to match(/^\s*\#.*account/)
          expect(output_string).not_to contain("scaffold")
          expect(output_string).not_to contain(%{"some_table"})
        end
      end

      context "when scaffolding a table with no existing config" do
        let(output_string) do
          string =<<-SQL
          INSERT INTO `some_table` (`email`, `name`, `something`, `age_of_the_individual_who_is_specified_by_this_row_of_the_table`) VALUES ('bob@honk.com','bob', 'some\\'thin,ge())lse1', 25),('joe@joe.com','joe', 'somethingelse2', 54);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_other_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "something" => :keep,
              "age_of_the_individual_who_is_specified_by_this_row_of_the_table" => :keep
            }})
          ddo.globally_kept_columns = %w[name]

          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should scaffold all the columns that are not globally kept" do
          expect(output_string).to match(/"email"\s+=>\s+:keep.+scaffold/)
          expect(output_string).to match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally kept columns" do
          expect(output_string).not_to match(/"name"\s+=>\s+:keep.+scaffold/)
        end

        it "should preserve long column names" do
          expect(output_string).to match(/"age_of_the_individual_who_is_specified_by_this_row_of_the_table"/)
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
          expect(output.gets_to_end).to eq(string)
        end
      end

      context "when the dump to obfuscate is missing columns" do
        let(database_dump) do
          string =<<-SQL
            INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          IO::Memory.new(string)
        end

        let(ddo) do
          ddo =  Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "gender" => Triki::ConfigColumnHash{:type => :fixed, :string => "m"}
            }})
          ddo.database_type = :sql_server
          ddo
        end

        let(output) { IO::Memory.new }

        it "should raise an error if a column name can't be found" do
          expect_raises(RuntimeError) do
            ddo.obfuscate(database_dump, output)
          end
        end
      end

      context "when there is something to obfuscate" do
        let(error_output) { IO::Memory.new }
        let(output_string) do
          string =<<-SQL
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

          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :skip_regexes => [
                  /^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/
                ]
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "age" => Triki::ConfigColumnHash{
                :type => :integer,
                :between => 10...80
              },
              "bday" => :keep
            },
            "another_table" => :truncate,
            "some_table_to_keep" => :keep,
            "one_more_table" => Triki::ConfigTableHash{
              # Note: fixed strings must be pre-SQL escaped!
              "password" => Triki::ConfigColumnHash{
                :type => :fixed,
                :string => "monkey"
              },
              "c" => Triki::ConfigColumnHash{
                :type => :null
              }
            }
          })
          ddo.database_type = :sql_server

          output = IO::Memory.new
          ddo.obfuscate(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should be able to truncate tables" do
          expect(output_string).not_to contain("INSERT [dbo].[another_table]")
          expect(output_string).to contain("INSERT [dbo].[one_more_table]")
        end

        it "should be able to declare tables to keep" do
          expect(output_string).to contain("INSERT [dbo].[some_table_to_keep] ([a], [b], [c], [d]) VALUES (1,2,3,4);")
          expect(output_string).to contain("INSERT [dbo].[some_table_to_keep] ([a], [b], [c], [d]) VALUES (5,6,7,8);")
        end

        it "should ignore tables that it doesn't know about, but should warn" do
          error_output = Log.capture("triki") do
            expect(output_string).to contain("INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello',N'kjhjd^&dkjh');")
            expect(output_string).to contain("INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello1',N'kjhj!');")
            expect(output_string).to contain("INSERT [dbo].[an_ignored_table] ([col], [col2]) VALUES (N'hello2',N'moose!!');")
          end

          error_output.check(:warn, /an_ignored_table was not specified in the config/)
        end

        it "should obfuscate the tables" do
          expect(output_string).to contain("INSERT [dbo].[some_table] ([email], [name], [something], [age], [bday]) VALUES (")
          expect(output_string).to contain("CAST(0x00009E1A00000000 AS DATETIME)")
          expect(output_string).to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (")
          expect(output_string).to contain("'some''thin,ge())lse1'")
          expect(output_string).to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello',N'monkey',NULL,N'wadus');")
          expect(output_string).to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello1',N'monkey',NULL,N'wadus');")
          expect(output_string).to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello2',N'monkey',NULL,N'wadus');")
          expect(output_string).not_to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello',N'kjhjd^&dkjh', N'aawefjkafe');")
          expect(output_string).not_to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello1',N'kjhj!', 892938);")
          expect(output_string).not_to contain("INSERT [dbo].[one_more_table] ([a], [password], [c], [d,d]) VALUES (N'hello2',N'moose!!', NULL);")
          expect(output_string).not_to contain("INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES (N'bob@honk.com',N'bob', N'some''thin,ge())lse1', 25, CAST(0x00009E1A00000000 AS DATETIME));")
          expect(output_string).not_to contain("INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES (N'joe@joe.com',N'joe', N'somethingelse2', 54, CAST(0x00009E1A00000000 AS DATETIME));")
        end

        it "honors a special case: on the people table, rows with anything@honk.com in a slot marked with :honk_email_skip do not change this slot" do
          expect(output_string).to contain("(N'bob@honk.com',")
          expect(output_string).to contain("(N'dontmurderme@direwolf.com',")
          expect(output_string).not_to contain("joe@joe.com")
        end
      end

      context "when fail_on_unspecified_columns is set to true" do
        let(database_dump) do
          string =<<-SQL
          INSERT INTO [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          IO::Memory.new(string)
        end

        let(ddo) do
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :skip_regexes => [/^[\w\.\_]+@honk\.com$/i, /^dontmurderme@direwolf.com$/]},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "age" => Triki::ConfigColumnHash{:type => :integer, :between => 10...80}
            }
          })
          ddo.database_type = :sql_server
          ddo.fail_on_unspecified_columns = true
          ddo
        end

        it "should raise an exception when an unspecified column is found" do
          expect {
            ddo.obfuscate(database_dump, IO::Memory.new)
          }.to raise_error(/column 'something' defined/i)
        end

        it "should accept columns defined in globally_kept_columns" do
          ddo.globally_kept_columns = %w[something]
          expect {
            ddo.obfuscate(database_dump, IO::Memory.new)
          }.not_to raise_error
        end
      end

      context "when there is an existing config to scaffold and it is missing columns" do
        let(output_string) do
          string =<<-SQL
          INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS}
            }})
          ddo.database_type = :sql_server
          ddo.globally_kept_columns = %w[something]
          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should scaffold columns that can't be found" do
          expect(output_string).to match(/"age"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally_kept_columns" do
          expect(output_string).not_to match(/"something"\s+=>\s+:keep.+scaffold/)
        end
      end

      context "when there is an existing config to scaffold and it has extra columns" do
        let(output_string) do
          string =<<-SQL
          INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "something" => :keep,
              "age" => :keep,
              "gender" => Triki::ConfigColumnHash{:type => :fixed, :string => "m"}
            }})
          ddo.database_type = :sql_server

          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should enumerate extra columns" do
          expect(output_string).to match(/\#\s*"gender"/)
        end
      end

      context "when there is an existing config to scaffold and it has both missing and extra columns" do
        let(output_string) do
          string =<<-SQL
          INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "gender" => Triki::ConfigColumnHash{:type => :fixed, :string => "m"}
            }})
          ddo.database_type = :sql_server

          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output_string = output.gets_to_end
        end

        it "should scaffold columns that can't be found" do
          expect(output_string).to match(/"age"\s+=>\s+:keep.+scaffold/)
          expect(output_string).to match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should enumerate extra columns" do
          expect(output_string).to match(/\#\s*"gender"/)
        end
      end

      context "when there is an existing config to scaffold and it is just right" do
        let(output_string) do
          string =<<-SQL
          INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{
                :type => :email,
                :honk_email_skip => true
              },
              "name" => Triki::ConfigColumnHash{
                :type => :string,
                :length => 8,
                :chars => Triki::USERNAME_CHARS
              },
              "something" => :keep,
              "age" => :keep
            }
          })
          ddo.database_type = :sql_server

          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output.gets_to_end
        end

        it "should say that everything is present and accounted for" do
          expect(output_string).to match(/^\s*\#.*account/)
          expect(output_string).not_to contain("scaffold")
          expect(output_string).not_to contain(%{"some_table"})
        end
      end

      context "when scaffolding a table with no existing config" do
        let(output_string) do
          string =<<-SQL
          INSERT [dbo].[some_table] ([email], [name], [something], [age]) VALUES ('bob@honk.com','bob', 'some''thin,ge())lse1', 25);
          SQL
          database_dump = IO::Memory.new(string)
          ddo = Triki.new(Triki::ConfigHash{
            "some_other_table" => Triki::ConfigTableHash{
              "email" => Triki::ConfigColumnHash{:type => :email, :honk_email_skip => true},
              "name" => Triki::ConfigColumnHash{:type => :string, :length => 8, :chars => Triki::USERNAME_CHARS},
              "something" => :keep,
              "age" => :keep
            }})
          ddo.database_type = :sql_server
          ddo.globally_kept_columns = %w[age]

          output = IO::Memory.new
          ddo.scaffold(database_dump, output)
          output.rewind
          output_string = output.gets_to_end
        end

        it "should scaffold all the columns that are not globally kept" do
          expect(output_string).to match(/"email"\s+=>\s+:keep.+scaffold/)
          expect(output_string).to match(/"name"\s+=>\s+:keep.+scaffold/)
          expect(output_string).to match(/"something"\s+=>\s+:keep.+scaffold/)
        end

        it "should not scaffold globally kept columns" do
          expect(output_string).not_to match(/"age"\s+=>\s+:keep.+scaffold/)
        end
      end

    end
  end
end
