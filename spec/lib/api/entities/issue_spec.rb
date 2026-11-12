# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::API::Entities::Issue, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let(:issue) { build_stubbed(:issue, project: project) }
  let(:current_user) { build_stubbed(:user) }
  let(:options) { { current_user: current_user }.merge(option_addons) }
  let(:option_addons) { {} }
  let(:entity) { described_class.new(issue, options) }

  subject(:json) { entity.as_json }

  describe '#service_desk_reply_to', feature_category: :service_desk do
    # Setting to true (default) doesn't play nice with stubs
    let(:option_addons) { { include_subscribed: false } }
    let(:issue) { build_stubbed(:issue, project: project, service_desk_reply_to: email) }
    let(:email) { 'creator@example.com' }

    subject { json[:service_desk_reply_to] }

    context 'as developer' do
      before do
        stub_member_access_level(issue.project, developer: current_user)
      end

      it { is_expected.to eq(email) }
    end

    context 'as guest' do
      before do
        stub_member_access_level(issue.project, guest: current_user)
      end

      it { is_expected.to eq('cr*****@e*****.c**') }
    end

    context 'without email' do
      let(:email) { nil }

      specify { expect(json).to have_key(:service_desk_reply_to) }
      it { is_expected.to be_nil }
    end
  end

  describe 'closed_as_duplicate_of link' do
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:duplicate_of) { create(:issue, project: public_project) }
    let(:issue) { create(:issue, project: project, duplicated_to: duplicate_of) }

    subject(:link) { json.dig(:_links, :closed_as_duplicate_of) }

    context 'when the user can read the issue it duplicates' do
      it { is_expected.to end_with("/projects/#{public_project.id}/issues/#{duplicate_of.iid}") }
    end

    context 'when there is no current user' do
      let(:current_user) { nil }

      it 'does not link the issue even though it is public' do
        expect(link).to be_nil
      end
    end
  end
end
