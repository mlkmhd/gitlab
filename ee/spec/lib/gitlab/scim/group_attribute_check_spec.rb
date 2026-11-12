# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Scim::GroupAttributeCheck, feature_category: :system_access do
  let_it_be(:scim_group_uid) { SecureRandom.uuid }

  subject(:check) { described_class.new(scim_group_uid: scim_group_uid) }

  describe '#error_for' do
    context 'with a SAML group link for the SCIM group' do
      let_it_be(:saml_group_link) do
        create(:saml_group_link, saml_group_name: 'engineering', scim_group_uid: scim_group_uid)
      end

      it 'returns nothing for the same name' do
        expect(check.error_for(display_names: ['engineering'], external_ids: [])).to be_nil
      end

      it 'returns nothing when no name is sent' do
        expect(check.error_for(display_names: [nil], external_ids: [nil])).to be_nil
      end

      it 'returns a mutability error for a different name' do
        result = check.error_for(display_names: ['platform'], external_ids: [])

        expect(result).to be_error
        expect(result.message).to eq(
          "Renaming a group isn't supported. Create a SAML group link named \"platform\", " \
            "provision the group again from your identity provider, and then remove the old link."
        )
        expect(result.payload[:scim_type]).to eq('mutability')
      end

      it 'treats a change of case as a rename' do
        expect(check.error_for(display_names: ['Engineering'], external_ids: [])).to be_error
      end

      it 'logs the rejection' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          message: 'Rejected a SCIM group update that changes an immutable attribute',
          scim_group_uid: scim_group_uid,
          Labkit::Fields::ERROR_MESSAGE =>
            "Renaming a group isn't supported. Create a SAML group link named \"platform\", " \
            "provision the group again from your identity provider, and then remove the old link."
        )

        check.error_for(display_names: ['platform'], external_ids: [])
      end
    end

    context 'without a SAML group link for the SCIM group' do
      it 'returns nothing for any name' do
        expect(check.error_for(display_names: ['platform'], external_ids: [])).to be_nil
      end
    end

    it 'returns nothing for an externalId that matches the SCIM group ID' do
      expect(check.error_for(display_names: [], external_ids: [scim_group_uid])).to be_nil
    end

    it 'returns a mutability error for a different externalId' do
      result = check.error_for(display_names: [], external_ids: ['another-id'])

      expect(result).to be_error
      expect(result.message).to eq("Changing the externalId of a group isn't supported")
      expect(result.payload[:scim_type]).to eq('mutability')
    end
  end
end
