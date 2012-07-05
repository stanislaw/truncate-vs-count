# Truncate vs Count

## Results

```text
MySQL
Truncate non-empty tables (AUTO_INCREMENT ensured)
  0.020000   0.010000   0.030000 (  0.080714)
Truncate non-empty tables (AUTO_INCREMENT is not ensured)
  0.010000   0.000000   0.010000 (  0.018336)
Truncate all tables one by one:
  0.010000   0.000000   0.010000 (  2.153827)
Truncate all tables with DatabaseCleaner:
  0.020000   0.000000   0.020000 (  1.639190)

PostgreSQL
Truncate non-empty tables (AUTO_INCREMENT ensured)
  0.010000   0.010000   0.020000 (  0.031100)
Truncate non-empty tables (AUTO_INCREMENT is not ensured)
  0.020000   0.000000   0.020000 (  0.026556)
Truncate all tables:
  0.010000   0.000000   0.010000 (  1.659555)
Truncate all tables with DatabaseCleaner:
  0.000000   0.000000   0.000000 (  1.183262)
```

## Code

### MySQL
```ruby
# truncate-vs-count-on-mysql.rb
require 'logger'
require 'active_record'

require 'benchmark'
require 'sugar-high/dsl' # I just can't write this ActiveRecord::Base.connection each time!

ActiveRecord::Base.logger = Logger.new(STDERR)

puts "Active Record #{ActiveRecord::VERSION::STRING}"

ActiveRecord::Base.establish_connection(
  :adapter  => 'mysql2',
  :database => 'truncate_vs_count',
  :host => 'localhost',
  :username => 'root',
  :password => '',
  :encoding => 'utf8'
)

require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

N = 30
Nrecords = 0

with ActiveRecord::Base.connection do
  tables.each do |table|
    drop_table table
  end
end

1.upto(N).each do |n|
  ActiveRecord::Schema.define do
    create_table :"users_#{n}", :force => true do |t|
      t.integer :name
    end
  end

  class_eval %{
    class ::User#{n} < ActiveRecord::Base
      self.table_name = 'users_#{n}'
    end
  } 
end

def fill_tables
  1.upto(N) do |n|
    1.upto(Nrecords) do |nr|
      Kernel.const_get(:"User#{n}").create!
    end
  end
end

fill_tables

fast_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|

      # This is from where it initially began:
      # rows_exist = execute("SELECT COUNT(*) FROM #{table}").first.first

      # Seems to be faster:
      rows_exist = execute("SELECT EXISTS(SELECT 1 FROM #{table} LIMIT 1)").first.first

      if rows_exist == 0
        # if we set 'next' right here (see next test case below)
        # it will work EVEN MORE FAST (10ms for 30 tables)!
        # But problem that then we will not reset AUTO_INCREMENT
        #
        # 
        # next

        auto_inc = execute <<-AUTO_INCREMENT
          SELECT Auto_increment 
          FROM information_schema.tables 
          WHERE table_name='#{table}'
        AUTO_INCREMENT

        # This is slower than just TRUNCATE
        # execute "ALTER TABLE #{table} AUTO_INCREMENT = 1" if auto_inc.first.first > 1
        truncate_table if auto_inc.first.first > 1
      else
        truncate_table table
      end
    end
  end
end

fill_tables

fast_truncation_no_reset_ids = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      # table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
      rows_exist = execute("SELECT EXISTS(SELECT 1 FROM #{table} LIMIT 1)").first.first
      truncate_table table if rows_exist == 1
    end
  end
end

fill_tables

just_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      execute "TRUNCATE TABLE #{table}"
    end
  end
end

fill_tables

database_cleaner = Benchmark.measure do
  DatabaseCleaner.clean
end

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{fast_truncation}"

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{fast_truncation_no_reset_ids}"

puts "Truncate all tables one by one:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"
```

### PostgreSQL

