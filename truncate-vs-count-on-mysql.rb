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
