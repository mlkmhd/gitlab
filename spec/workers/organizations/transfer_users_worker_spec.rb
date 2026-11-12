# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::TransferUsersWorker, :eager_load, feature_category: :organization do
  let_it_be(:source_organization) { create(:organization) }
  let_it_be_with_refind(:target_organization) { create(:organization) }
  let_it_be_with_refind(:user) { create(:user, :with_namespace, organization: source_organization) }

  let(:job_args) { { 'user_ids' => [user.id], 'organization_id' => target_organization.id } }

  it_behaves_like 'an idempotent worker' do
    subject(:worker) { described_class.new }
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(job_args) }

    it 'transfers the users and their personal namespaces to the organization', :aggregate_failures do
      perform

      expect(user.reload.organization_id).to eq(target_organization.id)
      expect(Namespaces::UserNamespace.for_owner(user.id).first.organization_id).to eq(target_organization.id)
    end

    context 'when the organization does not exist' do
      let(:job_args) { { 'user_ids' => [user.id], 'organization_id' => non_existing_record_id } }

      it 'does not run the transfer and logs the error', :aggregate_failures do
        expect(Organizations::Transfer::UsersService).not_to receive(:new)
        expect(Sidekiq.logger).to receive(:error).with(
          hash_including(
            'message' => 'User transfer to organization failed: organization not found',
            Labkit::Fields::GL_ORGANIZATION_ID => non_existing_record_id,
            'user_ids' => [user.id]
          )
        )

        expect { perform }.not_to change { user.reload.organization_id }
      end
    end

    context 'when the transfer is invalid' do
      let_it_be(:other_user) { create(:user, organization: create(:organization)) }

      let(:job_args) do
        { 'user_ids' => [user.id, other_user.id], 'organization_id' => target_organization.id }
      end

      it 'does not transfer the users' do
        expect { perform }.not_to change { user.reload.organization_id }
      end
    end
  end
end
