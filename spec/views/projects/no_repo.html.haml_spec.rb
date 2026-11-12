# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/no_repo', feature_category: :groups_and_projects do
  let_it_be(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project) }
  let(:can_remove_project) { true }

  before do
    allow(view).to receive_messages(current_user: user, can?: false)
    allow(view).to receive(:can?).with(user, :remove_project, project).and_return(can_remove_project)
    assign(:project, project)
  end

  def delete_button
    Nokogiri::HTML(rendered).at_css('#js-project-delete-button')
  end

  context 'when the user can remove the project' do
    it 'renders the delete project button' do
      render

      expect(delete_button).to be_present
      expect(delete_button['data-button-text']).to eq(_('Delete project'))
      expect(delete_button['data-form-path']).to eq(project_path(project))
      expect(delete_button['data-confirm-phrase']).to eq(project.full_path)
      expect(delete_button['data-trigger-delete-location']).to eq('no_repository')
      expect(delete_button['data-button-category']).to eq('tertiary')
    end

    it 'does not render the legacy confirm dialog' do
      render

      expect(rendered).not_to have_css('[data-confirm]')
    end

    context 'when the project is scheduled for deletion' do
      before do
        allow(project).to receive_messages(
          self_deletion_scheduled?: true,
          scheduled_for_deletion_in_hierarchy_chain?: true
        )
      end

      it 'renders the delete permanently button' do
        render

        expect(delete_button['data-button-text']).to eq(s_('ProjectSettings|Delete permanently'))
        expect(delete_button['data-form-path']).to eq(project_path(project, permanently_delete: true))
      end
    end

    context 'when an ancestor is scheduled for deletion' do
      before do
        allow(project).to receive_messages(
          self_deletion_scheduled?: false,
          scheduled_for_deletion_in_hierarchy_chain?: true
        )
      end

      it 'does not render the delete project button' do
        render

        expect(delete_button).to be_nil
      end
    end
  end

  context 'when the user cannot remove the project' do
    let(:can_remove_project) { false }

    it 'does not render the delete project button' do
      render

      expect(delete_button).to be_nil
    end
  end
end
