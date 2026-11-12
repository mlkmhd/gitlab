# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Availability::Instance, feature_category: :dap_code_review do
  using RSpec::Parameterized::TableSyntax

  let(:application_setting) { build(:application_setting, duo_features_enabled: true) }

  describe '#available?' do
    subject(:available) { described_class.new(application_setting).available? }

    it { is_expected.to be(false) }

    context 'with an active instance Duo Enterprise add-on' do
      before do
        create(:gitlab_subscription_add_on_purchase, :self_managed, :duo_enterprise)
      end

      it { is_expected.to be(true) }

      context 'when duo_foundational_flows_enabled is false' do
        before do
          application_setting.duo_foundational_flows_enabled = false
        end

        it { is_expected.to be(true) }
      end

      context 'when duo_features_enabled is false' do
        before do
          application_setting.duo_features_enabled = false
        end

        it { is_expected.to be(false) }
      end
    end

    context 'with an expired instance Duo Enterprise add-on' do
      before do
        create(:gitlab_subscription_add_on_purchase, :self_managed, :expired, :duo_enterprise)
      end

      it { is_expected.to be(false) }
    end

    context 'with an active instance Duo Pro or Duo Core add-on' do
      where(:add_on_trait) { [:duo_pro, :duo_core] }

      with_them do
        before do
          create(:gitlab_subscription_add_on_purchase, :self_managed, add_on_trait)
        end

        it { is_expected.to be(false) }
      end
    end
  end

  describe '#decisions_settings_available?' do
    subject(:decisions_available) { availability.decisions_settings_available? }

    let(:availability) do
      described_class.new(application_setting).tap { |a| allow(a).to receive(:available?).and_return(available) }
    end

    let(:available) { true }

    it 'does not read the Duo settings when the feature flag is disabled' do
      stub_feature_flags(duo_code_review_decisions: false)

      expect(application_setting).not_to receive(:duo_features_enabled)
      expect(decisions_available).to be(false)
    end

    where(:flag_enabled, :duo_features_enabled, :foundational_flows_enabled, :beta_enabled, :available, :expected) do
      true  | true  | true  | true  | true  | true
      false | true  | true  | true  | true  | false
      true  | false | true  | true  | true  | false
      true  | true  | false | true  | true  | false
      true  | true  | true  | false | true  | false
      true  | true  | true  | true  | false | false
    end

    with_them do
      before do
        stub_feature_flags(duo_code_review_decisions: flag_enabled)
        application_setting.assign_attributes(
          duo_features_enabled: duo_features_enabled,
          duo_foundational_flows_enabled: foundational_flows_enabled,
          instance_level_ai_beta_features_enabled: beta_enabled
        )
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '#automatic_review_available?' do
    let_it_be(:duo_enterprise_add_on) { create(:gitlab_subscription_add_on, :duo_enterprise) }
    let_it_be(:duo_core_add_on) { create(:gitlab_subscription_add_on, :duo_core) }
    let_it_be(:duo_pro_add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
    let(:application_setting) { build(:application_setting) }

    subject(:available) { described_class.new(application_setting).automatic_review_available? }

    before do
      application_setting.duo_features_enabled = true
    end

    context 'when duo_features_enabled is false' do
      before do
        application_setting.duo_features_enabled = false
      end

      it { is_expected.to be_falsey }
    end

    context 'when duo_features_enabled is true' do
      context 'without any duo add-on' do
        it { is_expected.to be_falsey }
      end

      context 'with active duo_enterprise add-on' do
        before do
          create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: duo_enterprise_add_on)
        end

        it 'returns true' do
          expect(available).to be_truthy
        end
      end

      context 'with expired duo_enterprise add-on' do
        before do
          create(:gitlab_subscription_add_on_purchase, :expired, :self_managed, add_on: duo_enterprise_add_on)
        end

        it 'returns false' do
          expect(available).to be_falsey
        end
      end

      context 'with duo_core or duo_pro add-ons' do
        where(:add_on_type, :add_on) do
          [
            ['duo_core', ref(:duo_core_add_on)],
            ['duo_pro',  ref(:duo_pro_add_on)]
          ]
        end

        with_them do
          before do
            create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: add_on)
          end

          it "returns false for #{params[:add_on_type]} (not yet supported at application setting level)" do
            expect(available).to be_falsey
          end
        end
      end

      context 'when duo_foundational_flows_enabled is set' do
        before do
          application_setting.duo_foundational_flows_enabled = true
          create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: duo_core_add_on)
        end

        it 'does not affect duo_core availability (setting not exposed yet)' do
          expect(available).to be_falsey
        end
      end
    end
  end

  describe '#depth_settings_available?' do
    subject(:available) { described_class.new(application_setting).depth_settings_available? }

    where(:flag_enabled, :duo_features_enabled, :foundational_flows_enabled, :beta_enabled, :expected) do
      true  | true  | true  | true  | true
      false | true  | true  | true  | false
      true  | false | true  | true  | false
      true  | true  | false | true  | false
      true  | true  | true  | false | false
    end

    with_them do
      before do
        stub_feature_flags(duo_code_review_deep_flow: flag_enabled)
        application_setting.assign_attributes(
          duo_features_enabled: duo_features_enabled,
          duo_foundational_flows_enabled: foundational_flows_enabled,
          instance_level_ai_beta_features_enabled: beta_enabled
        )
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '#default_depth' do
    let(:availability) { described_class.new(application_setting) }

    subject(:default_depth) { availability.default_depth }

    where(:available, :allowed, :selected_depth, :expected_depth) do
      true  | true  | 'deep'     | 'deep'
      true  | true  | 'standard' | 'standard'
      true  | false | 'deep'     | 'standard'
      false | true  | 'deep'     | 'standard'
    end

    with_them do
      before do
        allow(availability).to receive(:depth_settings_available?).and_return(available)
        allow(application_setting).to receive_messages(
          duo_code_review_depth_allowed: allowed,
          duo_code_review_default_depth: selected_depth
        )
      end

      it { is_expected.to eq(expected_depth) }
    end
  end
end
