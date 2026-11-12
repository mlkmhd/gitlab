# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ai::ModelSelection::RestrictedNamespaceModels, feature_category: :"self-hosted_models" do
  describe '.namespace_eligible?' do
    let_it_be(:group) { create(:group) }

    context 'when the model is not gated' do
      it 'is eligible regardless of namespace' do
        expect(described_class.namespace_eligible?(group, 'claude_sonnet_5_5')).to be(true)
        expect(described_class.namespace_eligible?(nil, 'claude_sonnet_5_5')).to be(true)
      end
    end

    context 'when the model is gated' do
      where(model_ref: %w[claude_mythos_5_1 claude_mythos_5_2])

      with_them do
        context 'without a namespace' do
          it 'is eligible (this gate only applies to namespace-scoped selection)' do
            expect(described_class.namespace_eligible?(nil, model_ref)).to be(true)
          end
        end

        context 'with a namespace' do
          it 'is not eligible when the flag is disabled' do
            stub_feature_flags(mythos_restricted_namespace_model: false)

            expect(described_class.namespace_eligible?(group, model_ref)).to be(false)
          end

          it 'is eligible when the flag is enabled for the root ancestor' do
            stub_feature_flags(mythos_restricted_namespace_model: group)

            expect(described_class.namespace_eligible?(group, model_ref)).to be(true)
          end

          it 'is not eligible when the flag is enabled for a different group' do
            other_group = create(:group)
            stub_feature_flags(mythos_restricted_namespace_model: other_group)

            expect(described_class.namespace_eligible?(group, model_ref)).to be(false)
          end
        end
      end
    end
  end
end
