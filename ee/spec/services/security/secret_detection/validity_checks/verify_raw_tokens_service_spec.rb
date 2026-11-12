# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::ValidityChecks::VerifyRawTokensService, feature_category: :secret_detection do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:active_pat) { create(:personal_access_token) }

  let(:user) { developer }
  let(:acting_project) { project }
  let(:tokens) do
    [
      { id: '1', token_type: 'gitlab_personal_access_token', raw_token: active_pat.token },
      { id: '2', token_type: 'gitlab_personal_access_token', raw_token: 'not-in-the-database' },
      { id: '3', token_type: 'not_a_rule', raw_token: 'value' }
    ]
  end

  subject(:result) do
    described_class.new(current_user: user, project: acting_project, tokens: tokens, organization_id: nil).execute
  end

  before do
    stub_licensed_features(secret_detection_validity_checks: true)
  end

  it 'returns one result per id, without raw values', :aggregate_failures do
    expect(result).to be_success
    expect(result.payload[:results]).to eq([
      { id: '1', token_type: 'gitlab_personal_access_token', status: 'active' },
      { id: '2', token_type: 'gitlab_personal_access_token', status: 'unknown' },
      { id: '3', token_type: 'not_a_rule', error: 'unsupported_token_type' }
    ])
    expect(result.payload.to_json).not_to include(active_pat.token)
  end

  it 'verifies each token type in one call' do
    expect_next_instance_of(Security::SecretDetection::ValidityChecks::GitlabTokenVerifier) do |verifier|
      expect(verifier).to receive(:verify)
        .with('gitlab_personal_access_token', [active_pat.token, 'not-in-the-database']).once.and_call_original
      expect(verifier).to receive(:verify).with('not_a_rule', ['value']).once.and_call_original
    end

    result
  end

  it 'does not persist a token status', :aggregate_failures do
    expect { result }.not_to change { Vulnerabilities::FindingTokenStatus.count + Security::FindingTokenStatus.count }
    expect(result).to be_success
  end

  it 'accepts a role inherited from the group' do
    user = create(:user, maintainer_of: group)

    expect(described_class.new(current_user: user, project: project, tokens: tokens, organization_id: nil).execute)
      .to be_success
  end

  shared_examples 'a denied request' do
    it 'is not found and verifies nothing', :aggregate_failures do
      expect(Security::SecretDetection::ValidityChecks::GitlabTokenVerifier).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end
  end

  context 'with callers the endpoint is not for' do
    let_it_be(:reporter) { create(:user, reporter_of: project) }
    let_it_be(:outsider) { create(:user) }
    let_it_be(:other_project) { create(:project) }

    where(:case_name, :user, :acting_project) do
      [
        ['a reporter', ref(:reporter), ref(:project)],
        ['a user outside the project', ref(:outsider), ref(:project)],
        ['a developer of another project', ref(:developer), ref(:other_project)],
        ['no user', nil, ref(:project)],
        ['no project', ref(:developer), nil]
      ]
    end

    with_them do
      it_behaves_like 'a denied request'
    end
  end

  context 'when validity checks are not licensed' do
    before do
      stub_licensed_features(secret_detection_validity_checks: false)
    end

    it_behaves_like 'a denied request'
  end
end
