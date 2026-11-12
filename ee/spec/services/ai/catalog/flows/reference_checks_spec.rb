# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ReferenceChecks, feature_category: :ai_catalog_curation do
  let_it_be(:group) { create(:group) }
  let_it_be(:other_group) { create(:group) }
  let_it_be(:flow_project) { create(:project, group: group) }
  let_it_be(:sibling_project) { create(:project, group: group) }
  let_it_be(:outside_project) { create(:project, group: other_group) }
  let_it_be(:user) { create(:user, developer_of: flow_project) }

  let(:flow_visibility) { :private }
  let(:checks) { described_class.new(user: user, flow_project: flow_project, flow_visibility: flow_visibility) }

  before do
    allow(Ability).to receive(:allowed?).and_call_original
  end

  def agent(visibility, project)
    create(:ai_catalog_agent, visibility, project: project).tap do |item|
      allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, item).and_return(true)
    end
  end

  describe '.refusal_message' do
    using RSpec::Parameterized::TableSyntax

    where(:code, :message) do
      :unknown_item    | "Agent '7' (version 1.2.0) was not found or you do not have access to it"
      :location        | "Agent 'Reviewer' is not visible to flows in this project"
      :visibility      | "Agent 'Reviewer' must be at least as visible as the flow that references it"
      :unknown_version | "Agent 'Reviewer' has no version 1.2.0"
    end

    with_them do
      it 'gives the sentence for the code' do
        expect(described_class.refusal_message(code, id: '7', version: '1.2.0', name: 'Reviewer')).to eq(message)
      end
    end

    it 'gives a refusal sentence for a code it does not know' do
      expect(described_class.refusal_message(:other, id: '7', version: '1.2.0', name: 'Reviewer'))
        .to eq("Agent '7' (version 1.2.0) cannot be used in this flow")
    end
  end

  describe '#refusal_code' do
    let(:item) { agent(:public, flow_project) }
    let(:version) { create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0') }

    it 'returns nil for a readable, permitted, released agent' do
      expect(checks.refusal_code(item, version)).to be_nil
    end

    describe 'unknown_item' do
      it 'is returned when the item is nil' do
        expect(checks.refusal_code(nil, version)).to eq(:unknown_item)
      end

      it 'is returned when the user cannot read the item' do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, item).and_return(false)

        expect(checks.refusal_code(item, version)).to eq(:unknown_item)
      end

      it 'is returned when the item is not an agent' do
        flow = create(:ai_catalog_flow, :public, project: flow_project)
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, flow).and_return(true)

        expect(checks.refusal_code(flow, version)).to eq(:unknown_item)
      end

      it 'is returned when the item is soft deleted' do
        item.soft_delete

        expect(checks.refusal_code(item, version)).to eq(:unknown_item)
      end
    end

    describe 'location' do
      it 'is returned for a private agent in another project' do
        expect(checks.refusal_code(agent(:private, sibling_project), version)).to eq(:location)
      end

      it 'is returned for a restricted agent outside the root group' do
        expect(checks.refusal_code(agent(:restricted, outside_project), version)).to eq(:location)
      end

      it 'is returned for an agent blocked by a namespace restriction' do
        allow(item).to receive(:blocked_by_namespace_restriction?).with(flow_project).and_return(true)

        expect(checks.refusal_code(item, version)).to eq(:location)
      end

      it 'is returned for a restricted agent whose project is gone' do
        restricted = agent(:restricted, sibling_project)
        restricted.project = nil

        expect(checks.refusal_code(restricted, version)).to eq(:location)
      end

      it 'is not returned for a public agent from any project' do
        expect(checks.refusal_code(agent(:public, outside_project), version)).to be_nil
      end

      it 'is not returned for a restricted agent from the same root group' do
        expect(checks.refusal_code(agent(:restricted, sibling_project), version)).to be_nil
      end

      it 'is not returned for a private agent from the flow project' do
        expect(checks.refusal_code(agent(:private, flow_project), version)).to be_nil
      end
    end

    describe 'visibility' do
      let(:flow_visibility) { :public }

      it 'is returned for an agent less visible than the flow' do
        expect(checks.refusal_code(agent(:restricted, flow_project), version)).to eq(:visibility)
      end

      it 'comes after location, so a private agent in another project is a location refusal' do
        expect(checks.refusal_code(agent(:private, sibling_project), version)).to eq(:location)
      end
    end

    describe 'unknown_version' do
      it 'is returned when the version is nil' do
        expect(checks.refusal_code(item, nil)).to eq(:unknown_version)
      end

      it 'is returned when the version is not released' do
        draft = create(:ai_catalog_agent_version, item: item, version: '1.1.0')

        expect(checks.refusal_code(item, draft)).to eq(:unknown_version)
      end
    end
  end
end
