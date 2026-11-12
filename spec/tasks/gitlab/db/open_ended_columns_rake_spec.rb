# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe 'gitlab:db:open_ended_columns namespace rake tasks', :silence_stdout, feature_category: :database do
  before(:all) do
    Rake.application.rake_require 'tasks/gitlab/db/open_ended_columns'
  end

  describe 'generate_allowlist' do
    let(:tmp_root) { Pathname.new(Dir.mktmpdir) }
    let(:allowlist_path) { tmp_root.join('spec/support/database/open-ended-columns-allowlist.yml') }
    let(:identifiers) { %w[users.bio projects.description description_versions.description] }

    before do
      allowlist_path.dirname.mkpath

      allow(Rails).to receive(:root).and_return(tmp_root)
      allow(Gitlab::Database::OpenEndedColumns).to receive(:unbounded_identifiers).and_return(identifiers)
    end

    after do
      FileUtils.rm_rf(tmp_root)
    end

    subject(:run_rake) { run_rake_task('gitlab:db:open_ended_columns:generate_allowlist') }

    it 'writes the unbounded columns into the allowlist' do
      run_rake

      expect(YAML.safe_load_file(allowlist_path)).to eq(identifiers)
    end

    it 'includes the header comment block', :aggregate_failures do
      run_rake

      contents = File.read(allowlist_path)
      expect(contents).to include('# Columns of open-ended (unbounded-width) types')
      expect(contents).to include('bundle exec rake gitlab:db:open_ended_columns:generate_allowlist')
    end

    it 'reports how many columns were written' do
      expect { run_rake }
        .to output(%r{Wrote 3 columns to spec/support/database/open-ended-columns-allowlist\.yml\.}).to_stdout
    end

    context 'when there are no unbounded columns' do
      let(:identifiers) { [] }

      it 'writes an empty allowlist' do
        run_rake

        expect(YAML.safe_load_file(allowlist_path)).to eq([])
      end
    end
  end
end
