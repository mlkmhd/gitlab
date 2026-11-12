# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ProjectSettingWriter, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:actor) { Users::Internal.in_organization(project.organization_id).admin_bot }

  subject(:writer) { described_class.new(project: project, actor: actor) }

  describe '#write' do
    it 'writes a mapped setting through Projects::UpdateService and skips the settings gate', :aggregate_failures do
      project.update_column(:request_access_enabled, true)

      expect(Projects::UpdateService).to receive(:new)
        .with(project, actor, hash_including(request_access_enabled: false, skip_govern_settings_gate: true))
        .and_call_original

      result = writer.write('request_access_enabled', false)

      expect(result[:status]).to eq(:success)
      expect(project.reload.request_access_enabled).to be(false)
    end

    it 'is an error for an actor that is not the admin bot', :aggregate_failures do
      project.update_column(:request_access_enabled, true)
      maintainer = create(:user, maintainer_of: [project])

      result = described_class.new(project: project, actor: maintainer).write('request_access_enabled', false)

      expect(result).to eq(status: :error, message: 'actor is not the policy engine bot')
      expect(project.reload.request_access_enabled).to be(true)
    end

    it 'is an error when there is no actor', :aggregate_failures do
      project.update_column(:request_access_enabled, true)

      result = described_class.new(project: project, actor: nil).write('request_access_enabled', false)

      expect(result).to eq(status: :error, message: 'actor is not the policy engine bot')
      expect(project.reload.request_access_enabled).to be(true)
    end

    it 'is an error when the project or an ancestor is archived' do
      archived = create(:project, :archived, group: group)

      expect(described_class.new(project: archived, actor: actor).write('request_access_enabled', false))
        .to eq(status: :error, message: 'project or one of its ancestors is archived')
    end

    it 'is an error for a setting with no write mapping' do
      expect(writer.write('no_such_setting', true))
        .to eq(status: :error, message: 'no write mapping for setting no_such_setting with value true')
    end

    it 'is an error for a value the mapping refuses', :aggregate_failures do
      result = writer.write('request_access_enabled', 'junk')

      expect(result[:status]).to eq(:error)
      expect(result[:message]).to include('no write mapping')
    end

    it 'discards unsaved attributes after a failed write', :aggregate_failures do
      allow_next_instance_of(Projects::UpdateService) do |service|
        allow(service).to receive(:execute) do
          project.request_access_enabled = true
          { status: :error, message: 'save failed' }
        end
      end

      result = writer.write('request_access_enabled', true)

      expect(result).to eq(status: :error, message: 'save failed')
      expect(project.changed?).to be(false)
    end

    it 'tracks an unexpected error and reports it as an error result', :aggregate_failures do
      allow_next_instance_of(Projects::UpdateService) do |service|
        allow(service).to receive(:execute) do
          project.request_access_enabled = true
          raise 'boom'
        end
      end

      expect(::Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
        .with(instance_of(RuntimeError), project_id: project.id, setting: 'request_access_enabled')

      result = writer.write('request_access_enabled', true)

      expect(result).to eq(status: :error, message: 'unexpected error while writing setting request_access_enabled')
      expect(project.changed?).to be(false)
    end

    context "with #{described_class::SECURITY_SETTING}" do
      # This path authorizes through the granular permission, not the bot identity.
      let_it_be(:actor) { create(:user, maintainer_of: [project]) }

      before do
        stub_licensed_features(secret_push_protection: true)
      end

      def write(value)
        writer.write(described_class::SECURITY_SETTING, value)
      end

      it 'writes the security settings row and emits the audit event of a regular change', :aggregate_failures do
        project.security_setting.update!(secret_push_protection_enabled: false)

        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
          name: 'project_security_setting_updated', author: actor, scope: project, target: project))

        expect(write(true)).to eq(status: :success)
        expect(project.security_setting.reload.secret_push_protection_enabled).to be(true)
      end

      it 'stays a success when the audit fails after the committed write', :aggregate_failures do
        project.security_setting.update!(secret_push_protection_enabled: false)
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'audit failed')

        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), project_id: project.id)

        expect(write(true)).to eq(status: :success)
        expect(project.security_setting.reload.secret_push_protection_enabled).to be(true)
      end

      it 'is an error on an unlicensed tier' do
        stub_licensed_features(secret_push_protection: false)

        expect(write(true)).to eq(status: :error, message: 'secret push protection is not licensed')
      end

      it 'is an error for a value that is not a real boolean' do
        expect(write('yes'))
          .to eq(status: :error, message: %(secret_push_protection_enabled takes a boolean, got "yes"))
      end

      it 'is an error for an actor who may not update the security setting', :aggregate_failures do
        developer = create(:user, developer_of: [project])
        refused = described_class.new(project: project, actor: developer).write(described_class::SECURITY_SETTING, true)

        expect(refused).to eq(status: :error, message: 'actor is not allowed to update the security setting')
        expect(project.security_setting.reload.secret_push_protection_enabled).to be(false)
      end

      it 'is an error when the project or an ancestor is archived' do
        archived = create(:project, :archived, group: group)
        archived_writer = described_class.new(project: archived, actor: create(:user, maintainer_of: [archived]))

        expect(archived_writer.write(described_class::SECURITY_SETTING, true))
          .to eq(status: :error, message: 'project or one of its ancestors is archived')
      end

      it 'refuses to disable the protection when the instance enforces it', :aggregate_failures do
        stub_application_setting(secret_push_protection_enforced: true)
        project.security_setting.update!(secret_push_protection_enabled: true)

        expect(write(false))
          .to eq(status: :error, message: 'secret push protection is enforced for all projects in the instance')
        expect(project.security_setting.reload.secret_push_protection_enabled).to be(true)
      end

      it 'is an error when the project has no security settings row' do
        project.security_setting.destroy!
        project.reload

        expect(write(true)).to eq(status: :error, message: 'project has no security settings row')
      end
    end
  end
end
