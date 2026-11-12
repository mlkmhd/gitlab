# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Preloaders::LabelsPreloader, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:root) { create(:group) }

  def create_group_with_both_labels
    subgroup = create(:group, parent: root)
    [create(:group_label, group: subgroup), create(:label, project: create(:project, group: subgroup))]
  end

  def preload(labels)
    ActiveRecord::QueryRecorder.new { described_class.new(Label.where(id: labels).to_a, user).preload_all }
  end

  it 'does not query root ancestors per group that owns both group and project labels' do
    labels = create_group_with_both_labels
    control = preload(labels)

    labels += Array.new(2) { create_group_with_both_labels }.flatten

    expect { preload(labels) }.not_to exceed_query_limit(control)
  end
end
