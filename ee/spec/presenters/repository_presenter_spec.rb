# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RepositoryPresenter, feature_category: :source_code_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { build_stubbed(:project, :repository) }

  let(:repository) { project.repository }
  let(:presenter) { described_class.new(repository) }

  describe '#code_owners_path' do
    context 'when repository is empty' do
      it 'returns nil' do
        expect(presenter.code_owners_path(ref: 'master')).to be_nil
      end
    end

    context 'when repository is not empty' do
      before do
        allow(repository).to receive(:empty?).and_return(false)
      end

      context 'when there is no code owners file' do
        it 'returns nil' do
          expect(presenter.code_owners_path(ref: 'master')).to be_nil
        end
      end

      context 'when no ref is passed' do
        before do
          allow(repository).to receive(:code_owners_blob)
          allow(repository).to receive(:root_ref).and_return('root_ref')
          presenter.code_owners_path
        end

        it 'uses the root_ref' do
          expect(repository).to have_received(:code_owners_blob).with(ref: 'root_ref')
        end
      end

      context 'when a CODEOWNERS file exists' do
        let(:blob) { Gitlab::Git::Blob.new(path: 'docs/CODEOWNERS') }

        before do
          allow(repository)
            .to receive(:code_owners_blob).with(ref: 'with-codeowners')
            .and_return(blob)
        end

        it 'returns the correct path' do
          expect(presenter.code_owners_path(ref: 'with-codeowners'))
            .to eq("/#{project.full_path}/-/blob/with-codeowners/docs/CODEOWNERS")
        end
      end
    end
  end

  describe '#diverged_from_upstream' do
    subject { presenter.diverged_from_upstream(ref: 'master') }

    where(:mirror, :ever_updated_successfully, :diverged, :expected) do
      false | true  | true  | false
      true  | false | true  | false
      true  | true  | false | false
      true  | true  | true  | true
    end

    with_them do
      before do
        allow(project).to receive_messages(
          mirror?: mirror,
          mirror_ever_updated_successfully?: ever_updated_successfully
        )
        allow(repository).to receive(:diverged_from_upstream?).with('master').and_return(diverged)
      end

      it { is_expected.to be(expected) }
    end
  end
end
