# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo workflow token scopes outside Rails', feature_category: :duo_agent_platform do
  let(:scope) { Ai::DuoWorkflows::WorkflowTokenScope.for(42).first }

  it 'cannot be registered on an OAuth application' do
    expect(build(:oauth_application, scopes: 'api')).to be_valid
    expect(build(:oauth_application, scopes: "api #{scope}")).not_to be_valid
  end

  it 'cannot be requested in an OAuth grant' do
    app_scopes = Doorkeeper::OAuth::Scopes.from_string('api ai_workflows mcp user:*')

    expect(
      Doorkeeper::OAuth::Helpers::ScopeChecker.valid?(
        scope_str: scope, server_scopes: Doorkeeper.config.scopes, app_scopes: app_scopes
      )
    ).to be(false)
  end

  it 'cannot be added to a personal access token' do
    expect(build(:personal_access_token, scopes: ['api'])).to be_valid
    expect(build(:personal_access_token, scopes: ['api', scope])).not_to be_valid
  end
end
