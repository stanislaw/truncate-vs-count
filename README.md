# Truncate vs Count

## Results

```text
MySQL
Truncate non-empty tables (AUTO_INCREMENT is not ensured)
  0.010000   0.000000   0.010000 (  0.013020)
Truncate non-empty tables (AUTO_INCREMENT ensured)
  0.010000   0.000000   0.010000 (  0.035882)
Truncate all tables one by one:
  0.000000   0.000000   0.000000 (  1.751737)
Truncate all tables with DatabaseCleaner:
  0.020000   0.010000   0.030000 (  1.626581)

PostgreSQL
Truncate non-empty tables (AUTO_INCREMENT ensured)
  0.010000   0.000000   0.010000 (  0.068535)
Truncate non-empty tables (AUTO_INCREMENT is not ensured)
  0.010000   0.010000   0.020000 (  0.018928)
Truncate all tables:
  0.010000   0.000000   0.010000 (  1.673684)
Truncate all tables with DatabaseCleaner:
  0.000000   0.000000   0.000000 (  1.124540)
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

1.upto(30).each do |n|
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
  class_eval %{
    1.upto(N) do |n|
      1.upto(Nrecords) do |nr|
        User#{N}.create!
      end
    end
  }
end

truncation_with_counts_no_reset_ids = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
      if table_count == 0
        next
      else
        execute "TRUNCATE TABLE #{table}"
      end
    end
  end
end

fill_tables

truncation_with_counts = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
      if table_count == 0
        # if we set 'next' right here
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

        execute "TRUNCATE TABLE #{table}" if auto_inc.first.first > 1

        # This is slower than just TRUNCATE
        # execute "ALTER TABLE #{table} AUTO_INCREMENT = 1" if auto_inc.first.first > 1
      else
        execute "TRUNCATE TABLE #{table}"
      end
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

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{truncation_with_counts_no_reset_ids}"

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{truncation_with_counts}"

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

1.upto(N) do |n|
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
  class_eval %{
    1.upto(N) do |n|
      1.upto(Nrecords) do |nr|
        User#{N}.create!
      end
    end
  }
end

fill_tables

truncation_with_counts = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables_to_truncate = []
    tables.each do |table|
      table_last_value = execute(<<-TRUNCATE_IF
        SELECT last_value from #{table}_id_seq;
      TRUNCATE_IF
      ).first['last_value'].to_i

      if table_last_value > 1
        # truncate_table table
        tables_to_truncate << table
      end
    end

    execute("TRUNCATE TABLE #{tables_to_truncate.join(',')};") if tables_to_truncate.any?
  end
end

fill_tables

truncation_with_counts_no_reset_ids = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      table_count = execute(<<-TRUNCATE_IF
      DO $$DECLARE r record;
      BEGIN 
        IF EXISTS(select * from #{table}) THEN
        TRUNCATE TABLE #{table};
        END IF;
      END$$;
      TRUNCATE_IF
      )
    end
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

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{truncation_with_counts}"

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{truncation_with_counts_no_reset_ids}"

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
