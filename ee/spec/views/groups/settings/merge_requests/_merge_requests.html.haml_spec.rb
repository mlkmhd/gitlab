# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/merge_requests/_merge_requests', feature_category: :chat_engine do
  let_it_be(:group) { build(:group, namespace_settings: build(:namespace_settings)) }

  before do
    assign(:group, group)
    allow(group).to receive(:licensed_feature_available?).and_return(false)
  end

  context 'when duo_features_enabled is false' do
    before do
      allow(group).to receive(:duo_features_enabled).and_return(false)
    end

    it 'does not render the Duo Code Review section' do
      render locals: { expanded: false }

      expect(rendered).not_to have_content 'GitLab Duo Code Review'
    end
  end

  context 'when duo_features_enabled is true' do
    before do
      allow(group).to receive(:duo_features_enabled).and_return(true)
    end

    context 'when automatic review is available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(group).and_return(true)
      end

      it 'renders the Duo Code Review section' do
        render locals: { expanded: false }

        expect(rendered).to have_content 'GitLab Duo Code Review'
      end

      it 'renders an enabled checkbox' do
        render locals: { expanded: false }

        expect(rendered).not_to have_css('input[name="namespace_setting[auto_duo_code_review_enabled]"][disabled]')
      end

      context 'when duo_code_review_dap_available? is true' do
        before do
          allow(group).to receive(:duo_code_review_dap_available?).and_return(true)
        end

        it 'renders the auto_duo_code_review_on_push_enabled checkbox' do
          render locals: { expanded: false }

          expect(rendered).to have_css('input[name="namespace_setting[auto_duo_code_review_on_push_enabled]"]')
        end
      end

      context 'when duo_code_review_dap_available? is false' do
        before do
          allow(group).to receive(:duo_code_review_dap_available?).and_return(false)
        end

        it 'does not render the auto_duo_code_review_on_push_enabled checkbox' do
          render locals: { expanded: false }

          expect(rendered).not_to have_css('input[name="namespace_setting[auto_duo_code_review_on_push_enabled]"]')
        end
      end
    end

    context 'when automatic review is not available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(group).and_return(false)
      end

      it 'renders the Duo Code Review section' do
        render locals: { expanded: false }

        expect(rendered).to have_content 'GitLab Duo Code Review'
      end

      it 'renders a disabled checkbox with a help link', :aggregate_failures do
        render locals: { expanded: false }

        expect(rendered).to have_css('input[name="namespace_setting[auto_duo_code_review_enabled]"][disabled]')
        expect(rendered).to have_content 'Requires the Code Review foundational flow to be enabled'
      end
    end

    context 'when the depth settings are available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(group).and_return(true)
        allow(::Gitlab::Duo::CodeReview).to receive(:depth_settings_available?).with(group).and_return(true)
      end

      it 'renders the allow deep reviews checkbox and the depth level radios', :aggregate_failures do
        render locals: { expanded: false }

        expect(rendered).to have_css(
          'input[type=checkbox][name="namespace_setting[duo_code_review_depth_allowed]"]'
        )
        expect(rendered).to have_css(
          'input[type=radio][name="namespace_setting[duo_code_review_default_depth]"]', count: 2
        )
      end

      it 'renders a Beta badge in the allow deep reviews label' do
        render locals: { expanded: false }

        expect(rendered).to have_css('label', text: /Allow deep reviews\s+Beta/)
      end
    end

    context 'when the depth settings are not available' do
      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:automatic_review_available?).with(group).and_return(true)
        allow(::Gitlab::Duo::CodeReview).to receive(:depth_settings_available?).with(group).and_return(false)
      end

      it 'does not render the depth settings' do
        render locals: { expanded: false }

        expect(rendered).not_to have_content('Depth level')
      end
    end
  end
end
