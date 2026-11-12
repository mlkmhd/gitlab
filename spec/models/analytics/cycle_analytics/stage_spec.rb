# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CycleAnalytics::Stage, feature_category: :value_stream_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }

  describe 'validations' do
    subject { build(:cycle_analytics_stage, namespace: group) }

    it { is_expected.to validate_uniqueness_of(:name).scoped_to([:group_id, :group_value_stream_id]) }

    it 'validates count of stages per value stream' do
      stub_const("#{described_class.name}::MAX_STAGES_PER_VALUE_STREAM", 1)
      value_stream = create(:cycle_analytics_value_stream, name: 'test')
      create(:cycle_analytics_stage, name: "stage 1", value_stream: value_stream)

      new_stage = build(:cycle_analytics_stage, name: "stage 2", value_stream: value_stream)

      expect do
        new_stage.save!
      end.to raise_error(ActiveRecord::RecordInvalid,
        _('Validation failed: Value stream Maximum number of stages per value stream exceeded'))
    end

    describe 'count of stages per top-level namespace' do
      let_it_be(:sub_group) { create(:group, organization: organization, parent: group) }
      let_it_be(:project) { create(:project, organization: organization, group: sub_group) }

      let!(:sub_group_stage) { create(:cycle_analytics_stage, namespace: sub_group) }
      let!(:project_stage) { create(:cycle_analytics_stage, project: project) }

      before do
        stub_const("#{described_class.name}::MAX_STAGES_PER_HIERARCHY", 2)
      end

      it 'rejects a new stage once the hierarchy holds the maximum, counting subgroups and projects' do
        new_stage = build(:cycle_analytics_stage, namespace: group)

        expect(new_stage).not_to be_valid
        expect(new_stage.errors[:namespace])
          .to include(_('Maximum number of stages per top-level namespace exceeded'))
      end

      it 'allows a new stage in another hierarchy' do
        new_stage = build(:cycle_analytics_stage, namespace: create(:group, organization: organization))

        expect(new_stage).to be_valid
      end

      it 'keeps a persisted stage valid when re-validated for create' do
        expect(project_stage.valid?(:create)).to be(true)
      end

      it 'rejects a new stage in a personal namespace hierarchy once it holds the maximum' do
        user = create(:user, :with_namespace, organization: organization)
        personal_project = create(:project, namespace: user.namespace, organization: organization)
        create_list(:cycle_analytics_stage, 2, project: personal_project)

        new_stage = build(:cycle_analytics_stage, project: personal_project)

        expect(new_stage).not_to be_valid
      end

      context 'when several new stages are saved together' do
        before do
          stub_const("#{described_class.name}::MAX_STAGES_PER_HIERARCHY", 3)
        end

        it 'counts the unsaved stages towards the maximum' do
          value_stream = build(:cycle_analytics_value_stream, namespace: group, stages: [
            build(:cycle_analytics_stage, namespace: group, name: 'stage 1'),
            build(:cycle_analytics_stage, namespace: group, name: 'stage 2')
          ])

          expect(value_stream).not_to be_valid
          expect(value_stream.errors.full_messages)
            .to include(a_string_including(_('Maximum number of stages per top-level namespace exceeded')))
        end

        it 'allows a single new stage that fits under the maximum' do
          expect(build(:cycle_analytics_stage, namespace: group)).to be_valid
        end

        context 'when the same update also removes stages' do
          let_it_be_with_reload(:value_stream) { create(:cycle_analytics_value_stream, namespace: group) }
          let_it_be(:removed_stage) { create(:cycle_analytics_stage, namespace: group, value_stream: value_stream) }

          def new_stage_attributes(name)
            attributes_for(:cycle_analytics_stage, name: name).merge(namespace: group)
          end

          it 'does not count the stages marked for destruction' do
            value_stream.assign_attributes(stages_attributes: [
              { id: removed_stage.id, _destroy: '1' },
              new_stage_attributes('replacement')
            ])

            expect(value_stream).to be_valid
          end

          it 'rejects more new stages than removed ones' do
            value_stream.assign_attributes(stages_attributes: [
              { id: removed_stage.id, _destroy: '1' },
              new_stage_attributes('replacement 1'),
              new_stage_attributes('replacement 2')
            ])

            expect(value_stream).not_to be_valid
          end
        end
      end

      context 'when the vsa_hierarchy_stage_limit feature flag is disabled' do
        before do
          stub_feature_flags(vsa_hierarchy_stage_limit: false)
        end

        it 'allows a new stage' do
          new_stage = build(:cycle_analytics_stage, namespace: group)

          expect(new_stage).to be_valid
        end
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).required }
    it { is_expected.to belong_to(:value_stream) }
  end

  it_behaves_like 'value stream analytics namespace models' do
    let(:factory_name) { :cycle_analytics_stage }
  end

  it_behaves_like 'value stream analytics stage' do
    let(:factory) { :cycle_analytics_stage }
    let(:parent) { create(:group) }
    let(:parent_name) { :namespace }
  end

  describe '.distinct_stages_within_hierarchy' do
    let_it_be(:group) { create(:group) }
    let_it_be(:sub_group) { create(:group, organization: group.organization, parent: group) }
    let_it_be(:project) { create(:project, organization: group.organization, group: sub_group).reload }

    before do
      # event identifiers are the same
      create(:cycle_analytics_stage, name: 'Stage A1', namespace: group,
        start_event_identifier: :merge_request_created, end_event_identifier: :merge_request_merged)
      create(:cycle_analytics_stage, name: 'Stage A2', namespace: sub_group,
        start_event_identifier: :merge_request_created, end_event_identifier: :merge_request_merged)
      create(:cycle_analytics_stage, name: 'Stage A3', namespace: sub_group,
        start_event_identifier: :merge_request_created, end_event_identifier: :merge_request_merged)
      create(:cycle_analytics_stage, name: 'Stage A4', project: project,
        start_event_identifier: :merge_request_created, end_event_identifier: :merge_request_merged)

      create(:cycle_analytics_stage,
        name: 'Stage B1',
        namespace: group,
        start_event_identifier: :merge_request_last_build_started,
        end_event_identifier: :merge_request_last_build_finished)

      create(:cycle_analytics_stage, name: 'Stage C1', project: project,
        start_event_identifier: :issue_created, end_event_identifier: :issue_deployed_to_production)
      create(:cycle_analytics_stage, name: 'Stage C2', project: project,
        start_event_identifier: :issue_created, end_event_identifier: :issue_deployed_to_production)
    end

    it 'returns distinct stages by the event identifiers' do
      stages = described_class.distinct_stages_within_hierarchy(group).to_a

      expected_event_pairs = [
        %w[merge_request_created merge_request_merged],
        %w[merge_request_last_build_started merge_request_last_build_finished],
        %w[issue_created issue_deployed_to_production]
      ].sort

      current_event_pairs = stages.map do |stage|
        [stage.start_event_identifier, stage.end_event_identifier]
      end.sort

      expect(current_event_pairs).to eq(expected_event_pairs)
    end
  end
end
