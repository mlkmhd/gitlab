# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ci::Runners::ResetAuthenticationTokenService, '#execute', :aggregate_failures, feature_category: :fleet_visibility do
  before_all do
    freeze_time # Freeze time before `let_it_be` runs, so that time is immediately frozen before computing deadlines
  end

  after :all do
    unfreeze_time
  end

  let_it_be_with_refind(:runner_without_token_rotation_deadline) { create(:ci_runner) }
  let_it_be_with_refind(:runner_with_future_rotation_deadline) { create(:ci_runner, :with_future_rotation_deadline) }
  let_it_be(:runner_with_past_rotation_deadline) { create(:ci_runner, :with_past_rotation_deadline) }
  let_it_be(:runner_at_token_rotation_deadline) { create(:ci_runner, token_rotation_deadline: Time.current) }

  let(:service) { described_class.new(runner: runner, current_user: current_user, source: source) }

  subject(:execute) { service.execute }

  shared_examples 'rotation deadline behavior' do
    context 'when token_rotation_deadline is nil' do
      let(:runner) { runner_without_token_rotation_deadline }

      it 'does reset authentication token and returns success' do
        expect { execute }.to change { runner.reload.token }
        expect(execute).to be_success
      end
    end

    context 'when runner has token_rotation_deadline in the future' do
      let(:runner) { runner_with_future_rotation_deadline }

      it 'resets token and clears token_rotation_deadline' do
        expect { execute }.to change { runner.reload.token }
        expect(execute).to be_success
        expect(runner.reload.token_rotation_deadline).to be_nil
      end
    end

    context 'when rotation deadline has passed' do
      let(:runner) { runner_with_past_rotation_deadline }

      it 'rejects rotation with forbidden error' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:forbidden)
        expect(execute.message).to include('Token rotation deadline has passed')
      end

      it 'does not change the token' do
        expect { execute }.not_to change { runner.reload.token }
      end
    end

    context 'when rotation deadline is exactly now' do
      let(:runner) { runner_at_token_rotation_deadline }

      it 'rejects rotation with forbidden error' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:forbidden)
        expect(execute.message).to include('Token rotation deadline has passed')
      end
    end
  end

  context 'without source' do
    let(:source) { nil }

    context 'with admin', :enable_admin_mode do
      let_it_be(:current_user) { build(:admin) }

      it_behaves_like 'rotation deadline behavior'
    end
  end

  context 'with source' do
    let(:current_user) { nil }

    context 'with permitted source' do
      let(:source) { :runner_api }

      it_behaves_like 'rotation deadline behavior'
    end
  end

  context 'with a GitLab Dedicated hosted runner on a GitLab Dedicated instance' do
    let_it_be_with_refind(:runner) { create(:ci_runner, :instance, :hosted_runner) }
    let_it_be(:hosted_registration) { create(:ci_hosted_runner, runner: runner) }

    before do
      stub_application_setting(gitlab_dedicated_instance: true)
    end

    context 'when an admin resets the token', :enable_admin_mode do
      let(:current_user) { create(:admin) }
      let(:source) { nil }

      it 'does not reset the token' do
        expect { execute }.not_to change { runner.reload.token }
        expect(execute).to be_error
        expect(execute.reason).to eq(:forbidden)
        expect(execute.message).to eq(
          'GitLab manages the authentication token of this hosted runner. To rotate it, contact GitLab Support.'
        )
      end
    end

    context 'when the admin bot resets the token' do
      let(:current_user) { runner.creator }
      let(:source) { nil }

      it 'does not reset the token' do
        expect { execute }.not_to change { runner.reload.token }
        expect(execute).to be_error
        expect(execute.reason).to eq(:forbidden)
        expect(execute.message).to eq(
          'GitLab manages the authentication token of this hosted runner. To rotate it, contact GitLab Support.'
        )
      end
    end

    context 'when the runner rotates its own token' do
      let(:current_user) { nil }
      let(:source) { :runner_api }

      it 'resets the token' do
        expect { execute }.to change { runner.reload.token }
        expect(execute).to be_success
      end
    end
  end

  context 'with an instance runner created by the admin bot without a hosted registration', :enable_admin_mode do
    let_it_be_with_refind(:runner) { create(:ci_runner, :instance, :hosted_runner) }
    let(:current_user) { create(:admin) }
    let(:source) { nil }

    before do
      stub_application_setting(gitlab_dedicated_instance: true)
    end

    it 'resets the token for an admin' do
      expect { execute }.to change { runner.reload.token }
      expect(execute).to be_success
    end
  end

  # The model only accepts hosted registrations for instance runners, so this stubs one.
  context 'with a group runner that has a hosted registration on a GitLab Dedicated instance' do
    let_it_be(:runner) { create(:ci_runner, :group, groups: [create(:group)]) }
    let_it_be(:current_user) { create(:user) }
    let(:source) { nil }

    before do
      stub_application_setting(gitlab_dedicated_instance: true)
      allow(runner).to receive(:hosted_registration).and_return(build(:ci_hosted_runner))
    end

    it 'refuses a user without access with the generic message' do
      expect(execute).to be_error
      expect(execute.reason).to eq(:forbidden)
      expect(execute.message).to eq('Not permitted to reset')
    end
  end
end
