# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Database::PreventCrossJoins::Analyzer, feature_category: :database do
  let(:main_and_ci_sql) { 'SELECT 1 FROM p_ci_builds JOIN projects ON projects.id = p_ci_builds.project_id' }

  describe '.enabled?' do
    it { expect(described_class.enabled?).to be(true) }
  end

  describe '.analyze' do
    it 'allows queries on main tables only' do
      expect { analyze('SELECT 1 FROM issues JOIN projects ON projects.id = issues.project_id') }.not_to raise_error
    end

    it 'allows queries on CI tables only' do
      expect { analyze('SELECT 1 FROM p_ci_builds JOIN p_ci_pipelines ON true') }.not_to raise_error
    end

    it 'raises for queries joining main and CI tables' do
      expect { analyze(main_and_ci_sql) }.to raise_error(
        Database::PreventCrossJoins::CrossJoinAcrossUnsupportedTablesError,
        /Unsupported cross-join across 'p_ci_builds, projects'/
      )
    end

    it 'allows cross-joins inside allow_cross_joins_across_databases' do
      Gitlab::Database.allow_cross_joins_across_databases(url: 'https://gitlab.com/gitlab-org/gitlab/-/issues/1') do
        expect { analyze(main_and_ci_sql) }.not_to raise_error
      end
    end

    it 'allows cross-joins annotated as allowed' do
      annotation = Database::PreventCrossJoins::ALLOW_ANNOTATE_KEY

      expect { analyze("#{main_and_ci_sql} /* #{annotation} */") }.not_to raise_error
    end

    it 'allows statements that disable triggers across tables' do
      sql = 'ALTER TABLE projects DISABLE TRIGGER ALL; ALTER TABLE p_ci_builds DISABLE TRIGGER ALL'

      expect { analyze(sql) }.not_to raise_error
    end

    it 'ignores SQL that cannot be parsed' do
      expect { analyze('SELECT SELECT FROM SELECT') }.not_to raise_error
    end
  end

  def analyze(sql)
    parsed = Gitlab::Database::QueryAnalyzer::Parsed.new(sql, ApplicationRecord.connection, 'load', false)

    described_class.analyze(parsed)
  end
end
