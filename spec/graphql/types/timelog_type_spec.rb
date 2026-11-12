# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['Timelog'], feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:fields) { %i[id spent_at time_spent user issue merge_request note summary userPermissions project] }

  it { expect(described_class.graphql_name).to eq('Timelog') }
  it { expect(described_class).to have_graphql_fields(fields) }
  it { expect(described_class).to require_graphql_authorizations(:read_issuable) }
  it { expect(described_class).to expose_permissions_using(Types::PermissionTypes::Timelog) }

  describe 'user field' do
    subject { described_class.fields['user'] }

    it 'returns user' do
      is_expected.to have_non_null_graphql_type(Types::UserType)
    end
  end

  describe '#user' do
    let_it_be_with_reload(:timelog) do
      create(:issue_timelog, issue: create(:issue, project: create(:project, :public)))
    end

    def resolve_user
      batch_sync { resolve_field(:user, timelog, current_user: nil) }
    end

    it 'returns the user who logged the time' do
      expect(resolve_user).to eq(timelog.user)
    end

    it 'returns the ghost user when the user no longer exists' do
      timelog.user_id = non_existing_record_id

      expect(resolve_user).to be_ghost
    end
  end

  describe 'issue field' do
    subject { described_class.fields['issue'] }

    it 'returns issue' do
      is_expected.to have_graphql_type(Types::IssueType)
    end
  end

  describe 'merge_request field' do
    subject { described_class.fields['mergeRequest'] }

    it 'returns merge_request' do
      is_expected.to have_graphql_type(Types::MergeRequestType)
    end
  end

  describe 'project field' do
    subject { described_class.fields['project'] }

    it 'returns a nullable project' do
      is_expected.to have_nullable_graphql_type(Types::ProjectType)
    end
  end

  describe 'note field' do
    subject { described_class.fields['note'] }

    it 'returns note' do
      is_expected.to have_graphql_type(Types::Notes::NoteType)
    end
  end
end
