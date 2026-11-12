# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ScimOauthAccessToken, feature_category: :system_access do
  describe "Associations" do
    it { is_expected.to belong_to(:organization) }
  end

  describe 'validations' do
    it 'requires organization_id on create' do
      token = described_class.new(organization_id: nil)

      expect(token).not_to be_valid
      expect(token.errors[:organization_id]).to include("can't be blank")
    end

    it 'is valid when organization_id is set' do
      organization = create(:organization)
      token = described_class.new(organization: organization)

      expect(token).to be_valid
      expect(token.errors[:organization_id]).to be_empty
    end
  end

  describe '#token' do
    shared_examples 'has a prefix' do
      it 'starts with prefix' do
        scim_token = build(:scim_oauth_access_token, organization: create(:organization), token_encrypted: nil)
        scim_token.save!

        expect(scim_token.token).to start_with expected_prefix
      end
    end

    it 'generates a prefixed token on creation' do
      scim_token = described_class.create!(organization: create(:organization))

      expect(scim_token.token).to match(/^glsoat-[\w-]{20}$/)
    end

    it_behaves_like 'has a prefix' do
      let(:expected_prefix) { described_class::TOKEN_PREFIX }
    end

    context 'with instance prefix configured' do
      let(:instance_prefix) { 'instanceprefix' }

      before do
        stub_application_setting(instance_token_prefix: instance_prefix)
      end

      it_behaves_like 'has a prefix' do
        let(:expected_prefix) { "#{instance_prefix}-#{described_class::TOKEN_PREFIX}" }
      end

      context 'with feature flag custom_prefix_for_all_token_types disabled' do
        before do
          stub_feature_flags(custom_prefix_for_all_token_types: false)
        end

        it_behaves_like 'has a prefix' do
          let(:expected_prefix) { described_class::TOKEN_PREFIX }
        end
      end
    end
  end
end
