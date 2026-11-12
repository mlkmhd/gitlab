# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Labels::DestroyService, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  describe '#execute' do
    context 'when current_user is provided' do
      it 'destroys the label successfully' do
        label = create(:label, project: project)

        expect { described_class.new(user, label).execute }.to change { Label.count }.by(-1)
      end
    end

    it 'destroys the label' do
      label = create(:label, project: project)

      expect { described_class.new(user, label).execute }.to change { Label.count }.by(-1)
    end

    it 'returns the destroyed label' do
      label = create(:label, project: project)
      result = described_class.new(user, label).execute

      expect(result).to eq(label)
      expect(result).to be_destroyed
    end

    context 'when destroy fails' do
      it 'returns the label without destroying it' do
        label = create(:label, project: project)
        allow(label).to receive(:destroy).and_return(false)

        result = described_class.new(user, label).execute

        expect(result).to eq(label)
        expect(result).not_to be_destroyed
      end
    end

    describe 'rate limiting' do
      let!(:label) { create(:label, project: project) }

      subject(:execute) { described_class.new(user, label).execute }

      it 'charges the label_delete limit once per delete' do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:label_delete, scope: { user: user }, users_allowlist: []).and_return(false)

        expect { execute }.to change { Label.count }.by(-1)
      end

      context 'when the user is throttled' do
        before do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:label_delete, scope: { user: user }, users_allowlist: []).and_return(true)
        end

        it 'raises a rate limited error and keeps the label' do
          expect { execute }.to raise_error(RateLimitedService::RateLimitedError)
          expect(label.reload).to be_persisted
        end
      end

      context 'when the limit is changed in the application settings',
        :freeze_time, :clean_gitlab_redis_rate_limiting do
        before do
          stub_application_setting(label_delete_limit: 2)
        end

        it 'raises a rate limited error after the configured number of deletes' do
          create_list(:label, 2, project: project).each { |other_label| described_class.new(user, other_label).execute }

          expect { execute }.to raise_error(RateLimitedService::RateLimitedError)
          expect(label.reload).to be_persisted
        end
      end

      context 'when the label_delete_rate_limit feature flag is disabled',
        :freeze_time, :clean_gitlab_redis_rate_limiting do
        before do
          stub_feature_flags(label_delete_rate_limit: false)
          stub_application_setting(label_delete_limit: 1)
        end

        it 'counts the deletes in log mode without throttling', :request_store do
          described_class.new(user, create(:label, project: project)).execute

          expect { execute }.to change { Label.count }.by(-1)
          expect(Gitlab::Instrumentation::RateLimitState.payload[:rate_limit_state])
            .to include('applimiter_label_delete:limit_label_deletes_by_user_log:log')
        end
      end
    end
  end
end
