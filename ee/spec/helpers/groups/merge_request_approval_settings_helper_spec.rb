# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::MergeRequestApprovalSettingsHelper, feature_category: :code_review_workflow do
  let_it_be(:group) { build_stubbed(:group) }
  let_it_be(:user) { build_stubbed(:user) }

  describe '#can_update_merge_request_approval_settings?' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(user, :update_merge_request_approval_setting, group).and_return(allowed)
    end

    context 'when the user can update the approval settings' do
      let(:allowed) { true }

      it 'returns true' do
        expect(helper.can_update_merge_request_approval_settings?(user, group)).to be(true)
      end
    end

    context 'when the user cannot update the approval settings' do
      let(:allowed) { false }

      it 'returns false' do
        expect(helper.can_update_merge_request_approval_settings?(user, group)).to be(false)
      end
    end
  end
end
