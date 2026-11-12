# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Milestones::DestroyService, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, maintainers: user) }
  let_it_be_with_reload(:project) { create(:project, group: group) }

  subject(:service) { described_class.new(container, user, {}) }

  describe '#execute' do
    shared_examples 'deletes milestone id from issuables' do
      specify do
        stub_const('Milestones::DestroyService::BATCH_SIZE', 2)

        issues = create_list(:issue, described_class::BATCH_SIZE + 1, project: project, milestone: milestone)
        merge_request = create(:merge_request, source_project: project, milestone: milestone)

        expect(milestone).to receive(:run_after_commit).and_yield

        expect { expect(service.execute(milestone)).to eq(milestone) }
          .to publish_event(WorkItems::BulkUpdatedEvent)
          .with(
            root_namespace_id: group.id,
            work_item_ids: issues.take(described_class::BATCH_SIZE).map(&:id),
            updated_attributes: %w[milestone_id]
          )

        expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound

        issues.each do |issue|
          expect(issue.reload.milestone).to be_nil
        end
        expect(merge_request.reload.milestone).to be_nil
      end
    end

    context 'on project milestones' do
      let(:milestone) { create(:milestone, title: 'Milestone v1.0', project: project) }

      let(:container) { project }

      it 'deletes milestone' do
        service.execute(milestone)

        expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
      end

      it_behaves_like 'deletes milestone id from issuables'

      it 'clears the milestone from every issue past the work item update limit',
        :freeze_time, :clean_gitlab_redis_rate_limiting do
        stub_application_setting(work_item_update_limit: 1)
        issues = create_list(:issue, 2, project: project, milestone: milestone)

        service.execute(milestone)

        expect(issues.map { |issue| issue.reload.milestone }).to all(be_nil)
      end

      it 'logs destroy event and runs on-delete webhook' do
        expect(service).to receive(:execute_hooks).with(milestone, 'delete')

        service.execute(milestone)

        event = Event.where(project_id: milestone.project_id, target_type: 'Milestone')

        expect(event.count).to eq(1)
      end

      context 'when a release is tied to a milestone' do
        it 'destroys the milestone but not the associated release' do
          release = create(
            :release,
            tag: 'v1.0',
            project: project,
            milestones: [milestone]
          )

          expect { service.execute(milestone) }.not_to change { Release.count }
          expect(release.reload).to be_persisted
        end
      end
    end

    context 'on group milestones' do
      let(:milestone) { create(:milestone, group: group) }
      let(:container) { group }

      it 'deletes milestone' do
        service.execute(milestone)

        expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
      end

      it_behaves_like 'deletes milestone id from issuables'

      it 'does not log destroy event and does not run on-delete webhook' do
        expect { service.execute(milestone) }.not_to change { Event.count }
      end
    end

    describe 'rate limiting', :freeze_time, :clean_gitlab_redis_rate_limiting do
      let(:container) { project }

      let_it_be_with_refind(:milestone) { create(:milestone, project: project) }

      before do
        stub_const("#{described_class}::RATE_LIMITED_ISSUABLES_THRESHOLD", 1)
      end

      def use_rate_limit(times, scope_user: user)
        times.times { Gitlab::ApplicationRateLimiter.throttled?(:milestone_destroy, scope: { user: scope_user }) }
      end

      context 'when the milestone has more issues and merge requests than the threshold' do
        before_all do
          create(:issue, project: project, milestone: milestone)
          create(:merge_request, source_project: project, milestone: milestone)
        end

        it 'deletes the milestone when the user is under the limit' do
          use_rate_limit(9)

          service.execute(milestone)

          expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
        end

        it 'raises a rate limit error and keeps the milestone after 10 deletes in a minute', :aggregate_failures do
          use_rate_limit(10)

          expect { service.execute(milestone) }.to raise_error(RateLimitedService::RateLimitedError)
          expect(milestone.reload).to be_persisted
        end

        it 'does not count deletes by other users' do
          use_rate_limit(10, scope_user: create(:user))

          service.execute(milestone)

          expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
        end

        context 'when the limit is changed in the application settings' do
          before do
            stub_application_setting(milestone_destroy_limit: 2)
          end

          it 'raises a rate limit error after the configured number of deletes', :aggregate_failures do
            use_rate_limit(2)

            expect { service.execute(milestone) }.to raise_error(RateLimitedService::RateLimitedError)
            expect(milestone.reload).to be_persisted
          end
        end

        context 'when the limit is set to 0' do
          before do
            stub_application_setting(milestone_destroy_limit: 0)
          end

          it 'does not rate limit the deletes' do
            use_rate_limit(10)

            service.execute(milestone)

            expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
          end
        end

        context 'when milestone_destroy_rate_limit is disabled' do
          before do
            stub_feature_flags(milestone_destroy_rate_limit: false)
          end

          it 'deletes the milestone without checking the rate limit', :aggregate_failures do
            use_rate_limit(10)

            expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:milestone_destroy, anything)

            service.execute(milestone)

            expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
          end
        end
      end

      context 'when the milestone only has merge requests over the threshold' do
        before_all do
          create(:merge_request, source_project: project, milestone: milestone)
          create(:merge_request, :simple, source_project: project, milestone: milestone)
        end

        it 'raises a rate limit error and keeps the milestone', :aggregate_failures do
          use_rate_limit(10)

          expect { service.execute(milestone) }.to raise_error(RateLimitedService::RateLimitedError)
          expect(milestone.reload).to be_persisted
        end
      end

      context 'when the milestone is at the threshold' do
        before_all do
          create(:issue, project: project, milestone: milestone)
        end

        it 'deletes the milestone without checking the rate limit', :aggregate_failures do
          use_rate_limit(10)

          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:milestone_destroy, anything)

          service.execute(milestone)

          expect { milestone.reload }.to raise_error ActiveRecord::RecordNotFound
        end
      end
    end
  end
end
