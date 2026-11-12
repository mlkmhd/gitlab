# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'db:schema:load:<name> prerequisites fix', feature_category: :database do
  let(:rakefile) { Rails.root.join('lib/tasks/gitlab/db/schema_load_fix.rake') }

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new

    example.run
  ensure
    Rake.application = original_application
  end

  before do
    %w[main ci].each do |db_name|
      Rake::Task.define_task("db:test:purge:#{db_name}")
      Rake::Task.define_task("db:schema:load:#{db_name}" => ['load_config', "db:test:purge:#{db_name}"])
    end
  end

  def prerequisites_of(db_name)
    Rake::Task["db:schema:load:#{db_name}"].prerequisites
  end

  # Coverage resets a file's counters every time the file is loaded again, and examples run in
  # random order. A single example loads the rake file for both versions, Rails 8.1 first, so the
  # patched path is always loaded last and stays covered.
  it 'removes the test purge prerequisite only before Rails 8.1', :aggregate_failures do
    allow(Rails).to receive(:gem_version).and_return(Gem::Version.new('8.1.0'))
    load rakefile

    expect(prerequisites_of(:main)).to eq(%w[load_config db:test:purge:main])
    expect(prerequisites_of(:ci)).to eq(%w[load_config db:test:purge:ci])

    # `sec` has no schema load task here, which covers skipping a database without one.
    allow(Rails).to receive(:gem_version).and_return(Gem::Version.new('8.0.0'))
    expect { load rakefile }.not_to raise_error

    expect(prerequisites_of(:main)).to eq(['load_config'])
    expect(prerequisites_of(:ci)).to eq(['load_config'])
  end
end
