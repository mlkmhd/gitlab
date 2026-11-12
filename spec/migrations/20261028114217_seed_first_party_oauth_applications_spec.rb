# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe SeedFirstPartyOauthApplications, migration: :gitlab_main, feature_category: :system_access do
  let(:applications) { table(:oauth_applications) }
  let(:organizations) { table(:organizations) }
  let(:glab_uid) { '41d48f9422ebd655dd9cf2947d6979681dfaddc6d0c56f7628f6ada59559af1e' }

  let(:default_organization_exists) { true }

  before do
    organizations.create!(id: 1, name: 'Default', path: 'default') if default_organization_exists
  end

  describe '#up' do
    it 'creates the public, untrusted applications with the GitLab.com client IDs', :aggregate_failures do
      expect { migrate! }.to change { applications.count }.from(0).to(3)

      expect(applications.pluck(:uid)).to contain_exactly(
        glab_uid,
        '36f2a70cddeb5a0889d4fd8295c241b7e9848e89cf9e599d0eed2d8e5350fbf5',
        '732efe7d78ba62b01d2a95cd3b02f3ca2a00c7cec32c01e060c1b7664a9aa367')

      glab = applications.find_by!(uid: glab_uid)
      expect(glab).to have_attributes(
        scopes: 'openid profile read_user write_repository api', confidential: false, trusted: false,
        ropc_enabled: false, device_code_enabled: true, organization_id: 1,
        redirect_uri: 'http://localhost:7171/auth/redirect')
    end

    it 'limits the editor integrations to the api scope' do
      migrate!

      expect(applications.where.not(uid: glab_uid).pluck(:scopes)).to all(eq('api'))
    end

    it 'registers the redirect URI of every VS Code variant' do
      migrate!

      vscode = applications.find_by!(uid: '36f2a70cddeb5a0889d4fd8295c241b7e9848e89cf9e599d0eed2d8e5350fbf5')

      expect(vscode.redirect_uri.split("\n")).to eq(%w[
        vscode://gitlab.gitlab-workflow/authentication
        vscode-insiders://gitlab.gitlab-workflow/authentication
        vscodium://gitlab.gitlab-workflow/authentication
      ])
    end

    context 'when the default organization does not exist' do
      let(:default_organization_exists) { false }

      it 'creates nothing instead of violating the organization foreign key' do
        expect { migrate! }.not_to change { applications.count }
      end
    end

    it 'skips an application that already exists' do
      applications.create!(
        uid: glab_uid, name: 'Edited', secret: 'secret', redirect_uri: 'http://localhost:1/cb', scopes: 'read_user',
        organization_id: 1)

      expect { migrate! }.to change { applications.count }.from(1).to(3)

      expect(applications.find_by!(uid: glab_uid)).to have_attributes(name: 'Edited', scopes: 'read_user')
    end
  end
end
