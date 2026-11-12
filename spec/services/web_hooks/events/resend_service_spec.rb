# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::Events::ResendService, feature_category: :webhooks do
  include StubRequests
  let_it_be(:hook) { create(:project_hook) }
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:log) { create(:web_hook_log, web_hook: hook) }

  subject(:service) { described_class.new(log, current_user: user) }

  describe '#execute' do
    context 'when user is authorized' do
      before do
        hook.project.add_owner(user)
      end

      context 'when the hook URL has changed' do
        before do
          allow(log).to receive(:url_current?).and_return(false)
        end

        it 'returns error' do
          service_result = service.execute

          expect(service_result).to be_error
          expect(service_result.message).to eq("The hook URL has changed. This log entry cannot be retried.")
        end
      end

      context 'when the hook URL has not changed' do
        before do
          allow(log).to receive(:url_current?).and_return(true)
        end

        it 'executes successfully' do
          stub_full_request(log.web_hook.url, method: :post)

          expect(log.web_hook).to receive(:execute).with(log.request_data, log.trigger,
            { idempotency_key: log.idempotency_key }).and_call_original

          expect(service.execute).to be_success
        end
      end
    end

    context 'when user is unauthorized' do
      before do
        hook.project.add_developer(user)
      end

      it 'returns error' do
        service_result = service.execute

        expect(service_result).to be_error
        expect(service_result.message).to eq("The current user is not authorized to resend a hook event.")
      end
    end

    context 'with a system hook' do
      let_it_be_with_refind(:organization) { create(:organization) }
      let_it_be_with_refind(:other_organization) { create(:organization) }
      let_it_be_with_refind(:system_hook) { create(:system_hook, organization: organization) }
      let_it_be_with_reload(:system_hook_log) { create(:web_hook_log, web_hook: system_hook) }

      subject(:service) { described_class.new(system_hook_log, current_user: user) }

      context 'when the user is an admin of the hook organization' do
        before do
          create(:organization_owner, organization: organization, user: user)
          allow(system_hook_log).to receive(:url_current?).and_return(true)
        end

        it 'executes successfully' do
          stub_full_request(system_hook.url, method: :post)

          expect(system_hook_log.web_hook).to receive(:execute).and_call_original

          expect(service.execute).to be_success
        end
      end

      context 'when the user is an admin of a different organization' do
        before do
          create(:organization_owner, organization: other_organization, user: user)
        end

        it 'returns error' do
          service_result = service.execute

          expect(service_result).to be_error
          expect(service_result.message).to eq("The current user is not authorized to resend a hook event.")
        end
      end
    end

    context 'with a service hook' do
      let_it_be(:integration) { create(:integration) }
      let_it_be(:service_hook) { create(:service_hook, integration: integration, project_id: integration.project_id) }
      let_it_be_with_reload(:service_hook_log) { create(:web_hook_log, web_hook: service_hook) }

      subject(:service) { described_class.new(service_hook_log, current_user: user) }

      before do
        allow(service_hook_log).to receive(:url_current?).and_return(false)
      end

      context 'when the user can administer the integration' do
        before do
          integration.project.add_maintainer(user)
        end

        it 'passes the authorization check' do
          expect(service.execute.message).to eq("The hook URL has changed. This log entry cannot be retried.")
        end
      end

      context 'when the user cannot administer the integration' do
        before do
          integration.project.add_developer(user)
        end

        it 'returns error' do
          expect(service.execute.message).to eq("The current user is not authorized to resend a hook event.")
        end
      end
    end
  end
end
