# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'admin/application_settings/_duo_code_review_settings', feature_category: :duo_chat do
  # view.render is used here because `render` throws a "no implicit conversion of nil into String" exception
  # on admin templates with gitlab_ui_form_for.
  # See: https://gitlab.com/gitlab-org/gitlab/-/merge_requests/53093#note_499060593
  subject(:rendered) { view.render('admin/application_settings/duo_code_review_settings') }

  let_it_be(:user) { build_stubbed(:admin) }
  let(:app_settings) { build(:application_setting) }

  before do
    # Set directly on view to ensure visibility with view.render
    view.instance_variable_set(:@application_setting, app_settings)
    allow(view).to receive_messages(current_user: user, expanded_by_default?: true)
  end

  context 'when duo_features_enabled is false' do
    before do
      allow(app_settings).to receive(:duo_features_enabled).and_return(false)
    end

    it 'renders nothing' do
      expect(rendered).to be_nil
    end
  end

  context 'when duo_features_enabled is true' do
    before do
      allow(app_settings).to receive(:duo_features_enabled).and_return(true)
    end

    context 'when automatic review is available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(app_settings).and_return(true)
      end

      it 'renders the settings section' do
        expect(rendered).to have_content 'GitLab Duo Code Review'
      end

      it 'renders an enabled checkbox' do
        expect(rendered).not_to have_css('input[name="application_setting[auto_duo_code_review_enabled]"][disabled]')
      end

      it 'renders the auto_duo_code_review_on_push_enabled checkbox' do
        expect(rendered).to have_css('input[name="application_setting[auto_duo_code_review_on_push_enabled]"]')
      end
    end

    context 'when automatic review is not available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(app_settings).and_return(false)
      end

      it 'renders the settings section' do
        expect(rendered).to have_content 'GitLab Duo Code Review'
      end

      it 'renders a disabled checkbox with a help link', :aggregate_failures do
        expect(rendered).to have_css('input[name="application_setting[auto_duo_code_review_enabled]"][disabled]')
        expect(rendered).to have_content 'Requires the Code Review foundational flow to be enabled'
      end
    end

    context 'when the depth settings are available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:depth_settings_available?).with(app_settings).and_return(true)
      end

      it 'renders the allow deep reviews checkbox and the depth level radios', :aggregate_failures do
        expect(rendered).to have_css(
          "input[type=checkbox][name='application_setting[duo_code_review_depth_allowed]']"
        )
        expect(rendered).to have_css(
          "input[type=radio][name='application_setting[duo_code_review_default_depth]']", count: 2
        )
      end

      it 'renders a Beta badge in the allow deep reviews label' do
        expect(rendered).to have_css('label', text: /Allow deep reviews\s+Beta/)
      end
    end

    context 'when the depth settings are not available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:depth_settings_available?).with(app_settings).and_return(false)
      end

      it 'does not render the depth settings' do
        expect(rendered).not_to have_content('Depth level')
      end
    end
  end
end
