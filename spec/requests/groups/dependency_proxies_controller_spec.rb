# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::DependencyProxiesController, feature_category: :virtual_registry do
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:dependency_proxy_group_setting) { create(:dependency_proxy_group_setting, group: group) }
  let_it_be(:user) { create(:user, owner_of: group) }

  before do
    sign_in(user)
  end

  describe 'GET #show' do
    subject(:show_dependency_proxy) { get group_dependency_proxy_path(group) }

    before do
      stub_config(dependency_proxy: { enabled: config_enabled })
    end

    context 'with global config enabled' do
      let(:config_enabled) { true }

      context 'with the setting enabled' do
        it 'returns 200 and renders the view' do
          show_dependency_proxy

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to have_css('#js-dependency-proxy')
        end
      end

      context 'with the setting disabled' do
        before do
          dependency_proxy_group_setting.update!(enabled: false)
        end

        it_behaves_like 'returning response status', :not_found
      end
    end

    context 'with global config disabled' do
      let(:config_enabled) { false }

      it_behaves_like 'returning response status', :not_found
    end
  end
end
