# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GitLab Duo and SDLC trends system dashboard', feature_category: :duo_agent_platform do
  let(:config) { Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('duo_and_sdlc_trends').config }

  describe 'the GitLab Duo Agent Platform flow usage panel' do
    let(:panel) { config['panels'].find { |p| p['title'] == 'GitLab Duo Agent Platform flow usage' } }
    let(:data) { panel.dig('visualization', 'data') }

    it 'is a GLQL panel that takes the date range through its date field' do
      expect(panel.dig('visualization', 'type')).to eq('Glql')
      expect(data.dig('query', 'dateField')).to eq('created')
      expect(data.dig('query', 'glql')).not_to include('%{')
    end

    it 'reads the session metrics of each flow' do
      glql = YAML.safe_load(data.dig('query', 'glql'))

      expect(glql).to include(
        'mode' => 'analytics',
        'query' => 'type = AgentPlatformSession',
        'dimensions' => 'flowType as "Flow"'
      )
      expect(glql['metrics']).to include('totalCount', 'durationQuantile(0.5)', 'usersCount', 'completionRate')
    end
  end
end
