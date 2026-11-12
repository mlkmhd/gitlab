# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::SecurityAiFlowFeedbacks::MetadataBuilder, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:scanner) { create(:vulnerabilities_scanner, project: project, external_id: 'semgrep', vendor: 'GitLab') }
  let_it_be(:rule_identifier) do
    create(:vulnerabilities_identifier, project: project, external_type: 'semgrep_id', external_id: 'rules.sqli',
      name: 'Semgrep rule', url: 'https://semgrep.dev/r/rules.sqli')
  end

  let_it_be(:cwe_identifier) do
    create(:vulnerabilities_identifier, project: project, external_type: 'cwe', external_id: '89', name: 'CWE-89')
  end

  let_it_be(:owasp_identifier) do
    create(:vulnerabilities_identifier, project: project, external_type: 'owasp', external_id: 'A03:2021',
      name: 'A03:2021 - Injection')
  end

  let_it_be(:workflow) do
    create(:duo_workflows_workflow,
      project: project,
      flow_metadata_json: {
        flow_id: 'sast_fp_detection', flow_version: '1.2.0'
      }.to_json,
      model_metadata_json: { provider: 'gitlab', name: 'claude_sonnet', identifier: 'claude-sonnet-4' }.to_json)
  end

  let(:file_path) { 'app/secret_service/handlers/user_query.rb' }
  let(:details) do
    {
      code_flows: {
        name: 'Code Flows',
        type: 'code-flows',
        items: [[{
          file_location: { file_name: file_path, line_start: 1, type: 'file-location' },
          node_type: 'source',
          type: 'code-flow-node'
        }]]
      }
    }
  end

  let(:finding) do
    create(:vulnerabilities_finding,
      project: project,
      report_type: :sast,
      severity: :high,
      scanner: scanner,
      primary_identifier: rule_identifier,
      identifiers: [rule_identifier, cwe_identifier, owasp_identifier],
      details: details,
      raw_metadata: { location: { file: file_path, start_line: 3 } }.to_json)
  end

  let(:origin) { Vulnerabilities::Flag::AI_SAST_FP_DETECTION_ORIGIN }
  let(:flag_workflow) { workflow }
  let(:flag) do
    create(:vulnerabilities_flag, :false_positive,
      finding: finding,
      origin: origin,
      status: :detected_as_fp,
      confidence_score: 0.85,
      workflow: flag_workflow)
  end

  let(:extras) { {} }

  subject(:builder) { described_class.new(flag, extras: extras) }

  describe '#build' do
    subject(:metadata) { builder.build }

    it 'snapshots the allowlisted finding and flow metadata' do
      expect(metadata).to eq(
        cwe: 'CWE-89',
        owasp: 'A03:2021',
        severity: 'high',
        report_type: 'sast',
        scanner_external_id: 'semgrep',
        scanner_vendor: 'GitLab',
        rule_identifier_type: 'semgrep_id',
        file_extension: 'rb',
        has_data_flow: true,
        ai_confidence_score: 0.85,
        ai_verdict: 'detected_as_fp',
        flow_version: '1.2.0',
        model_name: 'claude-sonnet-4',
        model_provider: 'gitlab'
      )
    end

    it 'never includes the file path, rule ID, rule URL, or identifier names' do
      values = metadata.values.map(&:to_s)

      expect(values).not_to include(a_string_including('rules.sqli'))
      expect(values).not_to include(a_string_including('secret_service'))
      expect(values).not_to include(a_string_including('user_query'))
      expect(values).not_to include(a_string_including('semgrep.dev'))
      expect(values).not_to include('Semgrep rule', 'A03:2021 - Injection')
    end

    context 'when the finding has no code flows' do
      let(:details) { { url: { name: 'URL', type: 'url', href: 'http://site.com' } } }

      it { is_expected.to include(has_data_flow: false) }
    end

    context 'when the finding has no file' do
      let(:file_path) { nil }
      let(:details) { { url: { name: 'URL', type: 'url', href: 'http://site.com' } } }

      it { is_expected.to include(file_extension: nil) }
    end

    context 'when the file has no extension' do
      let(:file_path) { 'Dockerfile' }

      it { is_expected.to include(file_extension: nil) }
    end

    context 'when the file extension is not a short alphanumeric value' do
      where(:file_path) do
        ['app/report.customer-acme', 'app/archive.verylongextension', 'app/notes.ext_1']
      end

      with_them do
        it { is_expected.to include(file_extension: 'other') }
      end
    end

    context 'when the file extension is uppercase' do
      let(:file_path) { 'app/Main.JAVA' }

      it { is_expected.to include(file_extension: 'java') }
    end

    context 'when the scanner is not from GitLab' do
      let(:scanner) do
        create(:vulnerabilities_scanner, project: project, external_id: 'acme-internal-scanner', vendor: 'Acme Corp')
      end

      let(:rule_identifier) do
        create(:vulnerabilities_identifier, project: project, external_type: 'acme_rule',
          external_id: 'acme.payments.secret-rule')
      end

      it 'replaces the scanner and rule fields with custom' do
        expect(metadata).to include(
          scanner_external_id: 'custom',
          scanner_vendor: 'custom',
          rule_identifier_type: 'custom'
        )
        expect(metadata.values.map(&:to_s)).not_to include(a_string_including('acme'))
      end
    end

    context 'when a report claims the GitLab vendor with names GitLab analyzers do not use' do
      let(:scanner) do
        create(:vulnerabilities_scanner, project: project, external_id: 'acme-internal-scanner', vendor: 'GitLab')
      end

      let(:rule_identifier) do
        create(:vulnerabilities_identifier, project: project, external_type: 'acme_rule',
          external_id: 'acme.payments.secret-rule')
      end

      it 'replaces the scanner and rule identifier type with custom' do
        expect(metadata).to include(
          scanner_external_id: 'custom',
          scanner_vendor: 'GitLab',
          rule_identifier_type: 'custom'
        )
        expect(metadata.values.map(&:to_s)).not_to include(a_string_including('acme'))
      end
    end

    context 'when the CWE and OWASP identifiers do not match the standard patterns' do
      let(:cwe_identifier) do
        create(:vulnerabilities_identifier, project: project, external_type: 'cwe', external_id: 'acme',
          name: 'CWE-acme-internal')
      end

      let(:owasp_identifier) do
        create(:vulnerabilities_identifier, project: project, external_type: 'owasp', external_id: 'Acme Top 10',
          name: 'Acme Top 10')
      end

      let(:owasp_2017_identifier) do
        create(:vulnerabilities_identifier, project: project, external_type: 'owasp', external_id: 'A1:2017',
          name: 'A1:2017 - Injection')
      end

      let(:finding) do
        create(:vulnerabilities_finding,
          project: project,
          scanner: scanner,
          primary_identifier: rule_identifier,
          identifiers: [rule_identifier, cwe_identifier, owasp_identifier, owasp_2017_identifier])
      end

      it 'drops the non-matching values' do
        expect(metadata).to include(cwe: nil, owasp: 'A1:2017')
      end
    end

    context 'when the flag is from secret detection' do
      let(:origin) { Vulnerabilities::Flag::AI_SECRET_DETECTION_FP_DETECTION_ORIGIN }
      let(:finding) { create(:vulnerabilities_finding, :with_secret_detection, project: project) }

      it 'snapshots the secret detection finding' do
        expect(metadata).to include(report_type: 'secret_detection', severity: 'critical', file_extension: 'py')
      end
    end

    context 'when the workflow uses a self-hosted model' do
      let(:flag_workflow) do
        create(:duo_workflows_workflow,
          project: project,
          model_metadata_json: {
            provider: 'openai',
            name: 'acme-private-llm',
            endpoint: 'https://llm.acme.internal/v1',
            api_key: 'secret-api-key',
            identifier: 'acme/custom-model'
          }.to_json)
      end

      it 'emits self_hosted and none of the model metadata' do
        expect(metadata).to include(model_name: 'self_hosted', model_provider: 'self_hosted')

        values = metadata.values.map(&:to_s)
        %w[acme llm.acme.internal secret-api-key openai].each do |leaked|
          expect(values).not_to include(a_string_including(leaked))
        end
      end
    end

    context 'when the flag has no workflow' do
      let(:flag_workflow) { nil }

      it 'leaves the flow metadata empty' do
        expect(metadata).to include(flow_version: nil, model_name: nil, model_provider: nil)
      end

      context 'when a matching triggered workflow exists for the finding' do
        before do
          create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding,
            workflow: create(:duo_workflows_workflow, project: project), workflow_name: :sast_fp_detection)
          create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding,
            workflow: workflow, workflow_name: :sast_fp_detection)
          create(:vulnerability_triggered_workflow, :resolve_sast_vulnerability, vulnerability_occurrence: finding,
            workflow: create(:duo_workflows_workflow, project: project))
        end

        it 'uses the latest workflow with the matching name' do
          expect(builder.workflow).to eq(workflow)
          expect(metadata).to include(flow_version: '1.2.0', model_name: 'claude-sonnet-4')
        end
      end

      context 'when a newer triggered workflow was created after the flag was written' do
        let(:later_workflow) { create(:duo_workflows_workflow, project: project) }

        before do
          flag.update_columns(updated_at: 2.hours.ago)

          create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding,
            workflow: later_workflow, workflow_name: :sast_fp_detection, created_at: 1.hour.ago)
          create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding,
            workflow: workflow, workflow_name: :sast_fp_detection, created_at: 3.hours.ago)
        end

        it 'uses the latest workflow created at or before the flag write' do
          expect(builder.workflow).to eq(workflow)
        end
      end
    end

    context 'when the workflow metadata is invalid JSON' do
      let(:flag_workflow) do
        create(:duo_workflows_workflow, project: project, flow_metadata_json: '{invalid', model_metadata_json: '[1]')
      end

      it 'tolerates it' do
        expect(metadata).to include(flow_version: nil, model_name: nil)
      end
    end

    context 'with extras' do
      let(:extras) { { dismissal_reason: 'false_positive', file_path: 'app/a.rb' } }

      it 'keeps only allowlisted extras' do
        expect(metadata).to include(dismissal_reason: 'false_positive')
        expect(metadata).not_to have_key(:file_path)
      end
    end
  end

  describe '#flow_type' do
    it { expect(builder.flow_type).to eq('sast_fp_detection') }

    context 'when the flag is from secret detection' do
      let(:origin) { Vulnerabilities::Flag::AI_SECRET_DETECTION_FP_DETECTION_ORIGIN }

      it { expect(builder.flow_type).to eq('secrets_fp_detection') }
    end

    context 'when the flag is not from an AI flow' do
      let(:origin) { 'manual_123' }

      it { expect(builder.flow_type).to be_nil }
    end
  end
end
