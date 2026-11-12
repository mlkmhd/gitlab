# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Releases::EvidencePipelineFinder, '#execute', feature_category: :release_evidence do
  let(:params) { {} }
  let_it_be(:project) { create(:project, :repository) }
  let(:tag_name) { project.repository.tag_names.first }
  let(:sha) { project.repository.find_tag(tag_name).dereferenced_target.sha }
  let!(:pipeline) { create(:ci_pipeline, sha: sha, project: project) }

  subject { described_class.new(project, params).execute }

  context 'when the tag is passed' do
    let(:params) { { tag: tag_name } }

    it 'returns the evidence pipeline' do
      expect(subject).to eq(pipeline)
    end

    it 'looks up the pipeline under the fast read timeout on the CI connection' do
      expect(Ci::ApplicationRecord).to receive(:with_fast_read_statement_timeout).and_call_original

      expect(subject).to eq(pipeline)
    end

    context 'when the project features are not loaded yet' do
      subject { described_class.new(Project.find(project.id), params).execute }

      before do
        # Creating the pipeline sticks the session to the primary, and a new job starts without that
        Gitlab::Database::LoadBalancing::SessionMap.clear_session
      end

      it 'returns the evidence pipeline' do
        expect(subject).to eq(pipeline)
      end
    end

    context 'when the lookup times out' do
      before do
        allow(Ci::ApplicationRecord).to receive(:with_fast_read_statement_timeout)
          .and_raise(ActiveRecord::QueryCanceled)
      end

      it 'returns nil and logs the timeout' do
        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(ActiveRecord::QueryCanceled), Labkit::Fields::GL_PROJECT_ID => project.id)

        expect(subject).to be_nil
      end
    end

    context 'when release_evidence_bounded_pipeline_lookup is disabled' do
      before do
        stub_feature_flags(release_evidence_bounded_pipeline_lookup: false)
      end

      it 'returns the evidence pipeline without the fast read timeout' do
        expect(Ci::ApplicationRecord).not_to receive(:with_fast_read_statement_timeout)

        expect(subject).to eq(pipeline)
      end
    end
  end

  context 'when the ref is passed' do
    let(:params) { { ref: sha } }

    it 'returns the evidence pipeline' do
      expect(subject).to eq(pipeline)
    end
  end

  context 'empty params' do
    it 'returns nil' do
      expect(subject).to be_nil
    end
  end

  # TODO: remove this with the release creation moved to it's own form https://gitlab.com/gitlab-org/gitlab/-/issues/214245
  context 'params[:evidence_pipeline] is present' do
    let(:params) { { evidence_pipeline: pipeline } }

    it 'returns the passed evidence pipeline' do
      expect(subject).to eq(pipeline)
    end
  end
end
