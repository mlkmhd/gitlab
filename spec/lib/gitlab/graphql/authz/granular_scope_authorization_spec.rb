# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Authz::GranularScopeAuthorization, feature_category: :permissions do
  include Authz::GranularTokenAuthorizationHelper

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:object) { project }
  let(:directives) { [create_directive(boundary: 'itself', permissions: ['read_wiki'], boundary_type: 'project')] }

  let(:access_token) { create(:granular_pat, user: user) }

  let(:context) { { access_token: access_token } }

  subject(:authorization) { described_class.new(directives) }

  describe '#ok?' do
    subject(:ok) { authorization.ok?(object, context, arguments: arguments) }

    let(:arguments) { nil }

    context 'with a legacy (non-granular) token' do
      let(:access_token) { create(:personal_access_token, user: user) }

      it { is_expected.to be(true) }

      context 'when there are no granular directives' do
        let(:directives) { [] }

        it { is_expected.to be(true) }
      end
    end

    context 'with a legacy OAuth token' do
      let(:access_token) { create(:oauth_access_token, resource_owner: user) }

      it 'does not call the authorization service' do
        expect(::Authz::Tokens::AuthorizeGranularScopesService).not_to receive(:new)

        expect(ok).to be(true)
      end
    end

    context 'with a granular token' do
      let(:access_token) do
        create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:read_wiki])
      end

      context 'when there are no granular directives' do
        let(:directives) { [] }

        context 'when the object is nil' do
          let(:object) { nil }

          it { is_expected.to be(true) }
        end

        context 'when the object is present' do
          let(:object) { project }

          it { is_expected.to be(false) }
        end
      end

      context 'when a directive declares a skip reason' do
        let(:directives) { [create_directive(skip_reason: 'parent_authorizes')] }

        it 'allows the object through because authorization is enforced elsewhere' do
          expect(ok).to be(true)
        end
      end

      context 'when the token has the required permission on the boundary' do
        it { is_expected.to be(true) }
      end

      context 'when the token does not have the required permission on the boundary' do
        let(:access_token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:create_work_item])
        end

        it { is_expected.to be(false) }

        it 'caches the denied result so the boundary is not re-checked' do
          ok

          expect(context[:granular_tokens_authz_cache]).to eq(
            { [['read_wiki'], [['Project', project.id]]] =>
              [false, 'Access denied: This operation requires a fine-grained personal access token ' \
                'with the following project permissions: [Wiki: Read].'] }
          )
        end
      end

      context 'when permissions replace the permissions of the directives' do
        let(:authorization) { described_class.new(directives, permissions: [:create_work_item]) }

        context 'when the token has the given permissions on the boundary of the directives' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:create_work_item])
          end

          it { is_expected.to be(true) }
        end

        context "when the token only has the directives' permissions" do
          it { is_expected.to be(false) }
        end
      end

      context 'when the token is scoped to a different boundary than the object' do
        let_it_be(:other_project) { create(:project) }

        let(:access_token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(other_project), permissions: [:read_wiki])
        end

        it { is_expected.to be(false) }
      end

      context 'when no directive resolves to a matching boundary' do
        let(:directives) do
          [create_directive(boundary: 'itself', permissions: ['read_wiki'], boundary_type: 'group')]
        end

        it { is_expected.to be(false) }
      end

      context 'with multiple directives where only one matches the resolved object' do
        let(:directives) do
          [
            create_directive(boundary: 'itself', permissions: ['read_wiki'], boundary_type: 'group'),
            create_directive(boundary: 'itself', permissions: ['read_wiki'], boundary_type: 'project')
          ]
        end

        # The object is a project and the token is scoped to that project.
        # Succeeding proves the project directive was selected and the
        # mismatched group directive was skipped.
        it { is_expected.to be(true) }
      end

      context 'when the directives declare both concrete and standalone boundaries' do
        let(:directives) do
          [
            create_directive(boundary: 'owner', permissions: ['read_runner'], boundary_type: 'project'),
            create_directive(boundary: 'owner', permissions: ['read_runner'], boundary_type: 'group'),
            create_directive(permissions: ['read_runner'], boundary_type: 'instance')
          ]
        end

        let(:access_token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(:instance), permissions: [:read_runner])
        end

        context 'when the object resolves to a concrete boundary' do
          let(:object) { create(:ci_runner, :project, projects: [project]) }

          it { is_expected.to be(false) }
        end

        context 'when the object resolves to no concrete boundary' do
          let(:object) { create(:ci_runner, :instance) }

          it { is_expected.to be(true) }
        end
      end

      context 'when the token is scoped to an instance boundary' do
        let(:directives) { [create_directive(permissions: ['read_runner'], boundary_type: 'instance')] }

        context 'when the token has the required permission on the boundary' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(:instance), permissions: [:read_runner])
          end

          it { is_expected.to be(true) }
        end

        context 'when the token does not have the required permission on the boundary' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(:instance),
              permissions: [:read_member_role])
          end

          it { is_expected.to be(false) }
        end
      end

      context 'when the token is scoped to a user boundary' do
        let(:directives) { [create_directive(permissions: ['read_member_role'], boundary_type: 'user')] }

        context 'when the token has the required permission on the boundary' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(:user), permissions: [:read_member_role])
          end

          it { is_expected.to be(true) }
        end

        context 'when the token does not have the required permission on the boundary' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(:user), permissions: [:read_runner])
          end

          it { is_expected.to be(false) }
        end
      end

      context 'when boundaries are resolved from field arguments (root query field path)' do
        let(:object) { nil }
        let(:directives) do
          [create_directive(boundary_argument: 'project_path', permissions: ['read_wiki'], boundary_type: 'project')]
        end

        let(:arguments) { { project_path: project.full_path } }

        context 'when the token has the required permission on the resolved boundary' do
          it { is_expected.to be(true) }
        end

        context 'when the token does not have the required permission on the resolved boundary' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:create_work_item])
          end

          it { is_expected.to be(false) }
        end

        context 'when the arguments do not resolve to a boundary' do
          let(:arguments) { { project_path: 'nonexistent/path' } }

          it { is_expected.to be(false) }
        end
      end

      context 'when an object-sourced directive is checked with both an object and arguments present' do
        let(:arguments) { { some_arg: 'value' } }

        it { is_expected.to be(true) }
      end

      context 'when only the public access rule admits the token' do
        let_it_be(:public_project) { create(:project, :public, :wiki_enabled, maintainers: user) }
        let(:object) { public_project }
        let(:access_token) { create(:granular_pat, user: user) }
        let(:query) { GraphQL::Query.new(GitlabSchema, '{ __typename }') }
        let(:context) do
          GraphQL::Query::Context.new(query: query, values: { access_token: access_token, current_user: user })
        end

        it 'authorizes and scopes the current user to anonymous' do
          expect(ok).to be(true)
          expect(context[:current_user]).to be_nil
          expect(context[described_class::TOKEN_USER_KEY]).to eq(user)
        end

        context 'when a later check needs a permission the token holds' do
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(public_project),
              permissions: [:create_work_item])
          end

          let(:held_directives) do
            [create_directive(boundary: 'itself', permissions: ['create_work_item'], boundary_type: 'project')]
          end

          it 'restores the token user' do
            expect(ok).to be(true)
            expect(context[:current_user]).to be_nil

            expect(described_class.new(held_directives).ok?(public_project, context)).to be(true)
            expect(context[:current_user]).to eq(user)
          end
        end
      end

      context 'with caching' do
        it 'caches the authorized result and reuses it without re-running the service' do
          expect { ok }.to change { context[:granular_tokens_authz_cache] }
            .from(nil)
            .to({ [['read_wiki'], [['Project', project.id]]] => [true, nil, false] })

          expect(::Authz::Tokens::AuthorizeGranularScopesService).not_to receive(:new)

          expect(described_class.new(directives).ok?(object, context)).to be(true)
        end

        context 'with a standalone boundary' do
          let(:directives) { [create_directive(permissions: ['read_runner'], boundary_type: 'instance')] }
          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(:instance), permissions: [:read_runner])
          end

          it 'caches the boundary as its type symbol' do
            ok

            expect(context[:granular_tokens_authz_cache]).to eq({ [['read_runner'],
              [:instance]] => [true, nil, false] })
          end
        end

        context 'with multiple permissions and boundaries' do
          let(:permissions) { %w[read_wiki create_work_item] }
          let(:directives) do
            [
              create_directive(boundary: 'itself', permissions: permissions, boundary_type: 'project'),
              create_directive(boundary: 'group', permissions: permissions, boundary_type: 'group')
            ]
          end

          let(:access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: permissions)
          end

          it 'caches the sorted permissions against every resolved boundary under one key' do
            ok

            expect(context[:granular_tokens_authz_cache]).to eq(
              { [%w[create_work_item read_wiki], [['Group', group.id], ['Project', project.id]]] => [true, nil, false] }
            )
          end
        end
      end
    end
  end

  describe '#authorize!' do
    subject(:authorize) { authorization.authorize!(object, context) }

    let(:access_token) do
      create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:read_wiki])
    end

    context 'when authorization succeeds' do
      it 'does not raise' do
        expect { authorize }.not_to raise_error
      end

      context 'when a loaded argument scoped the current user to anonymous' do
        let(:query) { GraphQL::Query.new(GitlabSchema, '{ __typename }') }
        let(:context) do
          GraphQL::Query::Context.new(query: query, values: { access_token: access_token, current_user: user })
        end

        it 'restores the token user' do
          context[described_class::TOKEN_USER_KEY] = user
          context.scoped_set!(:current_user, nil)

          authorize

          expect(context[:current_user]).to eq(user)
        end
      end
    end

    context 'when only the public access rule admits the token' do
      let_it_be(:public_project) { create(:project, :public, :wiki_enabled) }
      let(:object) { public_project }

      it 'raises an ArgumentError' do
        expect { authorize }.to raise_error(Gitlab::Graphql::Errors::ArgumentError, /Wiki: Read/)
      end
    end

    context 'when authorization fails' do
      let(:access_token) do
        create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:create_work_item])
      end

      it 'raises an ArgumentError with the denial message from the authorization service' do
        expect { authorize }.to raise_error(
          Gitlab::Graphql::Errors::ArgumentError,
          'Access denied: This operation requires a fine-grained personal access token ' \
            'with the following project permissions: [Wiki: Read].'
        )
      end
    end

    context 'when boundaries are resolved from arguments (mutation path)' do
      subject(:authorize) { authorization.authorize!(nil, context, arguments: arguments) }

      let(:directives) do
        [create_directive(boundary_argument: 'project_path', permissions: ['read_wiki'], boundary_type: 'project')]
      end

      let(:arguments) { { project_path: project.full_path } }

      context 'when the token has the required permission on the resolved boundary' do
        it 'does not raise' do
          expect { authorize }.not_to raise_error
        end
      end

      context 'when the token does not have the required permission on the resolved boundary' do
        let(:access_token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: [:create_work_item])
        end

        it 'raises an ArgumentError with the denial message from the authorization service' do
          expect { authorize }.to raise_error(
            Gitlab::Graphql::Errors::ArgumentError,
            'Access denied: This operation requires a fine-grained personal access token ' \
              'with the following project permissions: [Wiki: Read].'
          )
        end
      end

      context 'when the arguments do not resolve to a boundary' do
        let(:arguments) { { project_path: 'nonexistent/path' } }

        it 'raises an ArgumentError with a not found message' do
          expect { authorize }.to raise_error(Gitlab::Graphql::Errors::ArgumentError, '404 Not Found')
        end
      end
    end
  end
end
