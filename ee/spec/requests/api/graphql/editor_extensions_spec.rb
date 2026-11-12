# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Editor Extensions GraphQL integration on Dedicated', :clean_gitlab_redis_cache, :dedicated, feature_category: :editor_extensions do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let(:query) { graphql_query_for('project', { fullPath: project.full_path }, 'id') }

  describe 'language server client restrictions' do
    before do
      stub_feature_flags(enforce_language_server_version: false)
    end

    context 'with allowed clients' do
      before do
        allow(Gitlab::CurrentSettings.current_application_settings).to receive_messages(
          enable_language_server_restrictions: true,
          minimum_language_server_version: '1.0.0')
      end

      it 'is supported' do
        post_graphql(query, current_user: user, headers: {
          'User-Agent' => 'gitlab-language-server 1.0.0',
          'X-GitLab-Language-Server-Version' => '1.0.0'
        })

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_data['project']['id']).to eq(project.to_gid.to_s)
      end
    end

    shared_examples 'unallowed clients' do
      using RSpec::Parameterized::TableSyntax

      where(:client_version, :user_agent) do
        '0.1.0' | 'code-completions-language-server-experiment (gl-visual-studio-extension:1.0.0.0; arch:X64;)'
        '0.1.0' | 'gitlab-language-server 1.0.0'
        '0.1.0' | nil
        nil     | 'code-completions-language-server-experiment (gl-visual-studio-extension:1.0.0.0; arch:X64;)'
        nil     | 'gitlab-language-server 0.1.0'
      end

      with_them do
        it 'is unauthorized' do
          post_graphql(query, current_user: user, headers: {
            'User-Agent' => user_agent,
            'X-GitLab-Language-Server-Version' => client_version
          })

          expect(response).to have_gitlab_http_status(:unauthorized)
          expect(graphql_errors).to contain_exactly(
            hash_including('message' => a_string_including('Requests from Editor Extension clients are restricted'))
          )
        end
      end
    end

    context 'with unallowed clients on dedicated' do
      before do
        allow(Gitlab::CurrentSettings.current_application_settings).to receive_messages(
          enable_language_server_restrictions: true,
          minimum_language_server_version: '1.0.0')
      end

      it_behaves_like 'unallowed clients'
    end
  end
end
