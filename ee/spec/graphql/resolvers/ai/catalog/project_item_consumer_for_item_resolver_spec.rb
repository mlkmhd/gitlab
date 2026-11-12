# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::Catalog::ProjectItemConsumerForItemResolver, feature_category: :ai_catalog_curation do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: user) }
  let_it_be(:owning_project) { create(:project) }
  let_it_be(:item) { create(:ai_catalog_item, :public, project: owning_project) }

  let(:args) { { id: global_id_of(item) } }

  subject(:result) { sync(resolve(described_class, obj: project, args: args, ctx: { current_user: user })) }

  it 'has expected arguments' do
    expect(described_class).to have_graphql_arguments(:id, :include_inherited)
  end

  context 'when a consumer exists for the project and item' do
    let_it_be(:consumer) do
      create(:ai_catalog_item_consumer, project: project, item: item, enabled: true)
    end

    it { is_expected.to eq(consumer) }
  end

  context 'when no consumer exists for the project and item' do
    it { is_expected.to be_nil }
  end

  context 'when a consumer exists in a different project' do
    let_it_be(:other_project) { create(:project) }

    before do
      create(:ai_catalog_item_consumer, project: other_project, item: item, enabled: true)
    end

    it { is_expected.to be_nil }
  end

  context 'when the project is in a top-level group' do
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:project) { create(:project, maintainers: user, group: subgroup) }
    let_it_be(:item) { create(:ai_catalog_flow, :public) }

    context 'when the top-level group has an inheritance consumer for the item' do
      let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group, item: item) }

      it { is_expected.to eq(inheritance_consumer) }

      context 'when include_inherited is false' do
        let(:args) { super().merge(include_inherited: false) }

        it { is_expected.to be_nil }
      end

      context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it { is_expected.to be_nil }
      end

      context 'when the project also has its own consumer for the item' do
        let_it_be(:project_consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }

        it { is_expected.to eq(project_consumer) }
      end
    end

    context 'when a different top-level group has an inheritance consumer for the item' do
      before do
        create(:ai_catalog_item_consumer, :inheritance, group: create(:group), item: item)
      end

      it { is_expected.to be_nil }
    end

    context 'when the top-level group has a direct consumer for the item' do
      before do
        create(:ai_catalog_item_consumer, group: group, item: item)
      end

      it { is_expected.to be_nil }
    end
  end
end
