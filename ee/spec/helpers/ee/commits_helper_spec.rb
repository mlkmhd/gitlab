# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CommitsHelper, feature_category: :source_code_management do
  describe '#commit_list_app_data' do
    let_it_be(:user) { build_stubbed(:user) }
    let(:last_update_at) { Time.utc(2026, 11, 1, 10) }

    let(:project) { build_stubbed(:project, :repository, :mirror) }
    let(:import_state) do
      build_stubbed(:import_state, project: project, status: :finished,
        last_update_at: last_update_at, last_successful_update_at: last_update_at)
    end

    let(:can_push) { true }
    let(:can_update_mirror) { true }
    let(:pull_mirror) { ::Gitlab::Json::SafeParser.parse(helper.commit_list_app_data['pull_mirror']) }

    before do
      assign(:project, project)
      assign(:ref, 'master')

      allow(project).to receive_messages(import_state: import_state, default_branch: 'master')
      allow(helper).to receive_messages(current_user: user, rss_url_options: { format: :atom })
      allow(helper).to receive(:path_to_browse_file_or_directory).and_return('/browse')
      allow(helper).to receive(:can?).with(user, :push_code, project).and_return(can_push)
      allow(helper).to receive(:can?).with(user, :create_pull_mirror, project).and_return(can_update_mirror)
    end

    it 'includes the pull mirror status' do
      expect(pull_mirror).to eq(
        'url' => project.safe_import_url,
        'update_status' => 'success',
        'last_update_at' => last_update_at.iso8601,
        'last_successful_update_at' => last_update_at.iso8601,
        'ever_updated_successfully' => true,
        'hard_failed' => false,
        'update_scheduled' => false,
        'updating' => false,
        'can_update' => true,
        'settings_path' => "/#{project.full_path}/-/mirror"
      )
    end

    context 'when the project is not a pull mirror' do
      let(:project) { build_stubbed(:project, :repository) }

      it 'does not include pull mirror data' do
        expect(helper.commit_list_app_data).not_to have_key('pull_mirror')
      end
    end

    context 'when the repository is read-only' do
      before do
        allow(project).to receive(:repository_read_only?).and_return(true)
      end

      it 'reports the read-only status' do
        expect(pull_mirror['update_status']).to eq('read_only')
      end
    end

    context 'when the user can push but cannot update the mirror' do
      let(:can_update_mirror) { false }

      it 'does not allow updating the mirror' do
        expect(pull_mirror['can_update']).to be(false)
      end
    end

    context 'when the mirror has never updated' do
      let(:import_state) do
        build_stubbed(:import_state, project: project, status: :none,
          last_update_at: nil, last_successful_update_at: nil)
      end

      it 'leaves the update times empty' do
        expect(pull_mirror).to include(
          'last_update_at' => nil,
          'last_successful_update_at' => nil,
          'ever_updated_successfully' => false
        )
      end
    end

    context 'when the user cannot push code' do
      let(:can_push) { false }

      it 'does not include pull mirror data' do
        expect(helper.commit_list_app_data).not_to have_key('pull_mirror')
      end
    end
  end
end
