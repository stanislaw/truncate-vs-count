desc "Run MySQL test"
task :mysql do
  system %[bundle exec ruby truncate-vs-count-on-mysql.rb]
end

desc "Run MySQL test"
task :postgres do
  system %[bundle exec ruby truncate-vs-count-on-postgres.rb]
end

task :default => :mysql
