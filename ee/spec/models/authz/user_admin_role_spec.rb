# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::UserAdminRole, feature_category: :system_access do
  describe 'associations' do
    it { is_expected.to belong_to(:admin_role).class_name('Authz::AdminRole') }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validation' do
    subject(:user_admin_role) { build(:user_admin_role) }

    it { is_expected.to validate_presence_of(:admin_role) }
    it { is_expected.to validate_presence_of(:user) }
    it { is_expected.to validate_uniqueness_of(:user) }
  end

  describe '.with_identity_provider' do
    let_it_be(:provider) { 'ldapmain' }
    let_it_be(:user) { create(:user) }
    let_it_be(:user_admin_role) { create(:user_admin_role, user: user) }

    subject(:with_identity_provider) { described_class.with_identity_provider(provider) }

    it 'returns records for users with an identity for the provider' do
      create(:identity, user: user, provider: provider)

      expect(with_identity_provider).to eq([user_admin_role])
    end

    it 'skips users with an identity for another provider' do
      create(:identity, user: user, provider: 'jwt', extern_uid: 'jwt-uid')

      expect(with_identity_provider).to be_empty
    end
  end

  describe '.filter_users' do
    let_it_be(:user_1) { create(:user) }
    let_it_be(:user_2) { create(:user) }
    let_it_be(:user_role_1) { create(:user_admin_role, user: user_1) }
    let_it_be(:user_role_2) { create(:user_admin_role, user: user_2) }

    it 'returns the users with the admin role' do
      expect(described_class.filter_users(User.all, user_role_1.admin_role_id)).to eq([user_1])
    end
  end

  describe '.create_or_update' do
    let(:user) { create(:user) }
    let(:admin_role) { create(:admin_role) }
    let(:admin_role_2) { create(:admin_role) }

    subject(:create_or_update) { described_class.create_or_update(user: user, admin_role: admin_role) }

    context 'when a user has join record' do
      let!(:join_record) { create(:user_admin_role, user: user, admin_role: admin_role_2) }

      it 'updates the existing record with the new role' do
        expect { create_or_update }.to change {
          described_class.find_by(user: user).admin_role_id
        }.from(admin_role_2.id).to(admin_role.id)
      end

      it 'does not create a new join record' do
        expect { create_or_update }.not_to change { described_class.count }
      end
    end

    context 'with extra attributes' do
      subject(:create_or_update) { described_class.create_or_update(user: user, admin_role: admin_role, ldap: true) }

      it 'sets them on the record' do
        create_or_update

        expect(described_class.find_by(user: user).ldap).to be(true)
      end
    end

    context 'when a user has no join record' do
      it 'creates a new join record' do
        expect { create_or_update }.to change { described_class.count }.by(1)
      end

      it 'assigns the correct role to the user' do
        create_or_update

        expect(user.reload.user_admin_role.admin_role_id).to eq(admin_role.id)
      end
    end
  end
end