```ruby
# truncate-vs-count-on-postgres.rb
require 'logger'
require 'active_record'

require 'benchmark'
require 'sugar-high/dsl' # I just can't write this ActiveRecord::Base.connection each time!

ActiveRecord::Base.logger = Logger.new(STDERR)

puts "Active Record #{ActiveRecord::VERSION::STRING}"

db = { :database => 'truncate_vs_count' }

db_spec = {
  adapter:  'postgresql',
  username: 'postgres',
  password: '',
  host:     '127.0.0.1'
}

ActiveRecord::Base.establish_connection(db_spec.merge(db))

require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

N = 30
Nrecords = 0

with ActiveRecord::Base.connection do
  tables.each do |table|
    drop_table table
  end
end

1.upto(N) do |n|
  ActiveRecord::Schema.define do
    create_table :"users_#{n}", :force => true do |t|
      t.string :name
    end
  end

  class_eval %{
    class ::User#{n} < ActiveRecord::Base
      self.table_name = 'users_#{n}'
    end
  } 
end

def fill_tables
  1.upto(N) do |n|
    1.upto(Nrecords) do |nr|
      Kernel.const_get(:"User#{n}").create! :name => 'stanislaw'
    end
  end
end

fill_tables

fast_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables_to_truncate = []
    tables.each do |table|
      begin
        # [PG docs] currval: return the value most recently obtained by nextval for this sequence in the current session. (An error is reported if nextval has never been called for this sequence in this session.) Notice that because this is returning a session-local value, it gives a !!!predictable answer whether or not other sessions have executed nextval since the current session did!!!.

        table_curr_value = execute(<<-CURR_VAL
          SELECT currval('#{table}_id_seq');
        CURR_VAL
        ).first['currval'].to_i
      rescue ActiveRecord::StatementInvalid 

        # Here we are catching PG error, PG doc about states.
        # I don't like that PG gem do not raise its own exceptions. Or maybe I don't know how to handle them?

        table_curr_value = nil
      end

      if table_curr_value && table_curr_value > 0
        tables_to_truncate << table
      end
    end

    truncate_tables tables_to_truncate if tables_to_truncate.any?
  end
end

fill_tables

fast_truncation_no_reset_ids = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables_to_truncate = []
    tables.each do |table|
      # Anonymous blocks are supported only in PG9.
      # It should be somehow rewritten for older versions.
      # execute(<<-TRUNCATE_IF
      # DO $$DECLARE r record;
      # BEGIN 
        # IF EXISTS(select * from #{table}) THEN
        # TRUNCATE TABLE #{table};
        # END IF;
      # END$$;
      # TRUNCATE_IF
      # )

      # This one is good, but works too slow
      # execute(<<-TRUNCATE_IF
        # CREATE OR REPLACE FUNCTION truncate_if()
        # RETURNS void AS $$
        # BEGIN 
          # IF EXISTS(select * from #{table}) THEN
          # TRUNCATE TABLE #{table};
          # END IF;
        # END$$ LANGUAGE plpgsql;
        # SELECT truncate_if();
        # TRUNCATE_IF
      # )

      # Maybe this is the fastest?
      # count = execute(<<-TR
        # SELECT COUNT(*) FROM #{table} WHERE EXISTS(SELECT * FROM #{table})
      # TR
      # ).first['count'].to_i


      # The following is the fastest I found. It could be even written as 
      # select exists (select true from #{table} limit 1);
      # But I don't like to parse result PG gem gives. like {"?column?"=>"t"}

      at_least_one_row = execute(<<-TR
        SELECT true FROM #{table} LIMIT 1;
      TR
      )

      tables_to_truncate << table if at_least_one_row.any?
    end

    truncate_tables tables_to_truncate if tables_to_truncate.any?
  end
end

fill_tables

just_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |t|
      truncate_table t
    end
  end
end

fill_tables

database_cleaner = Benchmark.measure do
  DatabaseCleaner.clean
end

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{fast_truncation}"

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{fast_truncation_no_reset_ids}"

puts "Truncate all tables:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"
```

## Run it

```ruby
bundle

rake # runs MySQL test

rake mysql 
rake postgres
```

## Copyright
Copyright (c) 2012 Stanislaw Pankevich.
