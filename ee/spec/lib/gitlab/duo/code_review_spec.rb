# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview, feature_category: :dap_code_review do
  let_it_be(:group) { build_stubbed(:group) }
  let_it_be(:project) { build_stubbed(:project, group: group) }
  let_it_be(:merge_request) { build_stubbed(:merge_request, source_project: project) }
  let_it_be(:user) { build_stubbed(:user, developer_of: project) }

  describe '.enabled?' do
    let(:active_mode) { instance_double(Gitlab::Duo::CodeReview::Modes::Base, enabled?: double) }

    shared_examples 'delegates to ModeResolver.enabled?' do
      it 'delegates to ModeResolver.enabled?' do
        stub_active_mode_with(active_mode)

        expect(active_mode).to receive(:enabled?)

        described_class.enabled?(user: user, container: container)
      end
    end

    context 'when container is a group' do
      let(:container) { group }

      include_examples 'delegates to ModeResolver.enabled?'
    end

    context 'when container is a project' do
      let(:container) { project }

      include_examples 'delegates to ModeResolver.enabled?'
    end
  end

  describe '.mode' do
    let(:active_mode) { instance_double(Gitlab::Duo::CodeReview::Modes::Base, mode: double) }

    shared_examples 'delegates to ModeResolver.mode' do
      it 'delegates to ModeResolver.mode' do
        stub_active_mode_with(active_mode)

        expect(active_mode).to receive(:mode)

        described_class.mode(user: user, container: container)
      end
    end

    context 'when container is a group' do
      let(:container) { group }

      include_examples 'delegates to ModeResolver.mode'
    end

    context 'when container is a project' do
      let(:container) { project }

      include_examples 'delegates to ModeResolver.mode'
    end
  end

  describe '.dap?' do
    subject(:dap) { described_class.dap?(user: user, container: project) }

    before do
      stub_active_mode_with(active_mode)
    end

    context 'when active mode is dap' do
      let(:active_mode) { instance_double(Gitlab::Duo::CodeReview::Modes::Dap, mode: :dap) }

      it { is_expected.to be(true) }
    end

    context 'when active mode is classic' do
      let(:active_mode) { instance_double(Gitlab::Duo::CodeReview::Modes::Classic, mode: :classic) }

      it { is_expected.to be(false) }
    end

    context 'when active mode is disabled' do
      let(:active_mode) { instance_double(Gitlab::Duo::CodeReview::Modes::Disabled, mode: :disabled) }

      it { is_expected.to be(false) }
    end
  end

  describe '.depth_for' do
    using RSpec::Parameterized::TableSyntax

    subject { described_class.depth_for(build(:duo_workflows_workflow, flow_metadata_json: flow_metadata_json)) }

    where(:flow_metadata_json, :depth) do
      { flow_id: 'code_review' }.to_json      | :standard
      { flow_id: 'deep_code_review' }.to_json | :deep
      { flow_id: 'developer' }.to_json        | nil
      '"deep_code_review"'                    | nil
      nil                                     | nil
    end

    with_them do
      it { is_expected.to eq(depth) }
    end
  end

  private

  def stub_active_mode_with(active_mode)
    allow(Gitlab::Duo::CodeReview::ModeResolver)
      .to receive(:new)
      .and_return(active_mode)
  end

  describe '.deep_available?' do
    subject(:available) { described_class.deep_available?(project: container) }

    let(:container) { project }

    before do
      stub_feature_flags(duo_code_review_deep_flow: group)
      allow(group).to receive(:duo_beta_flows_enabled?).and_return(true)
      allow(project).to receive(:duo_code_review_depth_allowed).and_return(true)
    end

    it { is_expected.to be(true) }

    context 'when the flag is disabled for the root group' do
      before do
        stub_feature_flags(duo_code_review_deep_flow: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when beta flows are disabled for the root group' do
      before do
        allow(group).to receive(:duo_beta_flows_enabled?).and_return(false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the project does not allow deep reviews' do
      before do
        allow(project).to receive(:duo_code_review_depth_allowed).and_return(false)
      end

      it { is_expected.to be(false) }
    end

    context 'when there is no project' do
      let(:container) { nil }

      it { is_expected.to be(false) }
    end
  end
end
