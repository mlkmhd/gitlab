# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::Tokens::RunnerAuthenticationToken, :aggregate_failures, feature_category: :system_access do
  let_it_be(:admin) { create(:admin) }

  subject(:token) { described_class.new(runner.token, :api_admin_token) }

  describe '#revoke! on a GitLab Dedicated instance', :enable_admin_mode do
    before do
      stub_application_setting(gitlab_dedicated_instance: true)
    end

    context 'with a GitLab-hosted runner' do
      let_it_be_with_refind(:runner) { create(:ci_runner, :instance, :hosted_runner) }
      let_it_be(:hosted_registration) { create(:ci_hosted_runner, runner: runner) }

      it 'does not reset the runner token for an admin' do
        result = nil

        expect { result = token.revoke!(admin) }.not_to change { runner.reload.token }
        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
        expect(result.message).to eq(
          'GitLab manages the authentication token of this hosted runner. To rotate it, contact GitLab Support.'
        )
      end
    end

    context 'with an instance runner created by the admin bot without a hosted registration' do
      let_it_be_with_refind(:runner) { create(:ci_runner, :instance, :hosted_runner) }

      it 'resets the runner token for an admin' do
        result = nil

        expect { result = token.revoke!(admin) }.to change { runner.reload.token }
        expect(result).to be_success
      end
    end

    context 'with a customer-registered runner' do
      let_it_be_with_refind(:runner) { create(:ci_runner, :instance, registration_type: :authenticated_user) }

      it 'resets the runner token for an admin' do
        result = nil

        expect { result = token.revoke!(admin) }.to change { runner.reload.token }
        expect(result).to be_success
      end
    end
  end
end
