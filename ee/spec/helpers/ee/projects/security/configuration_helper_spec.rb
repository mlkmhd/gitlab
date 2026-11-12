# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::Projects::Security::ConfigurationHelper do
  let(:project) { build_stubbed(:project) }

  before do
    helper.instance_variable_set(:@project, project)
  end

  describe 'group_configuration_path' do
    subject { helper.group_configuration_path }

    it { is_expected.to eq(group_security_configuration_path(project.root_ancestor)) }
  end

  describe 'duo_settings_configuration_path' do
    subject { helper.duo_settings_configuration_path(can_admin_root_group) }

    context 'when the user can administer the root group' do
      let(:can_admin_root_group) { true }
      let(:project) { build_stubbed(:project, group: build_stubbed(:group)) }

      it { is_expected.to eq(project.root_ancestor.duo_settings_path) }

      context 'when the root ancestor is a user namespace' do
        let(:project) { build_stubbed(:project) }

        it { is_expected.to be_nil }
      end
    end

    context 'when the user cannot administer the root group' do
      let(:can_admin_root_group) { false }
      let(:project) { build_stubbed(:project, group: build_stubbed(:group)) }

      it { is_expected.to be_nil }
    end
  end
end
