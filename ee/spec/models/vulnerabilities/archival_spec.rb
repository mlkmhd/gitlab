# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::Archival, feature_category: :vulnerability_management do
  describe '.enabled_for?' do
    let_it_be(:root_ancestor) { create(:group) }
    let_it_be(:group) { create(:group, parent: root_ancestor) }
    let_it_be(:project) { create(:project, group: group) }

    subject { described_class.enabled_for?(project) }

    it { is_expected.to be_truthy }

    context 'when the feature is disabled' do
      before do
        stub_feature_flags(vulnerability_archival: false)
      end

      it { is_expected.to be_falsey }
    end

    context 'when the feature is enabled only for the direct parent' do
      before do
        stub_feature_flags(vulnerability_archival: group)
      end

      it { is_expected.to be_truthy }
    end

    context 'when the feature is enabled only for the root ancestor' do
      before do
        stub_feature_flags(vulnerability_archival: root_ancestor)
      end

      it { is_expected.to be_truthy }
    end
  end
end
