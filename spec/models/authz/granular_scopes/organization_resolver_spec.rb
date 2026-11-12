# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::GranularScopes::OrganizationResolver, feature_category: :permissions do
  let_it_be(:default_organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: other_organization) }
  let_it_be(:other_group) { create(:group, organization: other_organization) }
  let_it_be(:project) { create(:project, namespace: other_group) }
  let_it_be(:default_organization_group) { create(:group, organization: default_organization) }

  def scope_for(namespace = nil, access: :selected_memberships)
    Authz::GranularScope.new(namespace: namespace, access: access, permissions: %w[read_job])
  end

  describe '#organization' do
    subject(:organization) { described_class.new(scopes, default: default_organization).organization }

    context 'when no scope has a namespace' do
      let(:scopes) { [scope_for(access: :user), scope_for(access: :all_memberships)] }

      it { is_expected.to eq(default_organization) }
    end

    context 'when the scopes have namespaces in one organization' do
      let(:scopes) { [scope_for(group), scope_for(project.project_namespace), scope_for(access: :user)] }

      it { is_expected.to eq(other_organization) }
    end

    context 'when the scopes have namespaces in the default organization' do
      let(:scopes) { [scope_for(default_organization_group)] }

      it 'returns the default organization without loading it' do
        recorder = ActiveRecord::QueryRecorder.new { organization }

        expect(organization).to be(default_organization)
        expect(recorder.count).to eq(0)
      end
    end

    context 'when the scopes have namespaces in different organizations' do
      let(:scopes) { [scope_for(group), scope_for(default_organization_group)] }

      it 'raises an error' do
        expect { organization }.to raise_error(
          described_class::MultipleOrganizationsError, 'Granular scopes must belong to a single organization'
        )
      end
    end
  end
end
