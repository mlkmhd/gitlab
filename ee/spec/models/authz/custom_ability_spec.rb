# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::CustomAbility, feature_category: :permissions do
  describe '.allowed?', :request_store, :enable_admin_mode do
    subject(:custom_ability) { described_class }

    let_it_be_with_reload(:user) { create(:user) }

    context 'with admin abilities', factory_default: :keep do
      before do
        stub_licensed_features(custom_roles: true)
      end

      let_it_be(:organization) { create_default(:organization) }

      admin_abilities = Gitlab::CustomRoles::Definition.admin

      admin_abilities.each_key do |ability|
        context "with #{ability}" do
          let_it_be(:role) { create(:member_role, ability) }
          let_it_be(:user_member_role) { create(:user_member_role, member_role: role, user: user) }

          it { is_expected.to be_allowed(user, ability) }
        end
      end
    end

    context 'with standard abilities' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:group) { create(:group, parent: root_group) }
      let_it_be(:child_group) { create(:group, parent: group) }
      let_it_be(:project) { create(:project, group: group) }
      let_it_be(:child_project) { create(:project, group: child_group) }

      it { is_expected.not_to be_allowed(user, nil) }

      context 'with a role that enables every standard ability' do
        standard_abilities = Gitlab::CustomRoles::Definition.standard
        project_resources = %i[project child_project]

        resources_by_source = {
          root_group: %i[root_group group child_group project child_project],
          group: %i[group child_group project child_project],
          child_group: %i[child_group child_project],
          project: %i[project],
          child_project: %i[child_project]
        }

        let_it_be(:role) { create(:member_role, :guest, *standard_abilities.keys, namespace: root_group) }

        before do
          stub_licensed_features(custom_roles: true)
        end

        resources_by_source.each do |source_name, resource_names|
          context "with a membership on `#{source_name}`" do
            let_it_be(:membership) do
              source = public_send(source_name)
              membership_type = project_resources.include?(source_name) ? :project_member : :group_member

              create(membership_type, :guest, member_role: role, user: user, source: source)
            end

            resource_names.each do |resource_name|
              enabled_key = project_resources.include?(resource_name) ? :project_ability : :group_ability

              it "allows only the abilities enabled for `#{resource_name}`", :aggregate_failures do
                resource = public_send(resource_name)

                standard_abilities.each do |name, attrs|
                  expected = !!attrs[enabled_key]

                  expect(custom_ability.allowed?(user, name, resource))
                    .to be(expected), "expected allowed?(:#{name}) to be #{expected}"
                end
              end
            end
          end
        end
      end

      context 'with `custom_roles` enabled' do
        let_it_be(:ability) { :admin_runners }
        let_it_be(:role) { create(:member_role, :guest, ability, namespace: root_group) }

        before do
          stub_licensed_features(custom_roles: true)
        end

        it { is_expected.not_to be_allowed(user, ability, root_group) }

        context 'with a membership on `group`' do
          let_it_be(:membership) { create(:group_member, :guest, member_role: role, user: user, source: group) }

          it { is_expected.not_to be_allowed(user, ability, root_group) }
        end

        context 'with a membership on `child_group`' do
          let_it_be(:membership) { create(:group_member, :guest, member_role: role, user: user, source: child_group) }

          it { is_expected.not_to be_allowed(user, ability, root_group) }
          it { is_expected.not_to be_allowed(user, ability, group) }
          it { is_expected.not_to be_allowed(user, ability, project) }
        end

        context 'with a membership on `project`' do
          let_it_be(:membership) { create(:project_member, :guest, member_role: role, user: user, source: project) }

          it { is_expected.not_to be_allowed(user, ability, root_group) }
          it { is_expected.not_to be_allowed(user, ability, group) }
          it { is_expected.not_to be_allowed(user, ability, child_group) }
          it { is_expected.not_to be_allowed(user, ability, child_project) }
        end

        context 'with a membership on `child_project`' do
          let_it_be(:membership) do
            create(:project_member, :guest, member_role: role, user: user, source: child_project)
          end

          it { is_expected.not_to be_allowed(user, ability, root_group) }
          it { is_expected.not_to be_allowed(user, ability, group) }
          it { is_expected.not_to be_allowed(user, ability, child_group) }
          it { is_expected.not_to be_allowed(user, ability, project) }
        end

        context 'with a user assigned to an admin custom role' do
          let_it_be(:role) { create(:admin_member_role, :read_admin_users, user: user) }

          it { is_expected.to be_allowed(user, :read_admin_users) }
        end

        context 'with a nil user' do
          it { is_expected.not_to be_allowed(nil, ability, root_group) }
        end

        context 'with an unknown ability' do
          let_it_be(:membership) { create(:group_member, :guest, member_role: role, user: user, source: root_group) }

          it { is_expected.not_to be_allowed(user, :unknown, project) }
        end
      end

      context 'with `custom_roles` disabled' do
        let_it_be(:ability) { :admin_runners }
        let_it_be(:role) { create(:member_role, :guest, ability, namespace: root_group) }
        let_it_be(:membership) { create(:group_member, :guest, member_role: role, user: user, source: root_group) }

        before do
          stub_licensed_features(custom_roles: false)
        end

        it { is_expected.not_to be_allowed(user, ability, root_group) }

        context 'with a user assigned to an admin custom role' do
          let_it_be(:role) { create(:admin_member_role, :read_admin_users, user: user) }

          it { is_expected.not_to be_allowed(user, :read_admin_users) }
        end
      end
    end
  end
end
