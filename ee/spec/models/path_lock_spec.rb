# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PathLock, feature_category: :source_code_management do
  let_it_be(:path_lock) { create(:path_lock, path: 'app/models') }
  let_it_be(:another_path_lock) do
    create(:path_lock, path: 'app', user: path_lock.user,
      project: create(:project, namespace: path_lock.project.namespace))
  end

  let(:project) { path_lock.project }

  context 'Relations' do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:user) }
  end

  context 'Validations' do
    it { is_expected.to validate_presence_of(:user) }
    it { is_expected.to validate_presence_of(:project) }
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_uniqueness_of(:path).scoped_to(:project_id) }

    describe '#path_unique_validation' do
      it "is not valid because of upstream lock" do
        path_lock = build :path_lock, path: 'app/models/user.rb', project: project
        expect(path_lock.valid?).to be_falsey
        expect(path_lock.errors[:path].first).to match("upstream lock")
      end

      it "is not valid because of downstream lock" do
        path_lock = build :path_lock, path: 'app', project: project
        expect(path_lock.valid?).to be_falsey
        expect(path_lock.errors[:path].first).to match("downstream lock")
      end

      it "is valid when an existing lock only shares a name prefix" do
        path_lock = build :path_lock, path: 'app/mod', project: project
        expect(path_lock).to be_valid
      end
    end
  end

  describe 'downstream?' do
    it "returns true" do
      expect(path_lock.downstream?("app")).to be_truthy
    end

    it "returns false" do
      expect(path_lock.downstream?("app/models")).to be_falsey
    end

    it "returns false" do
      expect(path_lock.downstream?("app/models/user.rb")).to be_falsey
    end
  end

  describe 'upstream?' do
    it "returns true" do
      expect(path_lock.upstream?("app/models/user.rb")).to be_truthy
    end

    it "returns false" do
      expect(path_lock.upstream?("app/models")).to be_falsey
    end

    it "returns false" do
      expect(path_lock.upstream?("app")).to be_falsey
    end
  end

  describe 'exact?' do
    it "returns true" do
      expect(path_lock.exact?("app/models")).to be_truthy
    end

    it "returns false" do
      expect(path_lock.exact?("app")).to be_falsey
    end
  end

  describe '.for_paths' do
    it 'filters path locks by passed' do
      expect(described_class.for_paths(['app'])).to eq([another_path_lock])
      expect(described_class.for_paths(['app/models'])).to eq([path_lock])
    end
  end

  describe '.related_to_path' do
    let_it_be(:project) { create(:project) }
    let_it_be(:directory_lock) { create(:path_lock, project: project, path: 'lib/gitlab') }
    let_it_be(:file_lock) { create(:path_lock, project: project, path: 'app/models/user.rb') }
    let_it_be(:sibling_prefix_lock) { create(:path_lock, project: project, path: 'app/modelsx') }

    subject(:related_locks) { project.path_locks.related_to_path(path) }

    context 'when the path is locked' do
      let(:path) { 'app/models/user.rb' }

      it { is_expected.to contain_exactly(file_lock) }
    end

    context 'when a parent directory is locked' do
      let(:path) { 'lib/gitlab/foo/bar.rb' }

      it { is_expected.to contain_exactly(directory_lock) }
    end

    context 'when a path under the directory is locked' do
      let(:path) { 'app/models' }

      it { is_expected.to contain_exactly(file_lock) }
    end

    context 'when the path ends with a slash' do
      let(:path) { 'app/models/' }

      it { is_expected.to contain_exactly(file_lock) }
    end

    context 'when no related path is locked' do
      let(:path) { 'app/controllers' }

      it { is_expected.to be_empty }
    end

    context 'when the path contains LIKE wildcards' do
      let(:path) { 'app/mo_els' }

      it { is_expected.to be_empty }
    end

    context 'when joined with projects' do
      let(:path) { 'app/models' }

      subject(:related_locks) { project.path_locks.joins(:project).related_to_path(path) }

      it { is_expected.to contain_exactly(file_lock) }
    end

    context 'when the path differs only in case' do
      let(:path) { 'App/Models' }

      it { is_expected.to be_empty }
    end
  end

  describe '#for_path' do
    it 'finds the path lock with the given path' do
      expect(described_class.for_path('app')).to eq(another_path_lock)
      expect(described_class.for_path('app/models')).to eq(path_lock)
    end
  end
end
