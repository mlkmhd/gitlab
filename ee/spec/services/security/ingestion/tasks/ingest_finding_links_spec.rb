# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::Tasks::IngestFindingLinks, feature_category: :vulnerability_management do
  describe '#execute' do
    let(:pipeline) { create(:ci_pipeline) }
    let(:finding_link) { create(:ci_reports_security_link) }
    let(:finding_1) { create(:vulnerabilities_finding) }
    let(:finding_2) { create(:vulnerabilities_finding) }
    let(:report_finding_1) { create(:ci_reports_security_finding, links: [finding_link]) }
    let(:report_finding_2) { create(:ci_reports_security_finding, links: [finding_link]) }
    let(:finding_map_1) { create(:finding_map, finding: finding_1, report_finding: report_finding_1) }
    let(:finding_map_2) { create(:finding_map, finding: finding_2, report_finding: report_finding_2) }
    let(:service_object) { described_class.new(pipeline, [finding_map_1, finding_map_2]) }

    subject(:ingest_finding_links) { service_object.execute }

    before do
      create(:finding_link, finding: finding_2, url: finding_link.url)
    end

    it 'creates finding links for the new records' do
      expect { ingest_finding_links }.to change { Vulnerabilities::FindingLink.count }.by(1)
                                    .and change { finding_1.finding_links.count }.by(1)
    end

    # Guards gitlab-org/gitlab#603322: this task sets no `unique_by`, so it has to
    # order its own rows by the `(vulnerability_occurrence_id, name, url)` unique
    # index to keep a consistent row lock order between concurrent ingestions.
    context 'when a finding reports its links out of order' do
      let(:link_b) { create(:ci_reports_security_link, name: 'b-name', url: 'https://example.com/b') }
      let(:link_a) { create(:ci_reports_security_link, name: 'a-name', url: 'https://example.com/a') }
      let(:report_finding_1) { create(:ci_reports_security_finding, links: [link_b, link_a]) }
      let(:service_object) { described_class.new(pipeline, [finding_map_1]) }

      it 'inserts them ordered by the unique index' do
        ingest_finding_links

        expect(finding_1.finding_links.order(:id).pluck(:name)).to eq(%w[a-name b-name])
      end
    end

    it_behaves_like 'bulk insertable task'
  end
end
