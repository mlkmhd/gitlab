# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User with pull_container_image custom role', feature_category: :container_registry do
  let_it_be_with_reload(:project) { create(:project, :private, :in_group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:role) { create(:member_role, :guest, namespace: project.group, pull_container_image: true) }

  let(:scope) { "repository:#{project.full_path}:pull" }
  let(:granted_actions) do
    JWT.decode(json_response['token'], nil, false).first['access'].flat_map { |access| access['actions'] }
  end

  before do
    stub_licensed_features(custom_roles: true)
    stub_container_registry_config(enabled: true, key: 'spec/fixtures/x509_certificate_pk.key')
  end

  def request_token(login, password)
    get '/jwt/auth',
      params: { service: 'container_registry', scope: scope },
      headers: { authorization: ActionController::HttpAuthentication::Basic.encode_credentials(login, password) }
  end

  context 'when the user is a guest with the custom role' do
    let(:personal_access_token) { create(:personal_access_token, user: user, scopes: %w[read_registry]) }

    before_all do
      create(:group_member, :guest, member_role: role, user: user, source: project.group)
    end

    it 'grants pull' do
      request_token(user.username, personal_access_token.token)

      expect(granted_actions).to contain_exactly('pull')
    end

    context 'when the container registry is only visible to project members' do
      before do
        project.project_feature.update!(container_registry_access_level: ProjectFeature::PRIVATE)
      end

      it 'grants pull' do
        request_token(user.username, personal_access_token.token)

        expect(granted_actions).to contain_exactly('pull')
      end
    end

    context 'when pulling from a CI job in another project' do
      let_it_be(:ci_project) { create(:project, :private, developers: user) }
      let_it_be(:build) { create(:ci_build, :running, project: ci_project, user: user) }

      before_all do
        create(:ci_job_token_project_scope_link, source_project: project, target_project: ci_project,
          direction: :inbound)
      end

      it 'grants pull' do
        request_token('gitlab-ci-token', build.token)

        expect(granted_actions).to contain_exactly('pull')
      end
    end
  end

  context 'when the user is a guest without the custom role' do
    let_it_be(:guest) { create(:user, guest_of: project) }
    let(:personal_access_token) { create(:personal_access_token, user: guest, scopes: %w[read_registry]) }

    it 'denies pull' do
      request_token(guest.username, personal_access_token.token)

      expect(granted_actions).to be_empty
    end
  end
end
