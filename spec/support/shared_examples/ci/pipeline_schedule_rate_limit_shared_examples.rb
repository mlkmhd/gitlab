# frozen_string_literal: true

# Including groups define `user` (a maintainer of `project`), `project`,
# `unauthorized_user`, `grant_access(user)` and `execute_service(actor = user,
# target_project = project)`, which performs one fresh attempt.
RSpec.shared_examples 'a rate limited pipeline schedule management action' do
  let_it_be(:other_user) { create(:user) }
  let_it_be(:other_project) { create(:project, maintainers: user) }

  let(:throttle_message) { ::Gitlab::ApplicationRateLimiter.throttled_error_message }

  before_all do
    project.add_maintainer(other_user)
  end

  it 'succeeds while under the limit' do
    expect(execute_service).to be_success
  end

  it 'counts one attempt per call' do
    stub_application_setting(pipeline_schedule_management_limit_per_user: 2)

    2.times { expect(execute_service).to be_success }

    expect(execute_service.reason).to eq(:rate_limited)
  end

  context 'when the limit is reached' do
    before do
      stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
    end

    it 'throttles the next attempt', :aggregate_failures do
      expect(execute_service).to be_success

      response = execute_service

      expect(response).to be_error
      expect(response.reason).to eq(:rate_limited)
      expect(response.message).to eq(throttle_message)
    end

    it 'throttles the next attempt in another project' do
      execute_service

      expect(execute_service(user, other_project).reason).to eq(:rate_limited)
    end

    it 'does not throttle another user' do
      execute_service

      expect(execute_service(other_user)).to be_success
    end

    it 'logs the throttled attempt' do
      allow(Gitlab::AppJsonLogger).to receive(:info)

      2.times { execute_service }

      expect(Gitlab::AppJsonLogger).to have_received(:info).with(
        a_hash_including(
          Labkit::Fields::CLASS_NAME => described_class.to_s,
          message: 'Pipeline schedule management rate limit exceeded',
          rate_limit: 'pipeline_schedule_management',
          Labkit::Fields::GL_PROJECT_ID => project.id,
          Labkit::Fields::GL_USER_ID => user.id
        )
      ).once
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(rate_limit_pipeline_schedule_management: false)
      end

      it 'does not throttle' do
        2.times { expect(execute_service).to be_success }
      end
    end
  end

  context 'when the user is denied access' do
    before do
      stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
    end

    it 'returns the access error first but still counts the attempt', :aggregate_failures do
      2.times do
        response = execute_service(unauthorized_user)

        expect(response).to be_error
        expect(response.reason).not_to eq(:rate_limited)
      end

      grant_access(unauthorized_user)

      expect(execute_service(unauthorized_user).reason).to eq(:rate_limited)
    end
  end

  context 'when the limit is disabled' do
    before do
      stub_application_setting(pipeline_schedule_management_limit_per_user: 0)
    end

    it 'does not throttle' do
      3.times { expect(execute_service).to be_success }
    end
  end
end
