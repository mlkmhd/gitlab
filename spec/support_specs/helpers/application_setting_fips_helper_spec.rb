# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ApplicationSettingFipsHelper, feature_category: :settings do
  describe '.ensure_key_restrictions!' do
    let(:setting) { ApplicationSetting.create_from_defaults }

    context 'with non-compliant FIPS settings' do
      before do
        setting.update_columns(
          rsa_key_restriction: 1024,
          dsa_key_restriction: 0,
          ecdsa_key_restriction: 521,
          ed25519_key_restriction: -1,
          ecdsa_sk_key_restriction: 0,
          ed25519_sk_key_restriction: 0
        )
      end

      context 'in non-FIPS mode', fips_mode: false do
        it 'keeps existing key restrictions', :aggregate_failures do
          expect { described_class.ensure_key_restrictions!(setting) }.not_to change { setting.valid? }
          expect(setting).to be_valid
          expect(setting.rsa_key_restriction).to eq(1024)
          expect(setting.dsa_key_restriction).to eq(0)
          expect(setting.ecdsa_key_restriction).to eq(521)
          expect(setting.ed25519_key_restriction).to eq(-1)
          expect(setting.ecdsa_sk_key_restriction).to eq(0)
          expect(setting.ed25519_sk_key_restriction).to eq(0)
        end
      end

      context 'in FIPS mode', :fips_mode do
        it 'updates key restrictions to meet FIPS compliance', :aggregate_failures do
          expect { described_class.ensure_key_restrictions!(setting) }.to change { setting.valid? }.from(false).to(true)
          expect(setting.rsa_key_restriction).to eq(3072)
          expect(setting.dsa_key_restriction).to eq(-1)
          expect(setting.ecdsa_key_restriction).to eq(521)
          expect(setting.ed25519_key_restriction).to eq(-1)
          expect(setting.ecdsa_sk_key_restriction).to eq(256)
          expect(setting.ed25519_sk_key_restriction).to eq(256)
        end
      end
    end
  end
end
