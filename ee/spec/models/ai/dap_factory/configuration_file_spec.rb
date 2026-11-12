# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DapFactory::ConfigurationFile, :use_clean_rails_memory_store_caching,
  feature_category: :dap_triggers do
  let_it_be(:path) { Gitlab::Ai::DapFactory::Configuration::PATH }
  let_it_be(:project) { create(:project, :custom_repo, files: { 'README.md' => 'readme' }) }
  let_it_be(:user) { project.creator }

  subject(:file) { described_class.new(project) }

  def commit_file(project, path, content, message)
    project.repository.create_file(user, path, content, message: message, branch_name: project.default_branch)
  end

  it 'exposes the fixed path and the default branch of the project' do
    expect(file).to have_attributes(path: path, default_branch: project.default_branch)
  end

  context 'when the file does not exist' do
    it 'reports no content, commit, or validation' do
      expect(file).to have_attributes(
        exists?: false, content: nil, last_commit_id: nil, validation: nil, errors: [], warnings: []
      )
    end
  end

  context 'when the project has no default branch' do
    before do
      allow(project).to receive(:default_branch).and_return(nil)
    end

    it 'reports the file as missing' do
      expect(file).to have_attributes(exists?: false, content: nil, last_commit_id: nil)
    end
  end

  context 'when the file exists' do
    let_it_be(:project) { create(:project, :custom_repo, files: { 'README.md' => 'readme' }) }
    let_it_be(:content) { "factory: [test]\nowner: me\n" }
    let_it_be(:file_commit_id) { commit_file(project, path, content, 'Add factory') }
    let_it_be(:head_commit_id) { commit_file(project, 'other.txt', 'other', 'Touch another file') }

    it 'reads the content and the last commit that touched the file' do
      expect(head_commit_id).not_to eq(file_commit_id)
      expect(file).to have_attributes(exists?: true, content: content, last_commit_id: file_commit_id)
    end

    it 'validates the content against the project' do
      expect(file.validation).not_to be_valid
      expect(file.errors.map(&:code)).to contain_exactly(:invalid_factory)
      expect(file.warnings.map(&:path)).to contain_exactly('owner')
    end
  end

  context 'when the file is larger than the validator accepts' do
    let_it_be(:project) { create(:project, :custom_repo, files: { 'README.md' => 'readme' }) }

    before_all do
      commit_file(project, path, "factory: #{'a' * Gitlab::Ai::DapFactory::Validator::MAX_BYTES}", 'Add factory')
    end

    it 'withholds the content and rejects the file, without reporting it as missing' do
      expect(file).to have_attributes(exists?: true, content: nil)
      expect(file.last_commit_id).to be_present
      expect(file.errors.map(&:code)).to contain_exactly(:too_large)
    end
  end

  describe '#last_sync' do
    it 'is nil when the file was never synced' do
      expect(file.last_sync).to be_nil
    end

    it 'returns the last Sync result of the project' do
      Ai::DapFactory::SyncResult.new(status: 'synced', commit_sha: 'abc123', synced_at: Time.current)
        .save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save

      expect(file.last_sync).to have_attributes(status: 'synced', commit_sha: 'abc123')
    end
  end
end
