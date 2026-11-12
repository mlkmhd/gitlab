# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::UserAuthorizer, feature_category: :ai_abstraction_layer do
  describe '.for' do
    let_it_be(:user) { create(:user) }
    let_it_be(:other_user) { create(:user) }

    context 'with a request store', :request_store do
      it 'returns the same instance for the same user' do
        authorizer = described_class.for(user)

        expect(described_class.for(user)).to equal(authorizer)
      end

      it 'returns different instances for different users' do
        authorizer = described_class.for(user)

        expect(described_class.for(other_user)).not_to equal(authorizer)
      end
    end

    context 'without a request store' do
      it 'returns a new instance on each call' do
        authorizer = described_class.for(user)

        expect(described_class.for(user)).not_to equal(authorizer)
      end
    end

    context 'when the user has no id' do
      let(:user) { build(:user) }

      it 'returns a new instance on each call', :request_store do
        authorizer = described_class.for(user)

        expect(described_class.for(user)).not_to equal(authorizer)
      end
    end

    context 'when the user is nil' do
      it 'returns a new instance', :request_store do
        expect(described_class.for(nil)).to be_a(described_class)
      end
    end
  end

  describe '#any_group_with_mcp_server_enabled?', :saas, :use_clean_rails_redis_caching do
    let_it_be(:user) { create(:user) }

    subject(:group_with_mcp_server_enabled) { described_class.new(user).any_group_with_mcp_server_enabled? }

    context 'when user is not member of any group' do
      it { is_expected.to be(false) }
    end

    context 'when the user is a member of a group' do
      let_it_be(:user, freeze: false) { create(:user) }
      let_it_be(:group, freeze: false) { create(:group) }

      before_all do
        group.add_developer(user)
      end

      before do
        allow(user).to receive(:authorized_root_ancestor_ids).and_return([group.id])
      end

      context 'when group has mcp_server_enabled = true' do
        before do
          allow(Group).to receive(:with_mcp_server_enabled).and_return(
            Group.where(id: group.id)
          )
        end

        it 'returns true' do
          expect(described_class.new(user).any_group_with_mcp_server_enabled?).to be true
        end

        it 'caches the result with the MCP server cache key' do
          described_class.new(user).any_group_with_mcp_server_enabled?

          expect(
            Rails.cache.fetch(['users', user.id, described_class::GROUP_WITH_MCP_SERVER_ENABLED_CACHE_KEY])
          ).to be true
        end
      end

      context 'when group has mcp_server_enabled = false' do
        before do
          allow(Group).to receive(:with_mcp_server_enabled).and_return(Group.none)
        end

        it 'returns false' do
          expect(described_class.new(user).any_group_with_mcp_server_enabled?).to be false
        end
      end

      it 'uses the expected cache key' do
        expect(described_class::GROUP_WITH_MCP_SERVER_ENABLED_CACHE_KEY).to eq('group_with_mcp_server_enabled')
      end

      it 'uses the expected cache period' do
        expect(described_class::GROUP_WITH_MCP_SERVER_ENABLED_CACHE_PERIOD).to eq(1.hour)
      end
    end
  end

  describe '#eligible_for_self_managed_gitlab_duo_pro?' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:active_user) { create(:user) }
    let_it_be(:bot) { create(:user, :bot) }
    let_it_be(:ghost) { create(:user, :ghost) }
    let_it_be(:blocked_user) { create(:user, :blocked) }
    let_it_be(:banned_user) { create(:user, :banned) }
    let_it_be(:pending_approval_user) { create(:user, :blocked_pending_approval) }
    let_it_be(:group) { create(:group) }
    let_it_be(:guest_user) { create(:group_member, :guest, source: group).user }

    subject { described_class.new(user).eligible_for_self_managed_gitlab_duo_pro? }

    context 'when on gitlab.com', :saas_gitlab_com_subscriptions do
      let(:user) { active_user }

      it { is_expected.to be(false) }
    end

    context 'when on self managed' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      # True for human users, excluding bots, blocked, banned, and pending_approval users.
      where(:user, :result) do
        ref(:bot)                     | false
        ref(:ghost)                   | false
        ref(:blocked_user)            | false
        ref(:banned_user)             | false
        ref(:pending_approval_user)   | false
        ref(:active_user)             | true
        ref(:guest_user)              | true
      end

      with_them do
        it { is_expected.to eq(result) }
      end
    end
  end

  describe '#gitlab_com_root_group_ids', :use_clean_rails_redis_caching do
    using RSpec::Parameterized::TableSyntax

    let_it_be_with_refind(:user) { create(:user) }
    let_it_be(:root_group) { create(:group) }
    let_it_be(:sub_group) { create(:group, parent: root_group) }
    let_it_be(:group_project) { create(:project, group: root_group) }
    let_it_be(:sub_group_project) { create(:project, group: sub_group) }

    subject { described_class.new(user).gitlab_com_root_group_ids }

    context 'when on gitlab.com', :saas_gitlab_com_subscriptions do
      shared_examples 'excludes root group ids for banned user' do
        context 'when the user is banned' do
          let(:result) { [] }

          before do
            create(:namespace_ban, namespace: root_group, user: user)
          end

          it { is_expected.to eq(result) }
        end
      end

      where(:access_level, :include_group) do
        :guest      | true
        :reporter   | true
        :developer  | true
        :maintainer | true
        :owner      | true
      end

      with_them do
        let(:result) { include_group ? [root_group.id] : [] }

        context 'when the user is a member of the top level group' do
          before do
            root_group.add_member(user, access_level)
          end

          it { is_expected.to eq(result) }

          it 'caches the result' do
            described_class.new(user).gitlab_com_root_group_ids

            expect(
              Rails.cache.fetch(['users', user.id, described_class::ROOT_GROUP_IDS_CACHE_KEY])
            ).to eq(result)
          end
        end

        context 'when the user is a member of a sub group of the top level group' do
          before do
            sub_group.add_member(user, access_level)
          end

          it { is_expected.to eq(result) }

          it_behaves_like 'excludes root group ids for banned user'
        end

        context 'when the user is a member of a project within the top level group' do
          before do
            group_project.add_member(user, access_level)
          end

          it { is_expected.to eq(result) }

          it_behaves_like 'excludes root group ids for banned user'
        end

        context 'when the user is a member of a project within a sub group of the top level group' do
          before do
            sub_group_project.add_member(user, access_level)
          end

          it { is_expected.to eq(result) }

          it_behaves_like 'excludes root group ids for banned user'
        end
      end
    end

    context 'when on self managed' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#default_duo_namespace' do
    let_it_be(:user) { create(:user) }

    subject(:default_duo_namespace) { described_class.new(user).default_duo_namespace }

    it 'delegates to user_preference.duo_default_namespace_with_fallback' do
      expect(user.user_preference).to receive(:duo_default_namespace_with_fallback)

      default_duo_namespace
    end
  end

  describe '#duo_available_namespace_ids' do
    let_it_be(:user) { create(:user) }

    subject(:duo_namespace_ids) { described_class.new(user).duo_available_namespace_ids }

    shared_examples 'returns IDs of namespaces with duo add-on' do
      let_it_be(:gitlab_duo_add_on) { create(:gitlab_subscription_add_on, add_on_type) }

      let_it_be(:expired_gitlab_duo_purchase) do
        create(:gitlab_subscription_add_on_purchase, expires_on: 1.day.ago, add_on: gitlab_duo_add_on)
      end

      let_it_be_with_reload(:active_gitlab_duo_purchase) do
        create(:gitlab_subscription_add_on_purchase, add_on: gitlab_duo_add_on)
      end

      context 'when the user has an active assigned duo seat' do
        it 'returns the namespace ID' do
          create(
            :gitlab_subscription_user_add_on_assignment,
            user: user,
            add_on_purchase: active_gitlab_duo_purchase
          )

          expect(duo_namespace_ids).to eq([active_gitlab_duo_purchase.namespace_id])
        end
      end

      context 'when the user belongs to multiple namespaces with an active assigned duo seat' do
        let_it_be(:active_gitlab_duo_pro_purchase_2) do
          create(:gitlab_subscription_add_on_purchase, add_on: gitlab_duo_add_on)
        end

        it 'returns the namespace IDs' do
          create(
            :gitlab_subscription_user_add_on_assignment,
            user: user,
            add_on_purchase: active_gitlab_duo_purchase
          )

          create(
            :gitlab_subscription_user_add_on_assignment,
            user: user,
            add_on_purchase: active_gitlab_duo_pro_purchase_2
          )

          expect(duo_namespace_ids)
            .to contain_exactly(active_gitlab_duo_purchase.namespace_id,
              active_gitlab_duo_pro_purchase_2.namespace_id)
        end
      end

      context 'when the user has an expired assigned duo seat' do
        it 'returns empty' do
          create(
            :gitlab_subscription_user_add_on_assignment,
            user: user,
            add_on_purchase: expired_gitlab_duo_purchase
          )

          expect(duo_namespace_ids).to be_empty
        end
      end

      context 'when the user has no add on seat assignments' do
        it 'returns empty' do
          expect(duo_namespace_ids).to be_empty
        end
      end
    end

    context 'when user has duo pro add-on' do
      it_behaves_like 'returns IDs of namespaces with duo add-on' do
        let_it_be(:add_on_type) { :duo_pro }
      end
    end

    context 'when user has duo enterprise add-on' do
      it_behaves_like 'returns IDs of namespaces with duo add-on' do
        let_it_be(:add_on_type) { :duo_enterprise }
      end
    end

    context 'when user has duo core add-on' do
      it_behaves_like 'returns IDs of namespaces with duo add-on' do
        let_it_be(:add_on_type) { :duo_core }
      end
    end
  end
end
