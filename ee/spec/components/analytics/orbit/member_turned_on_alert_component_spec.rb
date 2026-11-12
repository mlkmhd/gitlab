# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::MemberTurnedOnAlertComponent, feature_category: :knowledge_graph do
  let(:current_user) { build_stubbed(:user) }
  let(:root) { build_stubbed(:group) }
  let(:source) { root }
  let(:title) { 'GitLab Orbit is now available to your group' }

  let(:enabled_namespace) do
    build_stubbed(
      :knowledge_graph_enabled_namespace,
      created_at: (::Analytics::Orbit::MemberNotifications::DELAY + 1.hour).ago
    )
  end

  subject(:component) do
    render_inline(described_class.new(current_user: current_user, root: root, source: source))
  end

  before do
    stub_default_url_options(host: 'test.host')
    stub_saas_features(gitlab_com_subscriptions: true)
    allow(::Analytics::KnowledgeGraph).to receive(:enabled_for?).with(current_user).and_return(true)
    allow(root).to receive(:knowledge_graph_enabled_namespace).and_return(enabled_namespace)
    allow(source).to receive(:member?).with(current_user, ::Gitlab::Access::REPORTER).and_return(true)
    allow(::Analytics::Orbit::Billing).to receive(:reject_gated_root_ids_without_access)
      .with([root.id]).and_return([root.id])
    allow(current_user).to receive(:dismissed_callout_for_group?).and_return(false)
  end

  it 'renders the alert with the copy and both actions', :aggregate_failures do
    expect(component).to have_content(title)
    expect(component).to have_content('Ask questions that span projects with GitLab Duo or your own agents.')
    expect(component).to have_link('Use GitLab Orbit', href: dashboard_orbit_path(quickstart: true))
    expect(component).to have_link('Learn more', href: 'https://docs.gitlab.com/orbit/')
  end

  it 'renders the dismissible callout for the root group' do
    expect(component).to have_dismissible_callout(feature_id: 'orbit_turned_on_alert', group: root)
  end

  context 'when the user is absent' do
    let(:current_user) { nil }

    it { is_expected.not_to have_content(title) }
  end

  context 'when the user is not human' do
    before do
      allow(current_user).to receive(:human?).and_return(false)
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when not on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when the Knowledge Graph is not enabled for the user' do
    before do
      allow(::Analytics::KnowledgeGraph).to receive(:enabled_for?).with(current_user).and_return(false)
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when the group has no enabled namespace' do
    before do
      allow(root).to receive(:knowledge_graph_enabled_namespace).and_return(nil)
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when Orbit was turned on less than the delay ago' do
    before do
      allow(enabled_namespace).to receive(:created_at)
        .and_return((::Analytics::Orbit::MemberNotifications::DELAY - 1.minute).ago)
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when the user is below the Reporter role on the source' do
    before do
      allow(source).to receive(:member?).with(current_user, ::Gitlab::Access::REPORTER).and_return(false)
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when the root is gated from Orbit billing' do
    before do
      allow(::Analytics::Orbit::Billing).to receive(:reject_gated_root_ids_without_access)
        .with([root.id]).and_return([])
    end

    it { is_expected.not_to have_content(title) }
  end

  context 'when the user already dismissed the callout' do
    before do
      allow(current_user).to receive(:dismissed_callout_for_group?).and_return(true)
    end

    it { is_expected.not_to have_content(title) }
  end
end
