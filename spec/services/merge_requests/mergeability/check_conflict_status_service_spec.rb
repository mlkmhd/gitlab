# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::Mergeability::CheckConflictStatusService, feature_category: :code_review_workflow do
  using RSpec::Parameterized::TableSyntax

  subject(:check_conflict_status) { described_class.new(merge_request: merge_request, params: {}) }

  let(:merge_request) { build(:merge_request, merge_status: merge_status) }
  let(:merge_status) { :can_be_merged }

  it_behaves_like 'mergeability check service', :conflict, 'Checks whether the merge request has a conflict'

  describe '#execute' do
    context 'when the source branch sha matches the diff head sha' do
      where(:merge_status, :expected) do
        :preparing | Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        :unchecked | Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        :cannot_be_merged_recheck | Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        :checking | Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        :cannot_be_merged_rechecking | Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        :can_be_merged | Gitlab::MergeRequests::Mergeability::CheckResult::SUCCESS_STATUS
        :cannot_be_merged | Gitlab::MergeRequests::Mergeability::CheckResult::FAILED_STATUS
      end

      with_them do
        let(:result) { check_conflict_status.execute }

        it 'returns the expected status' do
          expect(result.status).to eq expected
          expect(result.payload[:identifier]).to eq(:conflict)
        end
      end
    end

    context 'when the source branch sha does not match the diff head sha' do
      let(:merge_request) { build_stubbed(:merge_request) }
      let(:result) { check_conflict_status.execute }

      before do
        merge_request.source_branch_sha = '1'
      end

      it 'returns checking' do
        expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        expect(result.payload[:identifier]).to eq(:conflict)
      end
    end

    context 'when the merge request has no diff' do
      let(:merge_request) { build_stubbed(:merge_request) }
      let(:result) { check_conflict_status.execute }

      before do
        merge_request.source_branch_sha = '1'
        allow(merge_request).to receive(:merge_request_diff).and_return(nil)
      end

      it 'returns checking' do
        expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
      end
    end

    context 'with batched branch heads', :request_store do
      let_it_be_with_refind(:project) { create(:project, :repository) }
      let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
      let(:params) { { batched_branch_heads: true } }
      let(:result) { described_class.new(merge_request: merge_request, params: params).execute }

      it 'reads the source branch head from the ListRefs batch' do
        expect(merge_request).not_to receive(:source_branch_sha)

        expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::SUCCESS_STATUS
      end

      it 'returns checking when the branch moved past the diff head' do
        allow(project.repository).to receive(:batched_ref_target)
          .with(merge_request.source_branch_ref).and_return('1' * 40)

        expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
      end

      it 'looks up the source branch head when the batch has no target' do
        allow(project.repository).to receive(:batched_ref_target).and_return(nil)
        expect(merge_request).to receive(:source_branch_sha).and_call_original

        expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::SUCCESS_STATUS
      end

      it 'looks up the source branch head when the source project is gone' do
        orphan = MergeRequest.find(merge_request.id).tap { |mr| mr.source_project = nil }
        expect(orphan).to receive(:source_branch_sha).and_call_original

        expect(described_class.new(merge_request: orphan, params: params).execute.status)
          .to eq Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
      end

      context 'when the caller did not opt in' do
        let(:params) { {} }

        it 'looks up the source branch head' do
          expect(merge_request).to receive(:source_branch_sha).and_call_original

          expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::SUCCESS_STATUS
        end
      end
    end
  end

  describe '#skip?' do
    where(:skip_conflict_check, :expected) do
      nil   | false
      false | false
      true  | true
    end

    with_them do
      subject do
        described_class
          .new(merge_request: merge_request, params: { skip_conflict_check: skip_conflict_check })
          .skip?
      end

      it { is_expected.to equal expected }
    end
  end

  describe '#cacheable?' do
    it 'returns false' do
      expect(check_conflict_status.cacheable?).to be false
    end
  end
end
