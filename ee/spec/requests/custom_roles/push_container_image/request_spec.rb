# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User with push_container_image custom role', feature_category: :container_registry do
  let_it_be_with_reload(:project) { create(:project, :private, :in_group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:role) do
    create(:member_role, :guest, namespace: project.group, push_container_image: true, pull_container_image: true)
  end

  let(:personal_access_token) do
    create(:personal_access_token, user: user, scopes: %w[read_registry write_registry])
  end

  let(:granted_actions) do
    JWT.decode(json_response['token'], nil, false).first['access'].flat_map { |access| access['actions'] }
  end

  before_all do
    create(:group_member, :guest, member_role: role, user: user, source: project.group)
  end

  before do
    stub_licensed_features(custom_roles: true)
    stub_container_registry_config(enabled: true, key: 'spec/fixtures/x509_certificate_pk.key')
  end

  subject(:request_token) do
    get '/jwt/auth',
      params: { service: 'container_registry', scope: "repository:#{project.full_path}:pull,push" },
      headers: {
        authorization: ActionController::HttpAuthentication::Basic.encode_credentials(
          user.username, personal_access_token.token
        )
      }
  end

  it 'grants pull and push' do
    request_token

    expect(granted_actions).to contain_exactly('pull', 'push')
  end

  context 'when the container registry is only visible to project members' do
    before do
      project.project_feature.update!(container_registry_access_level: ProjectFeature::PRIVATE)
    end

    it 'grants pull and push' do
      request_token

      expect(granted_actions).to contain_exactly('pull', 'push')
    end
  end
end
