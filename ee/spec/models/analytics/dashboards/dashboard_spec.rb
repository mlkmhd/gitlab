# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Dashboards::Dashboard, feature_category: :product_analytics do
  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be_with_refind(:project) do
    create(:project, :repository,
      project_setting: build(:project_setting),
      group: group)
  end

  let_it_be(:config_project) do
    create(:project, :with_product_analytics_dashboard, group: group)
  end

  before_all do
    group.add_developer(user)
  end

  before do
    # Duo and SDLC trends is hidden once Explore is reachable, and these expectations are
    # written against the legacy dashboards app.
    stub_feature_flags(explore_analytics_dashboards: false)

    allow(Ability).to receive(:allowed?)
      .with(user, :read_enterprise_ai_analytics, anything)
      .and_return(true)
    allow(Ability).to receive(:allowed?)
      .with(user, :read_dora4_analytics, anything)
      .and_return(true)
    allow(Ability).to receive(:allowed?)
      .with(user, :read_project_merge_request_analytics, anything)
      .and_return(true)

    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    stub_licensed_features(
      product_analytics: true,
      project_level_analytics_dashboard: true,
      group_level_analytics_dashboard: true,
      dora4_analytics: true,
      project_merge_request_analytics: true
    )
  end

  shared_examples 'returns the value streams dashboard' do
    it 'returns the value streams dashboard' do
      expect(dashboard).to be_a(described_class)
      expect(dashboard.title).to eq('Value Streams Dashboard')
      expect(dashboard.slug).to eq('value_streams_dashboard')
      expect(dashboard.description).to eq('Track key DevSecOps metrics throughout the development lifecycle.')
      expect(dashboard.filters).to be_nil
      expect(dashboard.schema_version).to eq('2')
    end
  end

  shared_examples 'returns the DORA Metrics dashboard' do
    it 'returns the value streams dashboard' do
      expect(dashboard).to be_a(described_class)
      expect(dashboard.title).to eq('DORA metrics analytics')
      expect(dashboard.slug).to eq('dora_metrics')
      expect(dashboard.description).to eq(
        "View current DORA metric performance and historical trends to analyze DevOps efficiency over time."
      )
    end

    it 'returns the correct panels' do
      expect(dashboard.panels.size).to eq(8)
    end
  end

  shared_examples 'returns the Merge request analytics dashboard' do
    it 'returns the merge request analytics dashboard' do
      expect(dashboard).to be_a(described_class)
      expect(dashboard.title).to eq('Merge request analytics')
      expect(dashboard.slug).to eq('merge_request_analytics')
      expect(dashboard.description).to eq(
        "Get insights into your merge request lifecycle and view trends over time."
      )
    end

    it 'returns the correct panels' do
      expect(dashboard.panels.size).to eq(3)
    end
  end

  shared_examples 'loads custom dashboard within limits' do
    it 'successfully loads custom dashboard' do
      expect(dashboards.map(&:title)).to include('Dashboard Example 1')
      custom_dashboard = dashboards.find { |d| d.slug == 'dashboard_example_1' }
      expect(custom_dashboard).to be_a(described_class)
      expect(custom_dashboard.user_defined).to be true
    end
  end

  describe '#errors' do
    let(:dashboard) do
      described_class.new(
        container: group,
        config: Gitlab::Config::Loader::Yaml.new(config_yaml).load_raw!,
        slug: 'test2',
        user_defined: true,
        config_project: project
      )
    end

    context 'when yaml is valid' do
      let(:config_yaml) do
        File.open(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')).read
      end

      it 'returns nil' do
        expect(dashboard.errors).to be_nil
      end
    end

    context 'when yaml is faulty' do
      let(:config_yaml) do
        <<-YAML
---
title: not good yaml
description: with missing properties
        YAML
      end

      it 'returns schema errors' do
        expect(dashboard.errors).to eq(["root is missing required keys: panels"])
      end

      it 'still exposes the descriptive fields' do
        expect(dashboard.title).to eq('not good yaml')
        expect(dashboard.description).to eq('with missing properties')
      end

      it 'does not parse the rest of the definition' do
        expect(Analytics::Dashboards::Panel).not_to receive(:from_data)

        expect(dashboard.grid_height).to be_nil
        expect(dashboard.filters).to be_nil
        expect(dashboard.panels).to be_nil
      end
    end

    context 'when yaml has a malformed structure' do
      let(:config_yaml) do
        <<-YAML
---
title: malformed structure
version: '2'
panels: not a list
        YAML
      end

      it 'returns schema errors instead of raising' do
        expect(dashboard.errors).to eq(["property '/panels' is not of type: array"])
      end
    end

    context 'when yaml exceeds file size limits' do
      let(:config_yaml) do
        oversized = "title: Oversized\nversion: '2'\npanels: []\ndata: #{'x' * (2.megabytes + 1)}"
        oversized
      end

      it 'raises DataTooLargeError when loading oversized dashboard' do
        expect do
          dashboard
        end.to raise_error(Gitlab::Config::Loader::Yaml::DataTooLargeError)
      end
    end

    context 'when yaml exceeds file depth limits' do
      let(:config_yaml) do
        deeply_nested = "title: Deep\nversion: '2'\npanels: []\n"
        deeply_nested += "config:\n"
        101.times do |i|
          deeply_nested += ("  " * (i + 1)) + "l#{i}:\n"
        end
        deeply_nested += "#{'  ' * 102}value: test\n"
        deeply_nested
      end

      it 'raises DataTooLargeError when loading deeply nested dashboard' do
        expect do
          dashboard
        end.to raise_error(Gitlab::Config::Loader::Yaml::DataTooLargeError)
      end
    end
  end

  describe '.for' do
    context 'when resource is a project' do
      let(:resource_parent) { project }

      subject(:dashboards) { described_class.for(container: resource_parent, user: user) }

      before do
        allow(Gitlab::CurrentSettings).to receive(:product_analytics_enabled?).and_return(true)
      end

      it 'returns a collection of builtin dashboards' do
        expect(dashboards.map(&:title)).to match_array(
          [
            'Value Streams Dashboard',
            'DORA metrics analytics',
            'GitLab Duo and SDLC trends',
            'Merge request analytics'
          ]
        )
      end

      context 'when the user can reach Explore analytics dashboards' do
        before do
          stub_feature_flags(explore_analytics_dashboards: true)
        end

        it 'excludes Duo and SDLC trends from the list' do
          expect(dashboards.map(&:title)).not_to include('GitLab Duo and SDLC trends')
        end
      end

      context 'when configuration project is set' do
        before do
          resource_parent.update!(analytics_dashboards_configuration_project: config_project)
        end

        it 'returns custom and builtin dashboards' do
          expect(dashboards).to be_a(Array)
          expect(dashboards.size).to eq(5)
          expect(dashboards.last).to be_a(described_class)
          expect(dashboards.last.title).to eq('Dashboard Example 1')
          expect(dashboards.last.slug).to eq('dashboard_example_1')
          expect(dashboards.last.description)
            .to eq('North Star Metrics across all departments for the last 3 quarters.')
          expect(dashboards.last.schema_version).to eq('2')
          expect(dashboards.last.filters).to eq({ "projects" => { "enabled" => true },
            "dateRange" => { "enabled" => true }, "excludeAnonymousUsers" => { "enabled" => true },
                                               "filteredSearch" => { "enabled" => true, "options" =>
                                                 [{ "token" => "label", "maxSuggestions" => 20 }] } })
          expect(dashboards.last.errors).to be_nil
        end

        context 'when custom dashboard file is within size and depth limits' do
          it_behaves_like 'loads custom dashboard within limits'
        end
      end

      context 'when the configuration cache is enabled', :use_clean_rails_memory_store_caching do
        let(:cached_config_project) { create(:project, :with_product_analytics_dashboard, group: group) }
        let(:repository) { cached_config_project.repository }

        before do
          allow(resource_parent).to receive(:analytics_dashboards_configuration_project)
            .and_return(cached_config_project)
        end

        it 'serves the second request without reading the repository', :request_store do
          first = described_class.for(container: resource_parent, user: user)

          expect(repository).not_to receive(:tree)
          expect(repository).not_to receive(:blob_data_at)

          second = nil
          expect { second = described_class.for(container: resource_parent, user: user) }
            .not_to change { Gitlab::GitalyClient.get_request_count }
          expect(second.map(&:slug)).to eq(first.map(&:slug))
        end

        it 'makes one Gitaly request on a warm cache for a freshly loaded project', :request_store do
          described_class.for(container: resource_parent, user: user)
          allow(resource_parent).to receive(:analytics_dashboards_configuration_project)
            .and_return(Project.find(cached_config_project.id))

          expect { described_class.for(container: resource_parent, user: user) }
            .to change { Gitlab::GitalyClient.get_request_count }.by(1)
        end

        it 'reads the repository again after a new commit to the configuration project' do
          expect(described_class.for(container: resource_parent, user: user).map(&:slug))
            .not_to include('dashboard_example_2')

          repository.create_file(
            cached_config_project.creator,
            '.gitlab/analytics/dashboards/dashboard_example_2/dashboard_example_2.yaml',
            File.read(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')),
            message: 'test',
            branch_name: 'master'
          )
          allow(resource_parent).to receive(:analytics_dashboards_configuration_project)
            .and_return(Project.find(cached_config_project.id))

          expect(described_class.for(container: resource_parent, user: user).map(&:slug))
            .to include('dashboard_example_1', 'dashboard_example_2')
        end

        context 'when the feature flag is disabled' do
          before do
            stub_feature_flags(customizable_dashboards_config_cache: false)
          end

          it 'reads the repository on every request' do
            expect(repository).to receive(:tree).twice.and_call_original
            expect(repository).to receive(:blob_data_at).twice.and_call_original

            2.times { described_class.for(container: resource_parent, user: user) }
          end
        end
      end

      context 'when the dashboard file does not exist in the directory' do
        before do
          # Invalid dashboard - should not be included
          project.repository.create_file(
            project.creator,
            '.gitlab/analytics/dashboards/dashboard_example_1/project_dashboard_example_wrongly_named.yaml',
            File.open(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')).read,
            message: 'test',
            branch_name: 'master'
          )

          # Valid dashboard - should be included
          project.repository.create_file(
            project.creator,
            '.gitlab/analytics/dashboards/dashboard_example_2/dashboard_example_2.yaml',
            File.open(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')).read,
            message: 'test',
            branch_name: 'master'
          )
        end

        it 'excludes the dashboard from the list' do
          expected_dashboards =
            ["Value Streams Dashboard", "GitLab Duo and SDLC trends",
              "DORA metrics analytics", "Merge request analytics", "Dashboard Example 1"]

          expect(dashboards.map(&:title)).to eq(expected_dashboards)
        end
      end
    end

    context 'when resource is a group' do
      let_it_be(:resource_parent) { group }

      subject(:dashboards) { described_class.for(container: resource_parent, user: user) }

      it 'returns a collection of builtin dashboards' do
        expect(dashboards.map(&:title)).to match_array(['Value Streams Dashboard', 'DORA metrics analytics',
          'GitLab Duo and SDLC trends', 'Contributions Dashboard'])
      end

      context 'when the user can reach Explore analytics dashboards' do
        before do
          stub_feature_flags(explore_analytics_dashboards: true)
        end

        it 'excludes Duo and SDLC trends from the list' do
          expect(dashboards.map(&:title)).not_to include('GitLab Duo and SDLC trends')
        end
      end

      context 'when configuration project is set' do
        before do
          resource_parent.update!(analytics_dashboards_configuration_project: config_project)
        end

        it 'returns custom and builtin dashboards' do
          expect(dashboards).to be_a(Array)
          expect(dashboards.map(&:title)).to match_array(
            ['Value Streams Dashboard', 'GitLab Duo and SDLC trends', 'DORA metrics analytics',
              'Dashboard Example 1', 'Contributions Dashboard']
          )
        end

        context 'when custom dashboard file is within size and depth limits' do
          it_behaves_like 'loads custom dashboard within limits'
        end
      end

      context 'when the dashboard file does not exist in the directory' do
        before do
          project.repository.create_file(
            project.creator,
            '.gitlab/analytics/dashboards/dashboard_example_1/group_dashboard_example_wrongly_named.yaml',
            File.open(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')).read,
            message: 'test',
            branch_name: 'master'
          )
        end

        it 'excludes the dashboard from the list' do
          expect(dashboards.map(&:title)).to match_array(
            ['Value Streams Dashboard', 'GitLab Duo and SDLC trends', 'DORA metrics analytics',
              'Dashboard Example 1', 'Contributions Dashboard']
          )
        end
      end

      context 'when DORA metrics are not licensed' do
        before do
          allow(Ability).to receive(:allowed?)
                        .with(user, :read_enterprise_ai_analytics, anything)
                        .and_return(true)
          allow(Ability).to receive(:allowed?)
                        .with(user, :read_dora4_analytics, anything)
                        .and_return(false)
        end

        it 'excludes the dashboard from the list' do
          expect(dashboards.map(&:title)).not_to include('DORA metrics analytics')
        end
      end
    end

    context 'when resource is not a project or a group' do
      it 'raises error' do
        invalid_object = double

        error_message =
          "A group or project must be provided. Given object is RSpec::Mocks::Double type"
        expect { described_class.for(container: invalid_object, user: user) }
          .to raise_error(ArgumentError, error_message)
      end
    end
  end

  describe '.find_by_slug' do
    let_it_be(:container) { create(:group) }
    let_it_be(:multi_dashboard_config_project) do
      create(:project, :with_product_analytics_dashboard, group: container).tap do |config_project|
        example = File.read(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml'))

        { 'dashboard_example_2' => 'Dashboard Example 2', 'value_streams_dashboard' => 'Custom VSD' }
          .each do |folder, title|
          config_project.repository.create_file(
            config_project.creator,
            ".gitlab/analytics/dashboards/#{folder}/#{folder}.yaml",
            example.sub('title: Dashboard Example 1', "title: #{title}"),
            message: 'test',
            branch_name: 'master'
          )
        end
      end
    end

    let(:repository) { multi_dashboard_config_project.repository }
    let(:slug) { 'dashboard_example_2' }

    subject(:dashboard) { described_class.find_by_slug(container: container, user: user, slug: slug) }

    before do
      allow(container).to receive(:analytics_dashboards_configuration_project)
        .and_return(multi_dashboard_config_project)
    end

    it 'returns the same dashboard as filtering the full list' do
      listed = described_class.for(container: container, user: user).find { |d| d.slug == slug }

      expect(listed.title).to eq('Dashboard Example 2')
      expect(dashboard).to have_attributes(
        slug: slug,
        title: 'Dashboard Example 2',
        user_defined: true,
        config_project: multi_dashboard_config_project,
        container: container
      )
      expect(dashboard.panels.map(&:title)).to eq(listed.panels.map(&:title))
    end

    it 'reads only the requested dashboard folder' do
      expect(repository).not_to receive(:tree)
      expect(repository).to receive(:blob_data_at)
        .with(repository.root_ref_sha, ".gitlab/analytics/dashboards/#{slug}/#{slug}.yaml")
        .once.and_call_original

      expect(dashboard.slug).to eq(slug)
    end

    it 'makes fewer Gitaly requests than listing every dashboard', :request_store do
      described_class.for(container: container, user: user)

      list_requests = gitaly_requests { described_class.for(container: container, user: user) }
      slug_requests = gitaly_requests { described_class.find_by_slug(container: container, user: user, slug: slug) }

      expect(slug_requests).to be < list_requests
    end

    context 'when the slug is a builtin dashboard that a custom folder also uses' do
      let(:slug) { 'value_streams_dashboard' }

      it 'returns the builtin one, like the full list does, without reading the repository' do
        listed = described_class.for(container: container, user: user).find { |d| d.slug == slug }
        expect(listed.user_defined).to be(false)

        expect(repository).not_to receive(:blob_data_at)

        expect(dashboard).to have_attributes(title: 'Value Streams Dashboard', user_defined: false)
      end
    end

    context 'when no dashboard has the slug' do
      let(:slug) { 'not_a_real_dashboard' }

      it { is_expected.to be_nil }
    end

    context 'when the container has no configuration project' do
      before do
        allow(container).to receive(:analytics_dashboards_configuration_project).and_return(nil)
      end

      it { is_expected.to be_nil }

      context 'when the slug is a builtin dashboard' do
        let(:slug) { 'value_streams_dashboard' }

        it 'still returns the builtin dashboard' do
          expect(dashboard).to have_attributes(title: 'Value Streams Dashboard', user_defined: false)
        end
      end
    end

    context 'when the slug cannot be a dashboard folder' do
      where(slug: [
        'visualizations', 'dashboard_example_2/dashboard_example_2', 'dashboard_example_2\\dashboard_example_2',
        '..', '.', ".\n", "dashboard_example_2\0", 'a' * 256, ''
      ])

      with_them do
        it 'returns nil without reading the repository' do
          expect(repository).not_to receive(:blob_data_at)

          expect(dashboard).to be_nil
        end
      end
    end

    context 'when the configuration cache is enabled', :use_clean_rails_memory_store_caching do
      it 'serves the second lookup without reading the repository', :request_store do
        described_class.find_by_slug(container: container, user: user, slug: slug)

        expect(repository).not_to receive(:blob_data_at)
        expect { expect(dashboard.slug).to eq(slug) }.not_to change { Gitlab::GitalyClient.get_request_count }
      end

      it 'serves a lookup from the files a list request cached' do
        described_class.for(container: container, user: user)

        expect(repository).not_to receive(:blob_data_at)
        expect(dashboard.slug).to eq(slug)
      end

      context 'when no dashboard has the slug' do
        let(:slug) { 'not_a_real_dashboard' }

        it 'does not cache the miss' do
          expect(repository).to receive(:blob_data_at).twice.and_call_original

          2.times { expect(described_class.find_by_slug(container: container, user: user, slug: slug)).to be_nil }
        end
      end
    end

    context 'when the configuration project has an empty repository' do
      let_it_be(:empty_config_project) { create(:project, group: container) }

      before do
        allow(container).to receive(:analytics_dashboards_configuration_project).and_return(empty_config_project)
      end

      it { is_expected.to be_nil }
    end

    context 'when resource is not a project or a group' do
      it 'raises error' do
        expect { described_class.find_by_slug(container: double, user: user, slug: slug) }
          .to raise_error(ArgumentError, /A group or project must be provided/)
      end
    end

    def gitaly_requests
      before = Gitlab::GitalyClient.get_request_count
      yield
      Gitlab::GitalyClient.get_request_count - before
    end
  end

  describe '#panels' do
    before do
      project.update!(analytics_dashboards_configuration_project: config_project, namespace: config_project.namespace)
    end

    subject(:panels) { described_class.for(container: project, user: user).last.panels }

    it { is_expected.to be_a(Array) }

    it 'is expected to contain two panels' do
      expect(panels.size).to eq(2)
    end

    it 'is expected to contain a panel with the correct title' do
      expect(panels.first.title).to eq('Overall Conversion Rate')
    end

    it 'is expected to contain a panel with the correct grid attributes' do
      expect(panels.first.grid_attributes).to eq({ 'xPos' => 1, 'yPos' => 4, 'width' => 12, 'height' => 2 })
    end

    it 'is expected to contain a panel with the correct query overrides' do
      expect(panels.first.query_overrides).to eq({
        'timeDimensions' => [{
          'dimension' => 'Stories.time',
          'dateRange' => %w[2016-01-01 2016-02-30],
          'granularity' => 'month'
        }]
      })
    end

    it 'is expected to contain a panel with the correct tooltip' do
      expect(panels.first.tooltip).to eq({
        'description' => 'Percentage of visitors who complete a desired action. %{linkStart}Learn more%{linkEnd}.',
        'descriptionLink' => 'https://gitlab.com'
      })
    end

    it 'is expected to contain a panel with the correct views' do
      expect(panels.first.views).to match([
        { text: 'Line', visualization: have_attributes(slug: 'line_chart', type: 'LineChart') },
        { text: 'Bar', visualization: have_attributes(slug: 'bar_chart', type: 'BarChart') }
      ])
    end
  end

  describe '#==' do
    let(:dashboard_1) { described_class.for(container: project, user: user).first }
    let(:dashboard_2) do
      config_yaml =
        File.open(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')).read
      config_yaml = Gitlab::Config::Loader::Yaml.new(config_yaml).load_raw!

      described_class.new(
        container: project,
        config: config_yaml,
        slug: 'test2',
        user_defined: true,
        config_project: project
      )
    end

    subject { dashboard_1 == dashboard_2 }

    it { is_expected.to be false }
  end

  describe '.value_stream_dashboard' do
    context 'for groups' do
      let(:dashboard) { described_class.value_stream_dashboard(group, config_project) }

      it_behaves_like 'returns the value streams dashboard'

      it 'returns the correct panels' do
        expect(dashboard.panels.size).to eq(12)
        expect(dashboard.panels.map { |panel| panel.visualization.slug }).to eq(
          %w[
            namespace_metadata
            groups_count
            projects_count
            users_count
            issues_count
            merge_requests_count
            pipelines_count
            vsd_lifecycle_metrics_table
            vsd_dora_metrics_table
            vsd_security_metrics_table
            dora_performers_score
            dora_projects_comparison
          ]
        )
      end
    end

    context 'for projects' do
      let(:dashboard) { described_class.value_stream_dashboard(project, config_project) }

      it_behaves_like 'returns the value streams dashboard'

      it 'returns the correct panels' do
        expect(dashboard.panels.size).to eq(7)
        expect(dashboard.panels.map { |panel| panel.visualization.slug }).to eq(
          %w[
            namespace_metadata
            issues_count
            merge_requests_count
            pipelines_count
            vsd_lifecycle_metrics_table
            vsd_dora_metrics_table
            vsd_security_metrics_table
          ]
        )
      end
    end
  end

  describe '.dora_metrics_dashboard' do
    context 'for groups' do
      let(:dashboard) { described_class.dora_metrics_dashboard(group, config_project) }

      it_behaves_like 'returns the DORA Metrics dashboard'
    end

    context 'for projects' do
      let(:dashboard) { described_class.dora_metrics_dashboard(project, config_project) }

      it_behaves_like 'returns the DORA Metrics dashboard'
    end
  end

  describe '.merge_request_analytics_dashboard' do
    context 'for groups' do
      subject { described_class.merge_request_analytics_dashboard(group, config_project, user) }

      it { is_expected.to be_nil }
    end

    context 'for projects' do
      let(:dashboard) { described_class.merge_request_analytics_dashboard(project, config_project, user) }

      it_behaves_like 'returns the Merge request analytics dashboard'
    end
  end

  describe '.ai_impact_dashboard' do
    context 'for groups' do
      subject(:dashboard) { described_class.ai_impact_dashboard(group, config_project, user) }

      it 'returns the dashboard' do
        expect(dashboard.title).to eq('GitLab Duo and SDLC trends')
        expect(dashboard.slug).to eq('duo_and_sdlc_trends')
        expect(dashboard.schema_version).to eq('2')
        expect(dashboard.filters).to be_nil
      end

      context 'when clickhouse is not enabled' do
        before do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        end

        it { is_expected.to be_nil }
      end

      context 'when the user can reach Explore analytics dashboards' do
        before do
          stub_feature_flags(explore_analytics_dashboards: true)
        end

        it { is_expected.to be_nil }
      end
    end

    context 'for projects' do
      subject(:dashboard) { described_class.ai_impact_dashboard(project, config_project, user) }

      it 'returns the dashboard' do
        expect(dashboard.title).to eq('GitLab Duo and SDLC trends')
        expect(dashboard.slug).to eq('duo_and_sdlc_trends')
        expect(dashboard.schema_version).to eq('2')
        expect(dashboard.filters).to be_nil
      end

      context 'when clickhouse is not enabled' do
        before do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        end

        it { is_expected.to be_nil }
      end

      context 'when the user can reach Explore analytics dashboards' do
        before do
          stub_feature_flags(explore_analytics_dashboards: true)
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe '.contributions_dashboard' do
    context 'for groups' do
      subject(:dashboard) { described_class.contributions_dashboard(group, config_project) }

      it 'returns the dashboard' do
        expect(dashboard.title).to eq('Contributions Dashboard')
        expect(dashboard.slug).to eq('contributions_dashboard')
        expect(dashboard.schema_version).to eq('2')
        expect(dashboard.filters).to eq({ "dateRange" => { "enabled" => true, "numberOfDaysLimit" => 90,
                                                           "options" => %w[7d 30d 90d custom] } })
      end

      context 'when contributions_analytics_dashboard feature is disabled' do
        before do
          stub_feature_flags(contributions_analytics_dashboard: false)
        end

        it { is_expected.to be_nil }
      end
    end

    context 'for projects' do
      subject { described_class.contributions_dashboard(project, config_project) }

      it { is_expected.to be_nil }
    end
  end

  describe '.load_yaml_dashboard_config' do
    let(:file_path) { '.gitlab/analytics/dashboards' }

    context 'when invalid path is provided' do
      it 'raises exception for absolute path traversal attempt' do
        invalid_file_name = '/tmp/foo'

        error_message = "path #{invalid_file_name} is not allowed"
        expect { described_class.load_yaml_dashboard_config(invalid_file_name, file_path) }
          .to raise_error(StandardError, error_message)
      end

      it 'raises exception when path traversal is attempted' do
        error_message = "Invalid path"
        expect { described_class.load_yaml_dashboard_config('../foo', file_path) }
          .to raise_error(Gitlab::PathTraversal::PathTraversalAttackError, error_message)
      end
    end

    context 'for valid path' do
      subject(:dashboard_config) do
        described_class.load_yaml_dashboard_config('value_streams_dashboard',
          'ee/lib/gitlab/analytics/value_stream_dashboard/dashboards')
      end

      it 'loads the dashboard config' do
        expect(dashboard_config["title"]).to eq('Value Streams Dashboard')
      end
    end
  end
end
