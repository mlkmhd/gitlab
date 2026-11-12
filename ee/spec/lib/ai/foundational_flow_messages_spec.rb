# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FoundationalFlowMessages, feature_category: :duo_agent_platform do
  describe '.usage_billing_forbidden_error' do
    subject(:message) { described_class.usage_billing_forbidden_error }

    it 'includes guidance to contact an administrator' do
      expect(message).to include('contact your administrator')
    end

    it 'mentions usage billing' do
      expect(message).to include('Usage billing is not available')
    end
  end

  describe '.usage_quota_exceeded_error' do
    it 'names the flow and says it did not run for lack of GitLab Credits' do
      expect(described_class.usage_quota_exceeded_error(flow_name: 'Duo Security Review')).to eq(
        ':warning: Duo Security Review did not run because no GitLab Credits remain for this billing period. ' \
          'To continue using this flow, contact your administrator.'
      )
    end
  end

  describe '.concurrent_scan_limit_error' do
    it 'names the flow and says it did not run because of the scan limit' do
      expect(described_class.concurrent_scan_limit_error(flow_name: 'Business Logic Security Scan')).to eq(
        ':warning: Business Logic Security Scan did not run because this group already has the maximum ' \
          'number of scans running. Retry the job when one of them finishes.'
      )
    end
  end

  describe '.namespace_missing_error' do
    let(:user) { build_stubbed(:user, name: 'User Name') }

    subject(:message) { described_class.namespace_missing_error(user) }

    it 'includes actionable guidance about setting a default namespace' do
      expect(message).to include(user.to_reference)
      expect(message).to include('default GitLab Duo namespace')
      expect(message).to include('preferences')
    end

    it 'includes a link to the documentation' do
      expect(message).to include('set-a-default-gitlab-duo-namespace')
    end
  end

  describe '.could_not_prepare_session_error' do
    subject(:message) { described_class.could_not_prepare_session_error }

    it 'tells the user to retry, then to contact an administrator' do
      expect(message).to include('Try again later')
      expect(message).to include('contact your administrator')
    end
  end

  describe '.repository_empty_error' do
    it 'says the repository is empty' do
      expect(described_class.repository_empty_error).to eq('Repository is empty')
    end
  end
end
