# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServiceDesk::EmailRateLimiter, :saas, :clean_gitlab_redis_rate_limiting, :freeze_time,
  feature_category: :service_desk do
  before_all do
    create(:plan_limits, :free_plan, service_desk_outbound_emails_per_hour: 1)
    create(:plan_limits, :ultimate_plan, service_desk_outbound_emails_per_hour: 3)
  end

  let_it_be(:group_free_plan) { create(:group_with_plan, plan: :free_plan) }
  let_it_be_with_reload(:group_ultimate_plan) do
    create(:group_with_plan, plan: :ultimate_plan).tap do |group|
      group.gitlab_subscription.update_column(:created_at, 1.year.ago)
    end
  end

  let_it_be(:project_free_plan) { create(:project, group: group_free_plan, service_desk_enabled: true) }
  let_it_be_with_reload(:project_ultimate_plan) do
    create(:project, group: group_ultimate_plan, service_desk_enabled: true)
  end

  before do
    allow(::ServiceDesk).to receive(:enabled?).and_return(true)
  end

  describe '#rate_limit_batch!' do
    using RSpec::Parameterized::TableSyntax

    where(:project, :limit) do
      ref(:project_free_plan)     | 1
      ref(:project_ultimate_plan) | 3
    end

    with_them do
      it 'resolves the per-plan threshold' do
        limiter = described_class.new(project)

        # Strict: Service Desk suppresses the batch that trips the window, so a
        # limit of N sends exactly N before the next batch is suppressed.
        limit.times { expect(limiter.rate_limit_batch!(1)).to be(false) }

        expect(limiter.rate_limit_batch!(1)).to be(true)
      end
    end

    context 'when the paid namespace is on probation' do
      before do
        group_ultimate_plan.gitlab_subscription.update_column(:created_at, 1.day.ago)
      end

      it 'applies the free plan threshold' do
        limiter = described_class.new(project_ultimate_plan)

        expect(limiter.rate_limit_batch!(1)).to be(false)
        expect(limiter.rate_limit_batch!(1)).to be(true)
      end

      context 'when the probation feature flag is disabled' do
        before do
          stub_feature_flags(service_desk_paid_namespace_probation: false)
        end

        it 'applies the plan threshold' do
          limiter = described_class.new(project_ultimate_plan)

          3.times { expect(limiter.rate_limit_batch!(1)).to be(false) }
          expect(limiter.rate_limit_batch!(1)).to be(true)
        end
      end

      context 'when the Service Desk email rate limit feature flag is disabled' do
        before do
          stub_feature_flags(service_desk_email_rate_limit: false)
        end

        it 'does not look up the probation' do
          expect(::ServiceDesk::PaidNamespaceProbation).not_to receive(:new)

          expect(described_class.new(project_ultimate_plan).rate_limit_batch!(1)).to be(false)
        end
      end
    end
  end
end
