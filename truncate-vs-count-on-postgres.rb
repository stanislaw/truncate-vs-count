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

    # The following is the fastest I found
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
