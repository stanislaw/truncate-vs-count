# Truncate vs Count

This has been merged in ```database_cleaner``` as ```:pre_count``` option. See issues [126](https://github.com/bmabey/database_cleaner/issues/126) and [127](https://github.com/bmabey/database_cleaner/pull/127).

## Results

```text
MySQL
Truncate non-empty tables (AUTO_INCREMENT ensured)
  0.020000   0.000000   0.020000 (  0.554784)
Truncate non-empty tables (AUTO_INCREMENT is not ensured)
  0.020000   0.010000   0.030000 (  0.532889)
Truncate all tables one by one:
  0.020000   0.000000   0.020000 (  1.207616)
Truncate all tables with DatabaseCleaner:
  0.060000   0.010000   0.070000 (  1.284068)
Delete all tables one by one:
  0.010000   0.000000   0.010000 (  1.173978)
Delete non-empty tables one by one:
  0.010000   0.010000   0.020000 (  1.091690)

PostgreSQL
Truncate non-empty tables (AUTO_INCREMENT ensured)
  0.020000   0.010000   0.030000 (  0.558285)
Truncate non-empty tables (AUTO_INCREMENT is not ensured)
  0.010000   0.000000   0.010000 (  0.547050)
Truncate all tables:
  0.010000   0.000000   0.010000 (  1.443918)
Truncate all tables with DatabaseCleaner:
  0.000000   0.000000   0.000000 (  1.094980)
Delete all tables one by one:
  0.010000   0.000000   0.010000 (  0.176712)
Delete non-empty tables one by one:
  0.010000   0.000000   0.010000 (  0.176628)
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
NUM_RECORDS = 10
NUM_RUNS = 5

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
    next if n % 2 == 0
    values = (1..NUM_RECORDS).map{|i| "(#{i})" }.join(",") 
    ActiveRecord::Base.connection.execute("INSERT INTO users_#{n} (name) VALUES #{values};") if NUM_RECORDS > 0
  end
end

def benchmark_clean(&block)
  # I am sure it is not needed here, because we are measuring speed, not memuse
  # GC.start
  # sleep 1

  results = []

  NUM_RUNS.times do
    fill_tables
    results << Benchmark.measure do
      with(ActiveRecord::Base.connection, &block)
    end
  end

  # we get the best real time result of procedure being run for NUM_RUNS times
  results.sort{|x, y| x.real <=> y.real}.first
end


fast_truncation = benchmark_clean do
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


fast_truncation_no_reset_ids = benchmark_clean do
  tables.each do |table|
    # table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
    rows_exist = execute("SELECT EXISTS(SELECT 1 FROM #{table} LIMIT 1)").first.first
    truncate_table table if rows_exist == 1
  end
end


just_truncation = benchmark_clean do
  tables.each do |table|
    execute "TRUNCATE TABLE #{table}"
  end
end

database_cleaner = benchmark_clean do
  DatabaseCleaner.clean
end

just_deletion = benchmark_clean do
  tables.each do |table|
    execute "DELETE FROM #{table}"
  end
end


fast_deletion_no_reset_ids = benchmark_clean do
  tables.each do |table|
    rows_exist = execute("SELECT EXISTS(SELECT 1 FROM #{table} LIMIT 1)").first.first
    execute("DELETE FROM #{table}") if rows_exist == 1
  end
end


puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{fast_truncation}"

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{fast_truncation_no_reset_ids}"

puts "Truncate all tables one by one:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"

puts "Delete all tables one by one:\n#{just_deletion}"

puts "Delete non-empty tables one by one:\n#{fast_deletion_no_reset_ids}"
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
NUM_RECORDS = 10
NUM_RUNS = 5

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
    next if n % 2 == 0
    values = (1..NUM_RECORDS).map{|i| "(#{i})" }.join(",") 
    ActiveRecord::Base.connection.execute("INSERT INTO users_#{n} (name) VALUES #{values};") if NUM_RECORDS > 0
  end
end

def benchmark_clean(&block)
  # I am sure it is not needed here, because we are measuring speed, not memuse
  # GC.start
  # sleep 1

  results = []

  NUM_RUNS.times do
    fill_tables
    results << Benchmark.measure do
      with(ActiveRecord::Base.connection, &block)
    end
  end

  # we get the best real time result of procedure being run for NUM_RUNS times

  results.sort{|x, y| x.real <=> y.real}.first
end

fast_truncation = benchmark_clean do
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

fast_truncation_no_reset_ids = benchmark_clean do
  tables_to_truncate = []
  tables.each do |table|

    # The following is the fastest I found. 
    at_least_one_row = execute(<<-TR
      SELECT true FROM #{table} LIMIT 1;
    TR
    )

    tables_to_truncate << table if at_least_one_row.any?
  end

  truncate_tables tables_to_truncate if tables_to_truncate.any?
end

just_truncation = benchmark_clean do
  tables.each do |t|
    truncate_table t
  end
end

database_cleaner = benchmark_clean do
  DatabaseCleaner.clean
end

just_deletion = benchmark_clean do
  tables.each do |table|
    execute "DELETE FROM #{table}"
  end
end

fast_deletion_no_reset_ids = benchmark_clean do
  tables.each do |table|
    at_least_one_row = execute(<<-TR
      SELECT true FROM #{table} LIMIT 1;
    TR
    )

    execute("DELETE FROM #{table}") if at_least_one_row.any?
  end
end

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{fast_truncation}"

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{fast_truncation_no_reset_ids}"

puts "Truncate all tables:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"

puts "Delete all tables one by one:\n#{just_deletion}"

puts "Delete non-empty tables one by one:\n#{fast_deletion_no_reset_ids}"
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
