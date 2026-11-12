# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.vulnerabilities.details', feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project, security_dashboard_projects: [project]) }
  let_it_be(:details_file_location) do
    <<~FILE_LOACTION
      ... on VulnerabilityDetailFileLocation {
        description
        fieldName
        fileName
        lineEnd
        lineStart
        name
      }
    FILE_LOACTION
  end

  let_it_be(:all_field_types_for_query) do
    <<~FIELD_TYPES
      ... on VulnerabilityDetailBoolean {
        description
        fieldName
        name
        value
      }
      ... on VulnerabilityDetailCode {
        fieldName
        lang
        name
        value
      }
      ... on VulnerabilityDetailCommit {
        description
        fieldName
        name
        value
      }
      ... on VulnerabilityDetailDiff {
        after
        before
        description
        fieldName
        name
      }
      ... on VulnerabilityDetailInt {
        description
        fieldName
        name
        value
      }
      ... on VulnerabilityDetailMarkdown {
        description
        fieldName
        name
        value
      }
      ... on VulnerabilityDetailModuleLocation {
        description
        fieldName
        moduleName
        name
        offset
      }
      ... on VulnerabilityDetailText {
        description
        fieldName
        name
        value
      }
      ... on VulnerabilityDetailUrl {
        description
        fieldName
        href
        name
        text
      }
      #{details_file_location}
    FIELD_TYPES
  end

  let_it_be(:fields) do
    <<~QUERY
      details {
        __typename
        #{all_field_types_for_query}
        ... on VulnerabilityDetailTable {
          description
          fieldName
          name
          headers {
            __typename
            #{all_field_types_for_query}
          }
          rows {
            row {
              __typename
              #{all_field_types_for_query}
            }
          }
        }
        ... on VulnerabilityDetailList {
          description
          fieldName
          items {
            __typename
            #{all_field_types_for_query}
          }
          name
        }
        ... on VulnerabilityDetailNamedList {
          __typename
          name
          fieldName
          description
          items {
            __typename
            name
            fieldName
            description
            value {
              __typename
              #{all_field_types_for_query}
            }
          }
          name
        }
        ... on VulnerabilityDetailCodeFlows {
          type: __typename
          name
          items {
            ... {
              ... on VulnerabilityDetailCodeFlowNode {
                type: __typename
                nodeType
                fileLocation {
                  #{details_file_location}
                }
              }
            }
          }
        }
      }
    QUERY
  end

  let_it_be(:query) do
    graphql_query_for('vulnerabilities', {}, query_graphql_field('nodes', {}, fields))
  end

  let_it_be(:vulnerability) { create(:vulnerability, project: project, report_type: :container_scanning) }

  let_it_be(:finding) do
    create(
      :vulnerabilities_finding,
      :with_details,
      vulnerability: vulnerability
    )
  end

  let(:expected_details) do
    Gitlab::Json.parse(
      File.read(Rails.root.join('ee/spec/fixtures/api/graphql/vulnerabilities/details_expectation.json'))
    )
  end

  subject(:vulnerability_nodes) { graphql_data.dig('vulnerabilities', 'nodes') }

  before do
    stub_licensed_features(security_dashboard: true)
  end

  it 'returns a vulnerability details' do
    post_graphql(query, current_user: user)

    expect(vulnerability_nodes.first['details']).to eq(expected_details)
  end

  describe 'granular PAT authorization' do
    let(:vulnerability_query) { graphql_query_for('vulnerability', { id: global_id_of(vulnerability) }, fields) }
    let(:request) { post_graphql(vulnerability_query, current_user: user, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_vulnerability do
      let(:boundary_object) { project }
      let(:skipped_data_path) { %i[vulnerability details] }
    end

    context 'when the token can read the vulnerability' do
      let(:pat) do
        create(:granular_pat,
          user: user,
          boundary: ::Authz::Boundary.for(project),
          permissions: ::Authz::PermissionGroups::Assignable.preferred_for_permission(:read_vulnerability).name)
      end

      it 'returns every detail type' do
        request

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:vulnerability, :details)).to eq(expected_details)
      end

      context 'when a detail resolves to VulnerabilityDetailBase' do
        let_it_be(:vulnerability_with_value) do
          create(:vulnerability, project: project, report_type: :container_scanning).tap do |vuln|
            create(:vulnerabilities_finding, vulnerability: vuln,
              details: { 'score' => { 'type' => 'value', 'name' => 'Score', 'value' => 1.5 } })
          end
        end

        let(:vulnerability_query) do
          graphql_query_for('vulnerability', { id: global_id_of(vulnerability_with_value) },
            'details { __typename ... on VulnerabilityDetailBase { fieldName name } }')
        end

        it 'returns the detail' do
          request

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(:vulnerability, :details))
            .to eq([{ '__typename' => 'VulnerabilityDetailBase', 'fieldName' => 'score', 'name' => 'Score' }])
        end
      end
    end
  end
end
