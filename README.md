# Triki

[![Build Status](https://github.com/josacar/triki/workflows/Crystal%20CI/badge.svg)](https://github.com/josacar/triki/actions)

You want to develop against real production data, but you don't want to violate your users' privacy.  Enter Triki: standalone Crystal code for the selective rewriting of SQL dumps in order to protect user privacy.

# Documentation

[Here](https://josacar.github.io/triki/) you can find the latest generated API documentation about this library.

# Supported databases and versions

## Servers

- MySQL
- Postgres
- SQL Server

## Clients

- `pg_dump` ( Postgresql ) up to 15.x
- `mysqldump` ( MySQL ) up to 8.2
- `mysqldump` ( MariaDB ) aka `mariadb-dump` ( since v0.3.0 ) up to 10.11

**Note**: Clients may break current SQL dump parsing as by now there is no proper integration testing in CI with all combinations of servers and clients versions, above versions have been partially manually tested.

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

obfuscator = Triki.new({
  "people" => {
    "email"                     => { :type => :email, :skip_regexes => [/^[\w\.\_]+@my_company\.com$/i] },
    "ethnicity"                 => :keep,
    "crypted_password"          => { :type => :fixed, :string => "SOME_FIXED_PASSWORD_FOR_EASE_OF_DEBUGGING" },
    "bank_account"              => { :type => :fixed, :string =>  ->(row : Triki::RowAsHash) { "#{row["bank_account"].to_s[0..4]}#{"*" * (row["email"].to_s.size - 5)}".as(Triki::RowContent) } },
    "salt"                      => { :type => :fixed, :string => "SOME_THING" },
    "remember_token"            => :null,
    "remember_token_expires_at" => :null,
    "age"                       => { :type => :null, :unless => ->(row : Triki::RowAsHash) { row["email"] == "hello@example.com" } },
    "photo_file_name"           => :null,
    "photo_content_type"        => :null,
    "photo_file_size"           => :null,
    "photo_updated_at"          => :null,
    "postal_code"               => { :type => :fixed, :string => "94109", :unless => ->(person : Triki::RowAsHash) { person["postal_code"] == "12345"} },
    "name"                      => :name,
    "full_address"              => :address,
    "bio"                       => { :type => :lorem, :number => 4 },
    "relationship_status"       => { :type => :fixed, :one_of => ["Single", "Divorced", "Married", "Engaged", "In a Relationship"] },
    "has_children"              => { :type => :integer, :between => 0..1 },
  },
  "invites"                     => :truncate,
  "invite_requests"             => :truncate,
  "tags"                        => :keep,
  "relationships" => {
    "account_id"                => :keep,
    "code"                      => { :type => :string, :length => 8, :chars => Triki::USERNAME_CHARS }
  }
})
obfuscator.fail_on_unspecified_columns = true # if you want it to require every column in the table to be in the above definition
obfuscator.globally_kept_columns = %w[id created_at updated_at] # if you set fail_on_unspecified_columns, you may want this as well

obfuscator.obfuscate(STDIN, STDOUT)
```

And to get an obfuscated dump:

```
mysqldump -c --add-drop-table --hex-blob -u user -ppassword database | obfuscator > obfuscated_dump.sql
```

Note that the -c option on mysqldump is required to use triki.  Additionally, the default behavior of mysqldump
is to output special characters. This may cause trouble, so you can request hex-encoded blob content with `--hex-blob`.
If you get MySQL errors due to very long lines, try some combination of `--max_allowed_packet=128M`, `--single-transaction`, `--skip-extended-insert`, and `--quick`.

## Database Server

By default the database type is assumed to be MySQL, but you can use the builtin SQL Server support by specifying:

```crystal
obfuscator.database_type = :sql_server
obfuscator.database_type = :postgres
```

If using Postgres, use `pg_dump` to get a dump:

```
pg_dump database | obfuscator > obfuscated_dump.sql
```

## Types

Available types include:
- email
- string
- lorem
- name
- first_name
- last_name
- address
- street_address
- secondary_address
- city
- state
- zip_code
- phone
- company
- ipv4
- ipv6
- url
- integer
- fixed
- null

and `keep` to keep the same value.

## Helping with creation of the "obfuscator.cr" script

If you don't want to type all those table names and column names into your obfuscator.cr script,
you can use triki to do some of that work for you. It can consume your database dump file and create a "scaffold" for the script.
To run triki in this mode, start with an "empty" scaffolder.cr script as follows:

```crystal
obfuscator = Triki.new
obfuscator.scaffold(STDIN, STDOUT)
```

Then feed in your database dump:

```
mysqldump -c  --hex-blob -u user -ppassword database | scaffolder > obfuscator_scaffold_snippet
pg_dump database | scaffolder > obfuscator_scaffold_snippet
```

The output will be a series of configuration statements of the form:

```crystal
  "table_name" => {
    "column1_name" => :keep   # scaffold
    "column2_name" => :keep   # scaffold
    ... etc.
```

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

## Note on Patches/Pull Requests

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a future version unintentionally.
* Commit, do not mess with version. (If you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
* Send me a pull request. Bonus points for topic branches.

## Thanks

Forked from [https://github.com/cantino/my_obfuscate](https://github.com/cantino/my_obfuscate)

Thanks to all of the authors and contributors of the original Ruby gem

## LICENSE

This work is provided under the MIT License.  See the included LICENSE file.

The included English word frequency list used for generating random text is provided under the Creative Commons – Attribution / ShareAlike 3.0 license by http://invokeit.wordpress.com/frequency-word-lists/
