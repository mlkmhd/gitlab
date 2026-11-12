# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoSettings::AutoMode, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  describe '.consented?' do
    let_it_be_with_reload(:group) { create(:group) }
    let_it_be_with_reload(:subgroup) { create(:group, parent: group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }

    where(:scope, :group_consents, :group_locked, :subgroup_consents, :project_consents, :flag_enabled, :consented) do
      :group    | true  | false | nil   | false | true  | true
      :group    | false | false | nil   | true  | true  | false
      :group    | true  | false | nil   | false | false | false
      :subgroup | true  | false | false | false | true  | false
      :subgroup | true  | false | nil   | false | true  | true
      :subgroup | true  | true  | false | false | true  | true
      :project  | false | false | nil   | true  | true  | true
      :project  | true  | false | nil   | false | true  | false
      :project  | true  | true  | nil   | false | true  | true
    end

    with_them do
      let(:container) { { group: group, subgroup: subgroup, project: project }.fetch(scope) }

      before do
        stub_feature_flags(duo_auto_mode: flag_enabled)
        # Descendants first: a locked ancestor would otherwise reject their update.
        subgroup.namespace_settings.update!(duo_auto_mode_enabled: subgroup_consents)
        project.project_setting.update!(duo_auto_mode_enabled: project_consents)
        group.namespace_settings.update!(
          duo_auto_mode_enabled: group_consents, lock_duo_auto_mode_enabled: group_locked
        )
      end

      it { expect(described_class.consented?(container: container.reload)).to eq(consented) }
    end

    it 'is false without a container' do
      expect(described_class.consented?(container: nil)).to be(false)
    end
  end
end
