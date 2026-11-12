# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Dashboards::ConfigCache, :use_clean_rails_memory_store_caching,
  feature_category: :product_analytics do
  let_it_be(:config_project) { create(:project, :with_product_analytics_dashboard) }

  let(:repository) { config_project.repository }
  let(:line_chart_path) { '.gitlab/analytics/dashboards/visualizations/line_chart.yaml' }
  let(:bar_chart_path) { '.gitlab/analytics/dashboards/visualizations/bar_chart.yaml' }
  let(:missing_path) { '.gitlab/analytics/dashboards/missing/missing.yaml' }
  let(:reads) { [] }

  def fetch(project = config_project, value = %w[a b])
    described_class.fetch(project, :dashboard_slugs) do
      reads << value
      value
    end
  end

  describe '.fetch' do
    it 'runs the block once and serves the second call from the cache' do
      expect(fetch).to eq(%w[a b])
      expect(fetch).to eq(%w[a b])
      expect(reads.size).to eq(1)
    end

    it 'keys the entry on the project id and head commit sha with a five minute TTL' do
      expect(Rails.cache).to receive(:fetch)
        .with(['analytics_dashboards_config', config_project.id, repository.root_ref_sha, :dashboard_slugs],
          { expires_in: 5.minutes, skip_nil: true })
        .and_call_original

      fetch
    end

    it 'runs the block again after a new commit to the configuration project' do
      bumped_project = create(:project, :repository)
      fetch(bumped_project)

      bumped_project.repository.create_file(
        bumped_project.creator, 'bump.txt', 'bump', message: 'bump', branch_name: 'master'
      )
      fetch(Project.find(bumped_project.id))

      expect(reads.size).to eq(2)
    end

    it 'does not cache nil' do
      2.times { fetch(config_project, nil) }

      expect(reads.size).to eq(2)
    end

    context 'when the configuration project has an empty repository' do
      let_it_be(:config_project) { create(:project) }

      it 'runs the block every time without touching the cache' do
        expect(Rails.cache).not_to receive(:fetch)

        2.times { fetch }

        expect(reads.size).to eq(2)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(customizable_dashboards_config_cache: false)
      end

      it 'runs the block every time without touching the cache' do
        expect(Rails.cache).not_to receive(:fetch)

        2.times { fetch }

        expect(reads.size).to eq(2)
      end
    end
  end

  describe '.blob_data_at' do
    it 'reads the blob once and serves the second call from the cache' do
      expect(repository).to receive(:blob_data_at).with(repository.root_ref_sha, line_chart_path).once.and_call_original

      2.times do
        expect(described_class.blob_data_at(config_project, line_chart_path)).to include('type: LineChart')
      end
    end

    it 'does not cache a missing blob' do
      expect(repository).to receive(:blob_data_at).with(repository.root_ref_sha, missing_path).twice.and_call_original

      2.times do
        expect(described_class.blob_data_at(config_project, missing_path)).to be_nil
      end
    end

    context 'when the configuration project has an empty repository' do
      let_it_be(:config_project) { create(:project) }

      it 'returns nil without reading the repository' do
        expect(repository).not_to receive(:blob_data_at)

        expect(described_class.blob_data_at(config_project, line_chart_path)).to be_nil
      end
    end
  end

  describe '.blobs_data_at' do
    let(:paths) { [line_chart_path, missing_path, bar_chart_path] }

    subject(:blobs) { described_class.blobs_data_at(config_project, paths) }

    it 'returns the blobs keyed by path in the requested order' do
      expect(blobs.keys).to eq(paths)
      expect(blobs[line_chart_path]).to include('type: LineChart')
      expect(blobs[bar_chart_path]).to include('type: BarChart')
      expect(blobs[missing_path]).to be_nil
    end

    it 'reads each present blob once across calls' do
      expect(repository).to receive(:blob_data_at).with(repository.root_ref_sha, line_chart_path).once.and_call_original
      expect(repository).to receive(:blob_data_at).with(repository.root_ref_sha, bar_chart_path).once.and_call_original
      expect(repository).to receive(:blob_data_at).with(repository.root_ref_sha, missing_path).twice.and_call_original

      2.times { described_class.blobs_data_at(config_project, paths) }
    end

    it 'returns an empty hash for no paths' do
      expect(described_class.blobs_data_at(config_project, [])).to eq({})
    end

    it 'reads the blob again once the TTL has passed' do
      expect(repository).to receive(:blob_data_at)
        .with(repository.root_ref_sha, line_chart_path).twice.and_call_original

      described_class.blobs_data_at(config_project, [line_chart_path])

      travel_to(described_class::EXPIRES_IN.from_now + 1.second) do
        described_class.blobs_data_at(config_project, [line_chart_path])
      end
    end

    it 'reads a path given twice once and keys the result by path' do
      expect(repository).to receive(:blob_data_at).with(repository.root_ref_sha, line_chart_path).once.and_call_original

      blobs = described_class.blobs_data_at(config_project, [line_chart_path, line_chart_path])

      expect(blobs.keys).to eq([line_chart_path])
      expect(blobs[line_chart_path]).to include('type: LineChart')
    end

    context 'when a file is larger than the YAML size limit' do
      before do
        stub_application_setting(max_yaml_size_bytes: 16)
      end

      it 'returns the file on every call without writing it to the cache' do
        expect(repository).to receive(:blob_data_at)
          .with(repository.root_ref_sha, line_chart_path).twice.and_call_original
        expect(Rails.cache).not_to receive(:write_multi)

        2.times do
          expect(described_class.blobs_data_at(config_project, [line_chart_path])[line_chart_path])
            .to include('type: LineChart')
        end
      end
    end

    it 'makes one Gitaly request on a warm cache for a freshly loaded project', :request_store do
      present_paths = [line_chart_path, bar_chart_path]
      described_class.blobs_data_at(Project.find(config_project.id), present_paths)
      refreshed = Project.find(config_project.id)

      expect { described_class.blobs_data_at(refreshed, present_paths) }
        .to change { Gitlab::GitalyClient.get_request_count }.by(1)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(customizable_dashboards_config_cache: false)
      end

      it 'reads every blob on every call' do
        expect(Rails.cache).not_to receive(:read_multi)
        expect(repository).to receive(:blob_data_at).exactly(6).times.and_call_original

        2.times { described_class.blobs_data_at(config_project, paths) }
      end
    end
  end
end
