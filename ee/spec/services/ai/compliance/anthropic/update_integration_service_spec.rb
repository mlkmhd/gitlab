# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::UpdateIntegrationService, feature_category: :ai_governance do
  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user, owner_of: group) }

  let(:integration) { create(:ai_compliance_anthropic_integration, namespace: group, enabled: true) }

  def service(**args)
    described_class.new(integration, current_user: user, **args)
  end

  describe '#verification_needed?' do
    using RSpec::Parameterized::TableSyntax

    where(:currently_enabled, :args, :needed) do
      true  | { api_key: 'new' } | true
      false | { api_key: 'new' } | true
      false | { enabled: true }  | true
      true  | { enabled: true }  | false
      true  | { enabled: false } | false
      false | { enabled: false } | false
    end

    with_them do
      before do
        integration.update!(enabled: currently_enabled)
      end

      it { expect(service(**args).verification_needed?).to be(needed) }
    end
  end

  describe '#execute' do
    context 'when turning off the integration fails to save' do
      before do
        allow(integration).to receive(:update) do |attributes|
          integration.assign_attributes(attributes)
          integration.errors.add(:base, 'cannot be saved')
          false
        end
      end

      it 'returns an error and restores the unsaved attributes', :aggregate_failures do
        response = service(enabled: false).execute

        expect(response).to be_error
        expect(response.reason).to eq(:invalid_integration)
        expect(response.payload[:integration]).to have_attributes(enabled: true, disabled_reason: nil)
        expect(integration).not_to be_changed
      end
    end
  end
end
