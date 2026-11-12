# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::SecurityAiFlowFeedbacks::CreateService, :clean_gitlab_redis_rate_limiting,
  feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
  let_it_be(:finding) { vulnerability.finding }
  let_it_be(:flag) do
    create(:vulnerabilities_flag, :false_positive,
      finding: finding,
      origin: Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN,
      status: :detected_as_fp,
      confidence_score: 0.9,
      workflow: workflow)
  end

  let(:current_user) { user }
  let(:subject_vulnerability) { vulnerability }
  let(:sentiment) { 'disagree' }
  let(:reasons) { %w[verdict_wrong ignored_data_flow] }

  subject(:execute) do
    described_class.new(
      current_user: current_user, vulnerability: subject_vulnerability, sentiment: sentiment, reasons: reasons
    ).execute
  end

  before do
    stub_licensed_features(security_dashboard: true)
    allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available_for_project?).with(project).and_return(true)
  end

  shared_examples 'an error without an event' do |message, reason|
    it 'returns an error and emits no event' do
      expect { execute }.not_to trigger_internal_events('submit_security_ai_flow_feedback')

      expect(execute).to be_error
      expect(execute.message).to eq(message)
      expect(execute.reason).to eq(reason)
    end
  end

  context 'with valid feedback' do
    let(:expected_properties) do
      {
        label: 'sast_fp_detection',
        vulnerability_id: vulnerability.id,
        flag_id: flag.id,
        workflow_id: workflow.id,
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
    end

    it 'emits the event with the metadata snapshot' do
      expect { execute }
        .to trigger_internal_events('submit_security_ai_flow_feedback')
        .with(
          project: project,
          namespace: project.namespace,
          user: user,
          category: described_class.name,
          additional_properties: expected_properties.merge(
            property: 'disagree',
            reasons: 'verdict_wrong,ignored_data_flow'
          )
        )
    end

    it 'returns success' do
      expect(execute).to be_success
      expect(execute.payload[:flag]).to eq(flag)
    end

    it 'only emits strings and numbers' do
      properties = execute.payload[:event_properties]

      expect(properties.values).to all(be_a(String).or(be_a(Numeric)))
    end

    it 'does not duplicate the flow type outside the label' do
      expect(execute.payload[:event_properties]).not_to have_key(:flow_name)
    end

    context 'when the sentiment is agree without reasons' do
      let(:sentiment) { 'agree' }
      let(:reasons) { nil }

      it 'emits the event without reasons' do
        expect { execute }
          .to trigger_internal_events('submit_security_ai_flow_feedback')
          .with(
            project: project,
            namespace: project.namespace,
            user: user,
            category: described_class.name,
            additional_properties: expected_properties.merge(property: 'agree')
          )

        expect(execute.payload[:event_properties]).not_to have_key(:reasons)
      end
    end

    context 'when the sentiment is disagree without reasons' do
      let(:reasons) { nil }

      it 'emits the event without reasons' do
        expect { execute }
          .to trigger_internal_events('submit_security_ai_flow_feedback')
          .with(
            project: project,
            namespace: project.namespace,
            user: user,
            category: described_class.name,
            additional_properties: expected_properties.merge(property: 'disagree')
          )

        expect(execute.payload[:event_properties]).not_to have_key(:reasons)
      end
    end

    context 'when a reason is repeated' do
      let(:reasons) { %w[verdict_wrong ignored_data_flow verdict_wrong] }

      it 'sends each reason once' do
        expect(execute.payload[:event_properties][:reasons]).to eq('verdict_wrong,ignored_data_flow')
      end
    end

    context 'when the flag has no workflow' do
      let(:subject_vulnerability) { create(:vulnerability, :with_finding, project: project) }

      before do
        create(:vulnerabilities_flag, :false_positive,
          finding: subject_vulnerability.finding,
          origin: Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN,
          status: :detected_as_fp)
      end

      it 'still identifies the vulnerability' do
        properties = execute.payload[:event_properties]

        expect(properties).to include(vulnerability_id: subject_vulnerability.id)
        expect(properties).not_to have_key(:workflow_id)
      end
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_ai_flow_feedback: false)
    end

    it_behaves_like 'an error without an event', s_('SecurityAiFlowFeedback|Feature not available'), :feature_disabled
  end

  context 'when the user cannot create feedback' do
    let(:current_user) { create(:user) }

    it_behaves_like 'an error without an event', s_('SecurityAiFlowFeedback|Unauthorized'), :forbidden
  end

  context 'when the Duo Agent Platform is not available for the project' do
    before do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available_for_project?).with(project).and_return(false)
    end

    it_behaves_like 'an error without an event', s_('SecurityAiFlowFeedback|Unauthorized'), :forbidden
  end

  context 'when the vulnerability has no AI flag' do
    let(:subject_vulnerability) { create(:vulnerability, :with_finding, project: project) }

    it_behaves_like 'an error without an event',
      s_('SecurityAiFlowFeedback|No AI assessment is available for this vulnerability'),
      :no_ai_assessment

    context 'when it only has a manual flag' do
      before do
        create(:vulnerabilities_flag, :false_positive,
          finding: subject_vulnerability.finding, origin: 'manual_123', status: :dismissed)
      end

      it_behaves_like 'an error without an event',
        s_('SecurityAiFlowFeedback|No AI assessment is available for this vulnerability'),
        :no_ai_assessment
    end

    context 'when its AI flag has no verdict' do
      before do
        create(:vulnerabilities_flag, :false_positive,
          finding: subject_vulnerability.finding,
          origin: Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN,
          status: :failed)
      end

      it_behaves_like 'an error without an event',
        s_('SecurityAiFlowFeedback|No AI assessment is available for this vulnerability'),
        :no_ai_assessment
    end
  end

  context 'when the vulnerability has no finding' do
    let(:subject_vulnerability) { build_stubbed(:vulnerability, project: project) }

    before do
      allow(subject_vulnerability).to receive(:finding).and_return(nil)
    end

    it_behaves_like 'an error without an event',
      s_('SecurityAiFlowFeedback|No AI assessment is available for this vulnerability'),
      :no_ai_assessment
  end

  context 'when the finding also has an older manual flag' do
    let(:subject_vulnerability) { create(:vulnerability, :with_finding, project: project) }
    let!(:ai_flag) do
      create(:vulnerabilities_flag, :false_positive,
        finding: subject_vulnerability.finding,
        origin: Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN,
        status: :detected_as_not_fp,
        updated_at: 1.hour.ago)
    end

    before do
      create(:vulnerabilities_flag, :false_positive,
        finding: subject_vulnerability.finding, origin: 'manual_123', status: :dismissed, updated_at: 2.hours.ago)
    end

    it 'gives feedback on the newer AI flag' do
      expect(execute.payload[:flag]).to eq(ai_flag)
      expect(execute.payload[:event_properties]).to include(flag_id: ai_flag.id, ai_verdict: 'detected_as_not_fp')
    end

    context 'when a newer manual flag replaced the AI verdict' do
      before do
        create(:vulnerabilities_flag, :false_positive,
          finding: subject_vulnerability.finding, origin: 'manual_456', status: :dismissed)
      end

      it 'rejects the feedback' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:no_ai_assessment)
      end
    end
  end

  context 'when the user is throttled' do
    before do
      allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:security_ai_flow_feedback_create, scope: { user: user })
        .and_return(true)
    end

    it_behaves_like 'an error without an event',
      s_('SecurityAiFlowFeedback|You have submitted feedback too many times. Please try again later.'), :throttled
  end

  context 'with invalid input' do
    context 'when the sentiment is unknown' do
      let(:sentiment) { 'meh' }

      it_behaves_like 'an error without an event', s_('SecurityAiFlowFeedback|Sentiment is invalid'), :invalid
    end

    context 'when reasons are given with an agree sentiment' do
      let(:sentiment) { 'agree' }

      it_behaves_like 'an error without an event',
        s_('SecurityAiFlowFeedback|Reasons are only allowed when the sentiment is disagree'), :invalid
    end

    context 'when a reason is unknown' do
      let(:reasons) { %w[verdict_wrong made_up] }

      it_behaves_like 'an error without an event',
        s_('SecurityAiFlowFeedback|Reasons contain an invalid value'), :invalid
    end
  end
end
