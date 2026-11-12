# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SecurityAiFlowFeedbackCreate', :clean_gitlab_redis_rate_limiting,
  feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
  let_it_be(:flag) do
    create(:vulnerabilities_flag, :false_positive,
      finding: vulnerability.finding,
      origin: Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN,
      status: :detected_as_fp,
      confidence_score: 0.9)
  end

  let(:current_user) { user }
  let(:vulnerability_id) { vulnerability.to_global_id.to_s }
  let(:input) { { vulnerability_id: vulnerability_id, sentiment: 'DISAGREE', reasons: %w[VERDICT_WRONG OTHER] } }
  let(:mutation) { graphql_mutation(:security_ai_flow_feedback_create, input) }
  let(:mutation_response) { graphql_mutation_response(:security_ai_flow_feedback_create) }

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    stub_licensed_features(security_dashboard: true)
    allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available_for_project?).and_return(true)
  end

  shared_examples 'denies access' do
    it 'returns a resource not available error and emits no event' do
      expect { request }.not_to trigger_internal_events('submit_security_ai_flow_feedback')

      expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
    end
  end

  shared_examples 'returns the no AI assessment error' do
    it 'returns an error and emits no event' do
      expect { request }.not_to trigger_internal_events('submit_security_ai_flow_feedback')

      expect(mutation_response['errors']).to contain_exactly(
        s_('SecurityAiFlowFeedback|No AI assessment is available for this vulnerability')
      )
    end
  end

  it 'emits the feedback event about the AI flag and returns no errors' do
    expect { request }.to trigger_internal_events('submit_security_ai_flow_feedback')
      .with(
        project: project,
        user: user,
        category: 'Vulnerabilities::SecurityAiFlowFeedbacks::CreateService',
        additional_properties: {
          label: 'sast_fp_detection',
          property: 'disagree',
          reasons: 'verdict_wrong,other',
          vulnerability_id: vulnerability.id,
          flag_id: flag.id,
          severity: 'high',
          report_type: 'sast',
          scanner_external_id: 'custom',
          scanner_vendor: 'custom',
          rule_identifier_type: 'custom',
          file_extension: 'java',
          has_data_flow: 'false',
          ai_confidence_score: 0.9,
          ai_verdict: 'detected_as_fp'
        }
      )
      .and not_change { Vulnerabilities::Flag.count }

    expect(response).to have_gitlab_http_status(:success)
    expect(mutation_response['errors']).to be_empty
  end

  context 'when the vulnerability has no AI flag' do
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }

    it_behaves_like 'returns the no AI assessment error'
  end

  context 'when the vulnerability only has a manual flag' do
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }

    before_all do
      create(:vulnerabilities_flag, :false_positive,
        finding: vulnerability.finding, origin: 'manual_123', status: :dismissed)
    end

    it_behaves_like 'returns the no AI assessment error'
  end

  context 'when the vulnerability belongs to a project the user cannot read' do
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: create(:project)) }

    before_all do
      create(:vulnerabilities_flag, :false_positive,
        finding: vulnerability.finding,
        origin: Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN,
        status: :detected_as_fp)
    end

    it_behaves_like 'denies access'
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_security_ai_flow_feedback do
    let(:boundary_object) { project }
    let(:request) do
      post_graphql_mutation(
        graphql_mutation(:security_ai_flow_feedback_create, input, 'errors'),
        token: { personal_access_token: pat }
      )
    end
  end

  context 'when a granular token is scoped to another project the user can access' do
    let_it_be(:other_project) { create(:project, developers: user) }
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(other_project),
        permissions: 'create_security_ai_flow_feedback')
    end

    it 'denies access and emits no event' do
      expect { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
        .not_to trigger_internal_events('submit_security_ai_flow_feedback')

      expect(graphql_errors).to include(a_hash_including('message' => include('fine-grained personal access token')))
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_ai_flow_feedback: false)
    end

    it_behaves_like 'denies access'
  end

  context 'when the user is not authenticated' do
    let(:current_user) { nil }

    it_behaves_like 'denies access'
  end

  context 'when the user is a guest' do
    let(:current_user) { create(:user, guest_of: project) }

    it_behaves_like 'denies access'

    it 'does not count towards the rate limit' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
        .with(:security_ai_flow_feedback_create, anything)

      request
    end
  end

  context 'when the user is an auditor' do
    let(:current_user) { create(:user, :auditor) }

    it_behaves_like 'denies access'
  end

  context 'when the Duo Agent Platform is not available' do
    before do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available_for_project?).and_return(false)
    end

    it_behaves_like 'denies access'
  end

  context 'with the real project-level Duo check' do
    before do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available_for_project?).and_call_original
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(project).and_return(true)
    end

    it 'accepts the feedback when Duo features are enabled for the project' do
      expect(Gitlab::InternalEvents).to receive(:track_event).with('submit_security_ai_flow_feedback', any_args)

      request

      expect(mutation_response['errors']).to be_empty
    end

    context 'when Duo features are disabled for the project' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
      end

      it_behaves_like 'denies access'
    end
  end

  context 'when the vulnerability does not exist' do
    let(:vulnerability_id) { "gid://gitlab/Vulnerability/#{non_existing_record_id}" }

    it_behaves_like 'denies access'
  end

  context 'when reasons are given with an agree sentiment' do
    let(:input) { { vulnerability_id: vulnerability_id, sentiment: 'AGREE', reasons: %w[OTHER] } }

    it 'returns an error' do
      expect { request }.not_to trigger_internal_events('submit_security_ai_flow_feedback')

      expect(mutation_response['errors']).to contain_exactly(
        s_('SecurityAiFlowFeedback|Reasons are only allowed when the sentiment is disagree')
      )
    end
  end

  context 'when there are too many reasons' do
    let(:input) { { vulnerability_id: vulnerability_id, sentiment: 'DISAGREE', reasons: Array.new(6, 'OTHER') } }

    it 'returns a validation error' do
      request

      expect_graphql_errors_to_include('reasons is too long (maximum is 5)')
    end
  end

  context 'when the rate limit is exceeded', :freeze_time do
    before do
      60.times do
        Gitlab::ApplicationRateLimiter.throttled?(:security_ai_flow_feedback_create, scope: { user: current_user })
      end
    end

    it 'returns an error' do
      expect { request }.not_to trigger_internal_events('submit_security_ai_flow_feedback')

      expect(mutation_response['errors']).to contain_exactly(
        s_('SecurityAiFlowFeedback|You have submitted feedback too many times. Please try again later.')
      )
    end
  end
end
