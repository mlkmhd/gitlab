# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Search results for project settings", :js, feature_category: :global_search, type: :feature do
  before do
    allow(Gitlab::Saas).to receive(:feature_available?).and_call_original
    allow(Gitlab::Saas).to receive(:feature_available?).with(:repositories_web_based_commit_signing).and_return(true)

    stub_licensed_features(
      issuable_default_templates: true,
      target_branch_rules: true,
      push_rules: true,
      merge_request_approvers: true,
      protected_environments: true,
      auto_rollback: true,
      ci_project_subscriptions: true,
      status_page: true,
      observability: true,
      ai_features: true,
      review_merge_request: true
    )
  end

  it_behaves_like 'all project settings sections exist and have correct anchor links'
end

RSpec.describe Search::ProjectSettings, feature_category: :global_search do
  let_it_be(:project) { build_stubbed(:project) }

  subject(:project_settings) { described_class.new(project) }

  describe '#merge_request_settings' do
    let(:duo_code_review_text) { s_("DuoCodeReview|GitLab Duo Code Review") }

    before do
      allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(project)
        .and_return(automatic_review_available)
    end

    context 'when automatic review is available' do
      let(:automatic_review_available) { true }

      it 'includes the Duo Code Review settings' do
        setting = project_settings.merge_request_settings.find { |s| s[:text] == duo_code_review_text }

        expect(setting[:href]).to eq(
          Rails.application.routes.url_helpers.project_settings_merge_requests_path(
            project, anchor: 'merge-request-duo-code-review-settings'
          )
        )
      end
    end

    context 'when automatic review is not available' do
      let(:automatic_review_available) { false }

      it 'excludes the Duo Code Review settings' do
        expect(project_settings.merge_request_settings.pluck(:text)).not_to include(duo_code_review_text)
      end
    end
  end
end
