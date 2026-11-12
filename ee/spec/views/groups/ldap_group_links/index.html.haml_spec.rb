# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/ldap_group_links/index', feature_category: :user_management do
  let_it_be(:user) { build_stubbed(:user) }
  let_it_be(:ldap_group_link) { build_stubbed(:ldap_group_link) }
  let_it_be(:group) { build_stubbed(:group, ldap_group_links: [ldap_group_link]) }

  let(:can_create) { true }
  let(:can_delete) { true }

  before do
    assign(:group, group)
    allow(view).to receive(:current_user).and_return(user)
    allow(view).to receive(:can?).and_call_original
    allow(view).to receive(:can?).with(user, :create_ldap_group_link, group).and_return(can_create)
    allow(view).to receive(:can?).with(user, :delete_ldap_group_link, group).and_return(can_delete)
  end

  it 'renders the add form and the remove buttons' do
    render

    expect(rendered).to have_css('[data-testid="add-sync-button"]')
    expect(rendered).to have_link(_('Remove'))
  end

  context 'when the user cannot create LDAP group links' do
    let(:can_create) { false }

    it 'does not render the add form' do
      render

      expect(rendered).not_to have_css('[data-testid="add-sync-button"]')
      expect(rendered).to have_link(_('Remove'))
    end
  end

  context 'when the user cannot delete LDAP group links' do
    let(:can_delete) { false }

    it 'does not render the remove buttons' do
      render

      expect(rendered).to have_css('[data-testid="add-sync-button"]')
      expect(rendered).not_to have_link(_('Remove'))
    end
  end
end
