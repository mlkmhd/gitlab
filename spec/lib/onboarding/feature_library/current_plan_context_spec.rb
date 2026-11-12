# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibrary::CurrentPlanContext, feature_category: :onboarding do
  subject(:plan_context) { described_class.new(resource: build_stubbed(:group)) }

  it 'describes a Free self-managed viewer' do
    expect(plan_context.to_h).to include(deployment: :self_managed, current_plan: :free, base_plan: :free, trial: false)
  end

  it 'reports the CE edition', unless: Gitlab.ee? do
    expect(plan_context.edition).to eq(:ce)
  end

  it 'offers both Explore pages' do
    expect(plan_context.tier_pages).to eq(%i[premium ultimate])
  end

  describe '#tier_pages' do
    using RSpec::Parameterized::TableSyntax

    where(:base_plan, :pages) do
      :free     | %i[premium ultimate]
      :premium  | %i[ultimate]
      :ultimate | %i[]
    end

    with_them do
      before do
        allow(plan_context).to receive(:base_plan).and_return(base_plan)
      end

      it { expect(plan_context.tier_pages).to eq(pages) }
    end
  end

  describe '#has_upgrade_pages?' do
    using RSpec::Parameterized::TableSyntax

    where(:plan) { described_class::PLANS }

    with_them do
      before do
        allow(plan_context).to receive_messages(current_plan: plan, trial?: false)
      end

      it 'is true only when there are pages to upgrade to' do
        expect(plan_context.has_upgrade_pages?).to eq(plan_context.tier_pages.any?)
      end
    end

    it 'is true during a trial, without looking up the plan the trial returns to' do
      allow(plan_context).to receive(:trial?).and_return(true)
      expect(plan_context).not_to receive(:base_plan)

      expect(plan_context.has_upgrade_pages?).to be(true)
    end
  end
end
