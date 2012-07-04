# truncate-vs-count-on-postgres.rb
require 'logger'
require 'active_record'

require 'benchmark'
require 'sugar-high/dsl' # I just can't write this ActiveRecord::Base.connection each time!

# ActiveRecord::Base.logger = Logger.new(STDERR)

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

N = 10
Nrecords = 1

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
     
      # TODO
      # count = execute(<<-TR
        # SELECT COUNT(*) FROM #{table}
      # TR
      # ).first['count'].to_i
      
      # count = execute(<<-TR
      #   SELECT true FROM #{table};
      # TR
      # )
      # puts count[0]
      # tables_to_truncate << table if count > 0
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

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{truncation_with_counts}"

puts "Truncate non-empty tables (AUTO_INCREMENT is not ensured)\n#{truncation_with_counts_no_reset_ids}"

puts "Truncate all tables:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"
