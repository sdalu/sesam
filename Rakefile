# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"

# The suite runs once per store (TestStore in test/test_helper.rb), so
# that both answer it alike.
STORES = %w[sequel json].freeze

STORES.each do |kind|
    task("store:#{kind}") { ENV["SESAM_STORE"] = kind }
    Rake::TestTask.new("test:#{kind}") do |task|
        task.libs << "lib" << "test"
        task.pattern = "test/**/*_test.rb"
    end
    task "test:#{kind}" => "store:#{kind}"
end

desc "Run the suite on every store"
task test: STORES.map { "test:#{it}" }

RuboCop::RakeTask.new

task default: %i[test rubocop]
