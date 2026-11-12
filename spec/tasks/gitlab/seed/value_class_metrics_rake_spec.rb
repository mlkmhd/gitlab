# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../tooling/quality/value_class_coverage'

RSpec.describe 'gitlab:seed:value_class_metrics', :silence_stdout, feature_category: :tooling do
  let(:coverage) { instance_double(Quality::ValueClassCoverage) }
  let(:metrics_file) { Tempfile.new('metrics') }
  let(:report_file) { Tempfile.new('coverage') }

  before do
    Rake.application.rake_require 'tasks/gitlab/seed'
    stub_env('METRICS_FILE', metrics_file.path)
    stub_env('FIXTURE_COVERAGE_FILE', report_file.path)
    allow(Gitlab::Database::Dictionary).to receive(:entries)
      .and_return(Gitlab::Database::Dictionary.new([Gitlab::Database::Dictionary.entry('projects')]))
  end

  after do
    metrics_file.close!
    report_file.close!
  end

  def finding(table:, column:, seeded: true, missing: %w[glyphs], covered: %w[ascii])
    Quality::ValueClassCoverage::Finding.new(
      table: table, column: column, type: :string, seeded: seeded,
      covered: covered, missing: missing
    )
  end

  def stub_findings(findings)
    allow(Quality::ValueClassCoverage).to receive(:new).and_return(coverage)
    allow(coverage).to receive(:findings).and_return(findings)
  end

  it 'writes a gauge for every total', :aggregate_failures do
    stub_findings([
      finding(table: 'projects', column: 'name', missing: []),
      finding(table: 'projects', column: 'path'),
      finding(table: 'users', column: 'name', seeded: false, missing: %w[null])
    ])

    expect(File.size(metrics_file.path)).to eq(0)

    run_rake_task('gitlab:seed:value_class_metrics')

    expect(File.read(metrics_file.path)).to eq(<<~METRICS)
      # TYPE dev_fixtures_tables_checked gauge
      dev_fixtures_tables_checked 2
      # TYPE dev_fixtures_tables_empty gauge
      dev_fixtures_tables_empty 1
      # TYPE dev_fixtures_columns_checked gauge
      dev_fixtures_columns_checked 2
      # TYPE dev_fixtures_columns_with_gaps gauge
      dev_fixtures_columns_with_gaps 1
    METRICS
  end

  it 'prints the totals so the job log carries them' do
    stub_findings([finding(table: 'projects', column: 'path')])

    expect { run_rake_task('gitlab:seed:value_class_metrics') }
      .to output(/dev_fixtures_columns_with_gaps 1/).to_stdout
  end

  it 'leaves the columns of an empty table out of the column totals' do
    stub_findings([finding(table: 'users', column: 'name', seeded: false, missing: %w[null])])

    run_rake_task('gitlab:seed:value_class_metrics')

    expect(File.read(metrics_file.path)).to include(
      "dev_fixtures_tables_empty 1", "dev_fixtures_columns_checked 0", "dev_fixtures_columns_with_gaps 0"
    )
  end

  it 'says how many tables it could not reach when a schema has no connection', :aggregate_failures do
    allow(Gitlab::Database).to receive(:schemas_to_base_models).and_return({})

    expect { run_rake_task('gitlab:seed:value_class_metrics') }
      .to output(/no connection for gitlab_main_org, cannot check 1 table\(s\)/).to_stdout

    expect(File.read(metrics_file.path)).to include("dev_fixtures_tables_checked 0")
  end

  it 'reports what every checked column covers and misses, so two runs can be compared' do
    stub_findings([
      finding(table: 'projects', column: 'name', missing: []),
      finding(table: 'projects', column: 'path', missing: %w[empty glyphs]),
      finding(table: 'users', column: 'name', seeded: false, covered: [], missing: %w[null])
    ])

    run_rake_task('gitlab:seed:value_class_metrics')

    expect(File.read(report_file.path)).to eq(<<~REPORT)
      projects.name string seeded ascii -
      projects.path string seeded ascii empty,glyphs
      users.name string empty - null
    REPORT
  end

  # The job exists to seed and to run the coverage check, so a measurement that cannot run must not
  # take either of them down with it.
  it 'keeps the job green and publishes no total when the sweep raises', :aggregate_failures do
    allow(Quality::ValueClassCoverage).to receive(:new)
      .and_raise(ActiveRecord::StatementInvalid, 'canceling statement due to statement timeout')

    expect { run_rake_task('gitlab:seed:value_class_metrics') }
      .to output(/metrics skipped: ActiveRecord::StatementInvalid/).to_stdout

    expect(File.size(metrics_file.path)).to eq(0)
    expect(File.size(report_file.path)).to eq(0)
  end

  it 'keeps a report it already wrote when writing the next one fails' do
    stub_findings([finding(table: 'projects', column: 'path')])
    allow(File).to receive(:write).and_call_original
    allow(File).to receive(:write).with(report_file.path, /projects/).and_raise(Errno::ENOSPC)

    run_rake_task('gitlab:seed:value_class_metrics')

    expect(File.read(metrics_file.path)).to include('dev_fixtures_columns_with_gaps 1')
  end

  it 'refuses to scan the tables of a real install', :aggregate_failures do
    allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

    expect { run_rake_task('gitlab:seed:value_class_metrics') }
      .to output(/only runs in development and test/).to_stdout

    expect(File.size(metrics_file.path)).to eq(0)
  end
end
