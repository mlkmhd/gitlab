# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::FeedbackPolicy, feature_category: :vulnerability_management do
  include ExternalAuthorizationServiceHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :public, namespace: owner.namespace) }

  let(:current_user) { owner }

  subject { described_class.new(current_user, vulnerability_feedback) }

  it 'delegates to the project policy' do
    feedback = build_stubbed(:vulnerability_feedback, project: project)

    expect(described_class.new(current_user, feedback)).to delegate_to(ProjectPolicy)
  end

  describe 'create_vulnerability_feedback' do
    context 'when the user is able to create issues in the project' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      before_all do
        project.add_developer(owner)
      end

      it { expect_allowed(:create_vulnerability_feedback) }
    end

    context 'when issue cannot be created' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      context 'when issues feature is disabled' do
        before do
          project.project_feature.update!(issues_access_level: ProjectFeature::DISABLED)
        end

        it 'does not allow to create issue feedback' do
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'when user does not have permission to create issue in project' do
        subject { described_class.new(nil, vulnerability_feedback) }

        it 'does not allow to create issue feedback' do
          expect_disallowed(:create_issue)
          expect_disallowed(:create_vulnerability_feedback)
        end
      end
    end

    context 'when merge request cannot be created' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :merge_request) }

      context 'when merge request feature is disabled' do
        before do
          project.project_feature.update!(merge_requests_access_level: ProjectFeature::DISABLED)
        end

        it 'does not allow to create merge request feedback' do
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'when user does not have permission to create merge_request in project' do
        subject { described_class.new(nil, vulnerability_feedback) }

        it 'does not allow to create merge request feedback' do
          expect_disallowed(:create_merge_request_in)
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'when user does not have developer permission' do
        # guest can create merge request IN
        let_it_be(:guest) { create(:user, guest_of: project) }

        subject { described_class.new(guest, vulnerability_feedback) }

        it 'does not allow to create merge request feedback' do
          expect_allowed(:create_merge_request_in)
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'with security bot' do
        let_it_be(:current_user) { create(:user, :security_bot) }

        it { expect_disallowed(:create_vulnerability_feedback) }
      end
    end

    context 'when the user can dismiss vulnerabilities without admin_vulnerability' do
      let_it_be_with_reload(:group_project) { create(:project, :private, :in_group) }
      let_it_be(:dismisser) { create(:user) }
      let_it_be(:role) { create(:member_role, :developer, :dismiss_vulnerability, namespace: group_project.group) }

      let(:current_user) { dismisser }

      before_all do
        create(:group_member, :developer, member_role: role, user: dismisser, source: group_project.group)
      end

      before do
        stub_licensed_features(custom_roles: true, security_dashboard: true)
      end

      it 'has dismiss_vulnerability but not admin_vulnerability' do
        expect(dismisser.can?(:dismiss_vulnerability, group_project)).to be(true)
        expect(dismisser.can?(:admin_vulnerability, group_project)).to be(false)
      end

      context 'when feedback type is dismissal' do
        let(:vulnerability_feedback) do
          Vulnerabilities::Feedback.new(project: group_project, feedback_type: :dismissal, finding_uuid: finding_uuid)
        end

        context 'when the finding has a vulnerability' do
          let(:finding_uuid) { create(:vulnerability, :with_finding, project: group_project).finding.uuid }

          it { expect_allowed(:create_vulnerability_feedback) }

          context 'when the project is archived' do
            let(:current_user) { create(:user, maintainer_of: group_project) }

            before do
              group_project.update!(archived: true)
            end

            it { expect_disallowed(:create_vulnerability_feedback) }
          end
        end

        context 'when the finding has no vulnerability' do
          let(:finding_uuid) { create(:vulnerabilities_finding, project: group_project).uuid }

          it { expect_disallowed(:create_vulnerability_feedback) }

          context 'when the user is a maintainer' do
            let(:current_user) { create(:user, maintainer_of: group_project) }

            it { expect_allowed(:create_vulnerability_feedback) }
          end
        end

        context 'when the finding only exists in a pipeline' do
          let(:finding_uuid) { SecureRandom.uuid }

          it { expect_disallowed(:create_vulnerability_feedback) }
        end
      end

      context 'when feedback type is merge_request' do
        let(:vulnerability_feedback) do
          Vulnerabilities::Feedback.new(project: group_project, feedback_type: :merge_request)
        end

        it { expect_disallowed(:create_vulnerability_feedback) }
      end
    end
  end

  describe 'update_vulnerability_feedback' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when feedback type is issue' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      it 'does not allow to update issue feedback' do
        expect_disallowed(:update_vulnerability_feedback)
      end
    end

    context 'when feedback type is merge_request' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :merge_request) }

      it 'does not allow to update merge request feedback' do
        expect_disallowed(:update_vulnerability_feedback)
      end
    end

    context 'when feedback type is dismissal' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :dismissal) }

      it 'allows to update dismissal feedback' do
        expect_allowed(:update_vulnerability_feedback)
      end
    end
  end

  describe 'destroy_vulnerability_feedback' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when feedback type is issue' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      it 'does not allow to destroy issue feedback' do
        expect_disallowed(:destroy_vulnerability_feedback)
      end
    end

    context 'when feedback type is merge_request' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :merge_request) }

      it 'does not allow to destroy merge request feedback' do
        expect_disallowed(:destroy_vulnerability_feedback)
      end
    end

    context 'when feedback type is dismissal' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :dismissal) }

      it 'allows to destroy dismissal feedback' do
        expect_allowed(:destroy_vulnerability_feedback)
      end
    end

    context 'when the user can change vulnerability status without admin_vulnerability' do
      let_it_be_with_reload(:group_project) { create(:project, :private, :in_group) }
      let_it_be(:status_changer) { create(:user) }
      let_it_be(:role) do
        create(:member_role, :developer, :update_vulnerability_status, namespace: group_project.group)
      end

      let(:current_user) { status_changer }

      before_all do
        create(:group_member, :developer, member_role: role, user: status_changer, source: group_project.group)
      end

      before do
        stub_licensed_features(custom_roles: true, security_dashboard: true)
      end

      it 'has revert_vulnerability but not admin_vulnerability' do
        expect(status_changer.can?(:revert_vulnerability, group_project)).to be(true)
        expect(status_changer.can?(:admin_vulnerability, group_project)).to be(false)
      end

      context 'when feedback type is dismissal' do
        let(:vulnerability_feedback) do
          Vulnerabilities::Feedback.new(project: group_project, feedback_type: :dismissal, finding_uuid: finding_uuid)
        end

        context 'when the finding has a vulnerability' do
          let(:finding_uuid) { create(:vulnerability, :with_finding, project: group_project).finding.uuid }

          it { expect_allowed(:destroy_vulnerability_feedback) }

          context 'when the project is archived' do
            let(:current_user) { create(:user, maintainer_of: group_project) }

            before do
              group_project.update!(archived: true)
            end

            it { expect_disallowed(:destroy_vulnerability_feedback) }
          end
        end

        context 'when the finding has no vulnerability' do
          let(:finding_uuid) { create(:vulnerabilities_finding, project: group_project).uuid }

          it { expect_disallowed(:destroy_vulnerability_feedback) }

          context 'when the user is a maintainer' do
            let(:current_user) { create(:user, maintainer_of: group_project) }

            it { expect_allowed(:destroy_vulnerability_feedback) }
          end
        end
      end

      context 'when feedback type is issue' do
        let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: group_project, feedback_type: :issue) }

        it { expect_disallowed(:destroy_vulnerability_feedback) }
      end

      context 'when creating dismissal feedback' do
        let(:vulnerability_feedback) do
          Vulnerabilities::Feedback.new(
            project: group_project, feedback_type: :dismissal,
            finding_uuid: create(:vulnerability, :with_finding, project: group_project).finding.uuid
          )
        end

        it { expect_disallowed(:create_vulnerability_feedback) }
      end
    end
  end
end
