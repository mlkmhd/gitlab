# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ci::Runners::UpdateRunnerService, '#execute', feature_category: :runner_core do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be_with_reload(:runner) { create(:ci_runner, :group, groups: [group], tag_list: %w[linux docker]) }

  subject(:execute) { described_class.new(user, runner).execute(params) }

  def tag_changes(from, to)
    { changes: [{ change: :tag_list, from: from, to: to }] }
  end

  describe 'tag_list audit event' do
    context 'when tag_list changes' do
      let(:params) { { tag_list: %w[linux docker gpu] } }

      it 'logs a ci_runner_tags_updated audit event with the old and new tags' do
        expect_next_instance_of(
          ::AuditEvents::RunnerAuditEventService,
          runner, user, group,
          name: 'ci_runner_tags_updated',
          message: 'Changed %{runner_type} CI runner tags from %{from} to %{to}',
          from: '[docker, linux]',
          to: '[docker, gpu, linux]',
          additional_details: tag_changes(%w[docker linux], %w[docker gpu linux])
        ) do |service|
          expect(service).to receive(:track_event).once.and_call_original
        end

        expect(execute).to be_success
      end

      it 'persists the audit event', :aggregate_failures do
        expect { execute }.to change { ::AuditEvents::GroupAuditEvent.count }.by(1)

        audit_event = ::AuditEvents::GroupAuditEvent.last
        expect(audit_event).to have_attributes(author: user, group_id: group.id, target_id: runner.id)
        expect(audit_event.details).to include(
          custom_message: 'Changed group CI runner tags from [docker, linux] to [docker, gpu, linux]',
          **tag_changes(%w[docker linux], %w[docker gpu linux])
        )
      end

      it 'displays the custom message as the audit event action' do
        execute

        expect(AuditEventPresenter.new(::AuditEvents::GroupAuditEvent.last).action)
          .to eq('Changed group CI runner tags from [docker, linux] to [docker, gpu, linux]')
      end
    end

    context 'when all tags are removed' do
      let(:params) { { tag_list: [] } }

      it 'shows the empty tag list as []' do
        execute

        expect(::AuditEvents::GroupAuditEvent.last.details).to include(
          custom_message: 'Changed group CI runner tags from [docker, linux] to []',
          **tag_changes(%w[docker linux], [])
        )
      end
    end

    context 'with an untagged runner' do
      let_it_be_with_reload(:untagged_runner) { create(:ci_runner, :group, groups: [group]) }

      subject(:execute) { described_class.new(user, untagged_runner).execute(params) }

      context 'when tags are added' do
        let(:params) { { tag_list: %w[linux] } }

        it 'shows the empty tag list as []' do
          execute

          expect(::AuditEvents::GroupAuditEvent.last.details[:custom_message])
            .to eq('Changed group CI runner tags from [] to [linux]')
        end
      end

      context 'when a tag named none is added' do
        let(:params) { { tag_list: %w[none] } }

        it 'records the tags in structured details' do
          execute

          expect(::AuditEvents::GroupAuditEvent.last.details).to include(
            custom_message: 'Changed group CI runner tags from [] to [none]',
            **tag_changes([], %w[none])
          )
        end
      end
    end

    context 'when a tag contains a comma' do
      let_it_be_with_reload(:runner) { create(:ci_runner, :group, groups: [group], tag_list: '"docker, gitlab--duo"') }

      let(:params) { { tag_list: %w[docker gitlab--duo] } }

      it 'records the tags in structured details' do
        execute

        expect(::AuditEvents::GroupAuditEvent.last.details)
          .to include(tag_changes(['docker, gitlab--duo'], %w[docker gitlab--duo]))
      end
    end

    context 'with an instance runner' do
      let_it_be_with_reload(:runner) { create(:ci_runner, :instance, tag_list: %w[linux]) }

      let(:params) { { tag_list: %w[gpu] } }

      it 'persists an instance-scoped audit event', :aggregate_failures do
        expect { execute }.to change { ::AuditEvents::InstanceAuditEvent.count }.by(1)

        audit_event = ::AuditEvents::InstanceAuditEvent.last
        expect(audit_event).to have_attributes(target_id: runner.id, target_type: 'Ci::Runner')
        expect(audit_event.details).to include(
          custom_message: 'Changed instance CI runner tags from [linux] to [gpu]', **tag_changes(%w[linux], %w[gpu])
        )
      end
    end

    context 'with a project runner' do
      let_it_be(:project) { create(:project, group: group) }
      let_it_be_with_reload(:runner) { create(:ci_runner, :project, projects: [project], tag_list: %w[linux]) }

      let(:params) { { tag_list: %w[gpu] } }

      it 'persists a project-scoped audit event', :aggregate_failures do
        expect { execute }.to change { ::AuditEvents::ProjectAuditEvent.count }.by(1)

        audit_event = ::AuditEvents::ProjectAuditEvent.last
        expect(audit_event).to have_attributes(project_id: project.id, target_id: runner.id, target_type: 'Ci::Runner')
        expect(audit_event.details).to include(
          custom_message: 'Changed project CI runner tags from [linux] to [gpu]', **tag_changes(%w[linux], %w[gpu])
        )
      end
    end

    context 'when tag_list is unchanged' do
      let(:params) { { tag_list: %w[docker linux] } }

      it 'does not log an audit event', :aggregate_failures do
        expect(::AuditEvents::RunnerAuditEventService).not_to receive(:new)

        expect { execute }.not_to change { ::AuditEvents::GroupAuditEvent.count }
        expect(execute).to be_success
      end
    end

    context 'when a non-tag attribute changes' do
      let(:params) { { description: 'new description' } }

      it 'does not log a ci_runner_tags_updated audit event' do
        expect(::AuditEvents::RunnerAuditEventService).not_to receive(:new)

        expect(execute).to be_success
      end
    end

    context 'when the update fails' do
      let(:params) { { tag_list: %w[linux docker gpu], maximum_timeout: 1 } }

      it 'does not log an audit event', :aggregate_failures do
        expect(::AuditEvents::RunnerAuditEventService).not_to receive(:new)

        expect(execute).to be_error
      end
    end
  end
end
