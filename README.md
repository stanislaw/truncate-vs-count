# Truncate vs Count

## Results

```text
Truncate only non-empty tables:
  0.010000   0.000000   0.010000 (  0.012800)
Truncate all tables:
  0.010000   0.000000   0.010000 (  1.425400)
Truncate all tables with DatabaseCleaner:
  0.020000   0.010000   0.030000 (  1.625825)
```

## Script

```ruby
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

(1..30).each do |n|
  ActiveRecord::Schema.define do
    create_table :"users_#{n}", :force => true do |t|
      t.integer :name
    end
  end
end

class User < ActiveRecord::Base
end

truncation_with_counts = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      table_count = execute("SELECT COUNT(*) FROM #{table}").first.first
      execute "TRUNCATE #{table}" unless table_count == 0
    end
  end
end

just_truncation = Benchmark.measure do
  with ActiveRecord::Base.connection do
    tables.each do |table|
      execute "TRUNCATE #{table}"
    end
  end
end

database_cleaner = Benchmark.measure do
  DatabaseCleaner.clean
end

puts "Truncate only non-empty tables:\n#{truncation_with_counts}"

puts "Truncate all tables:\n#{just_truncation}"

puts "Truncate all tables with DatabaseCleaner:\n#{database_cleaner}"
```

## Run it

```ruby
rake
```
