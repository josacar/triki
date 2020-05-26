# Triki

[![Build Status](https://travis-ci.org/josacar/triki.svg?branch=master)](https://travis-ci.org/josacar/triki)

You want to develop against real production data, but you don't want to violate your users' privacy.  Enter Triki: standalone Crystal code for the selective rewriting of SQL dumps in order to protect user privacy.  It supports MySQL, Postgres, and SQL Server.

# Install

Add this in your `shard.yml`

```
dependencies:
  triki:
    github: josacar/triki
```

And then run `shards install`

# Example Usage

Make an obfuscator.cr script:

```crystal
require "triki"

obfuscator = Triki.new(Triki::ConfigHash{
  "people" => Triki::ConfigTableHash{
    "email"                     => Triki::ConfigColumnHash{ :type => :email, :skip_regexes => [/^[\w\.\_]+@my_company\.com$/i] },
    "ethnicity"                 => :keep,
    "crypted_password"          => Triki::ConfigColumnHash{ :type => :fixed, :string => "SOME_FIXED_PASSWORD_FOR_EASE_OF_DEBUGGING" },
    "salt"                      => Triki::ConfigColumnHash{ :type => :fixed, :string => "SOME_THING" },
    "remember_token"            => :null,
    "remember_token_expires_at" => :null,
    "age"                       => Triki::ConfigColumnHash{ :type => :null, :unless => ->(person : Triki::ConfigApplicator::RowAsHash) { person["email"] == "hello@example.com" } },
    "photo_file_name"           => :null,
    "photo_content_type"        => :null,
    "photo_file_size"           => :null,
    "photo_updated_at"          => :null,
    "postal_code"               => Triki::ConfigColumnHash{ :type => :fixed, :string => "94109", :unless => ->(person : Triki::ConfigApplicator::RowAsHash) { person["postal_code"] == "12345"} },
    "name"                      => :name,
    "full_address"              => :address,
    "bio"                       => Triki::ConfigColumnHash{ :type => :lorem, :number => 4 },
    "relationship_status"       => Triki::ConfigColumnHash{ :type => :fixed, :one_of => ["Single", "Divorced", "Married", "Engaged", "In a Relationship"] },
    "has_children"              => Triki::ConfigColumnHash{ :type => :integer, :between => 0..1 },
  },

  "invites"                     => :truncate,
  "invite_requests"             => :truncate,
  "tags"                        => :keep,

  "relationships" => Triki::ConfigTableHash{
    "account_id"                => :keep,
    "code"                      => Triki::ConfigColumnHash{ :type => :string, :length => 8, :chars => Triki::USERNAME_CHARS }
  }
})
obfuscator.fail_on_unspecified_columns = true # if you want it to require every column in the table to be in the above definition
obfuscator.globally_kept_columns = %w[id created_at updated_at] # if you set fail_on_unspecified_columns, you may want this as well
# If you'd like to also validate against your schema.cr file to make sure all fields and tables are present, see https://gist.github.com/cantino/5376e73b0ad806dc4da4
obfuscator.obfuscate(STDIN, STDOUT)
```

And to get an obfuscated dump:

    mysqldump -c --add-drop-table --hex-blob -u user -ppassword database | obfuscator > obfuscated_dump.sql

Note that the -c option on mysqldump is required to use triki.  Additionally, the default behavior of mysqldump
is to output special characters. This may cause trouble, so you can request hex-encoded blob content with --hex-blob.
If you get MySQL errors due to very long lines, try some combination of --max_allowed_packet=128M, --single-transaction, --skip-extended-insert, and --quick.

## Database Server

By default the database type is assumed to be MySQL, but you can use the
builtin SQL Server support by specifying:

    obfuscator.database_type = :sql_server
    obfuscator.database_type = :postgres

If using Postgres, use pg_dump to get a dump:

    pg_dump database | ruby obfuscator > obfuscated_dump.sql

## Types

Available types include: email, string, lorem, name, first_name, last_name, address, street_address, secondary_address, city, state,
zip_code, phone, company, ipv4, ipv6, url, integer, fixed, null, and keep.

## Helping with creation of the "obfuscator.cr" script

If you don't want to type all those table names and column names into your obfuscator.cr script,
you can use triki to do some of that work for you. It can consume your database dump file and create a "scaffold" for the script.
To run triki in this mode, start with an "empty" scaffolder.cr script as follows:

```crystal

obfuscator = Triki.new(Triki::ConfigHash{})
obfuscator.scaffold(STDIN, STDOUT)
```

Then feed in your database dump:
  mysqldump -c  --hex-blob -u user -ppassword database | ruby scaffolder > obfuscator_scaffold_snippet
  pg_dump database | ruby scaffolder > obfuscator_scaffold_snippet

The output will be a series of configuration statements of the form:
    "table_name" => {
      "column1_name"     => :keep   # scaffold
      "column2_name"     => :keep   # scaffold
  	... etc.

Scaffolding also works if you have a partial configuration.  If your configuration is missing some tables or some columns, a call to 'scaffold' will pass through the configuration that exists and augment it with scaffolding for the missing tables or columns.

## Speed

The main motivation to rewrite this from Ruby to Crystal was speed, here is an example obfuscating 16 tables and 15 columns in total.

### MySQL dump 160MB (gzip'ed)

#### Ruby

```
real    1m56.980s
user    1m57.080s
sys     0m2.660s
```

#### Crystal

```
real    0m26.579s
user    0m28.220s
sys     0m1.748s
```

### MySQL dump 1.4G

#### Ruby

```
real    1m52.974s
user    1m49.824s
sys     0m4.560s
```

#### Crystal

```
real    0m17.642s
user    0m17.952s
sys     0m2.192s
```

That's about 6.40x speedup compared to the Ruby version.

## Changes

* Support for Postgres.  Thanks @samuelreh!
* Support for SQL Server
* :unless and :if now support :nil as a shorthand for a Proc that checks for nil
* :name, :lorem, and :address are all now supported types.  You can pass :number to :lorem to specify how many sentences to generate.  The default is one.
* <tt>{ :type => :whatever }</tt> is now optional when no additional options are needed.  Just use <tt>:whatever</tt>.
* Warnings are thrown when an unknown column type or table is encountered.  Use <tt>:keep</tt> in both cases.
* <tt>{ :type => :fixed, :string => Proc { |row| ... } }</tt> is now available.

## Note on Patches/Pull Requests

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a future version unintentionally.
* Commit, do not mess with rakefile, version, or history.  (If you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
* Send me a pull request. Bonus points for topic branches.

## Thanks

Forked from [https://github.com/cantino/my_obfuscate](https://github.com/cantino/my_obfuscate)

Thanks to all of the authors and contributors of the original Ruby gem

## LICENSE

This work is provided under the MIT License.  See the included LICENSE file.

The included English word frequency list used for generating random text is provided under the Creative Commons – Attribution / ShareAlike 3.0 license by http://invokeit.wordpress.com/frequency-word-lists/
