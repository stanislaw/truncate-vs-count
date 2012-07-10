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
    # next if n % 2 == 0
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
