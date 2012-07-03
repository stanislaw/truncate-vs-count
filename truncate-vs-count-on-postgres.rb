require 'logger'
require 'active_record'

require 'benchmark'
require 'sugar-high/dsl' # I just can't write this ActiveRecord::Base.connection each time!

ActiveRecord::Base.logger = Logger.new(STDERR)

puts "Active Record #{ActiveRecord::VERSION::STRING}"

ActiveRecord::Base.establish_connection(
  adapter:  'postgresql',
  database: 'truncate_vs_count',
  username: 'postgres',
  password: '',
  host:     '127.0.0.1'
)

require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

(1..30).each do |n|
  ActiveRecord::Schema.define do
    create_table :"users_#{n}", :force => true do |t|
      t.integer :name
    end
  end
end

class User1 < ActiveRecord::Base
  self.table_name = 'users_1'
end

16.times { User1.create! }

User1.delete_all

raise "stuck with faster PG procedure - does it exist or not?"

truncation_with_counts = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      # IF EXISTS(select * from #{table}) THEN
      # END IF;

      # table_count = execute(<<-TRUNCATE_IF
      # DO $$DECLARE r record;
      # BEGIN 
      #   IF (SELECT last_value from #{table}_id_seq) THEN
      #   TRUNCATE TABLE #{table};
      #   END IF;
      # END$$;
      # TRUNCATE_IF
      # )
    end
  end
end

u = User1.create!

# raise u.inspect
# raise "u.id should == 1" if u.id != 1

just_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    truncate_tables tables
  end
end

database_cleaner = Benchmark.measure do
  DatabaseCleaner.clean
end

puts "Truncate non-empty tables (AUTO_INCREMENT ensured)\n#{truncation_with_counts}"

puts "Truncate all tables:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"
