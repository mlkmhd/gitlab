# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::BaseField, feature_category: :api do
  describe 'authorized?' do
    let(:object) { double }
    let(:current_user) { nil }
    let(:ctx) { { current_user: current_user } }

    it 'defaults to true' do
      field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true)

      expect(field).to be_authorized(object, nil, ctx)
    end

    it 'tests the field authorization, if provided' do
      field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, authorize: :foo)

      expect(Ability).to receive(:allowed?).with(current_user, :foo, object).and_return(false)

      expect(field).not_to be_authorized(object, nil, ctx)
    end

    it 'tests the field authorization, if provided, when it succeeds' do
      field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, authorize: :foo)

      expect(Ability).to receive(:allowed?).with(current_user, :foo, object).and_return(true)

      expect(field).to be_authorized(object, nil, ctx)
    end

    it 'only tests the resolver authorization if it authorizes_object?' do
      resolver = Class.new(Resolvers::BaseResolver)

      field = described_class.new(
        name: 'test', type: GraphQL::Types::String, null: true, resolver_class: resolver
      )

      expect(field).to be_authorized(object, nil, ctx)
    end

    it 'tests the resolver authorization, if provided' do
      resolver = Class.new(Resolvers::BaseResolver) do
        include Gitlab::Graphql::Authorize::AuthorizeResource

        authorizes_object!
      end

      field = described_class.new(
        name: 'test', type: GraphQL::Types::String, null: true, resolver_class: resolver
      )

      expect(resolver).to receive(:authorized?).with(object, ctx).and_return(false)

      expect(field).not_to be_authorized(object, nil, ctx)
    end

    it 'tests field authorization before resolver authorization, when field auth fails' do
      resolver = Class.new(Resolvers::BaseResolver) do
        include Gitlab::Graphql::Authorize::AuthorizeResource

        authorizes_object!
      end

      field = described_class.new(
        name: 'test',
        type: GraphQL::Types::String,
        null: true,
        authorize: :foo,
        resolver_class: resolver
      )

      expect(Ability).to receive(:allowed?).with(current_user, :foo, object).and_return(false)
      expect(resolver).not_to receive(:authorized?)

      expect(field).not_to be_authorized(object, nil, ctx)
    end

    it 'tests field authorization before resolver authorization, when field auth succeeds' do
      resolver = Class.new(Resolvers::BaseResolver) do
        include Gitlab::Graphql::Authorize::AuthorizeResource

        authorizes_object!
      end

      field = described_class.new(
        name: 'test',
        type: GraphQL::Types::String,
        null: true,
        authorize: :foo,
        resolver_class: resolver
      )

      expect(Ability).to receive(:allowed?).with(current_user, :foo, object).and_return(true)
      expect(resolver).to receive(:authorized?).with(object, ctx).and_return(false)

      expect(field).not_to be_authorized(object, nil, ctx)
    end
  end

  context 'when considering complexity' do
    let(:resolver) do
      Class.new(Resolvers::BaseResolver) do
        def self.resolver_complexity(args, child_complexity:)
          2 if args[:foo]
        end

        def self.complexity_multiplier(args)
          0.01
        end
      end
    end

    it 'defaults to 1' do
      field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true)

      expect(field.complexity).to eq 1
    end

    describe '#base_complexity' do
      context 'with no gitaly calls' do
        it 'defaults to 1' do
          field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true)

          expect(field.base_complexity).to eq 1
        end
      end

      context 'with a gitaly call' do
        it 'adds 1 to the default value' do
          field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, calls_gitaly: true)

          expect(field.base_complexity).to eq 2
        end
      end
    end

    it 'has specified value' do
      field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, complexity: 12)

      expect(field.complexity).to eq 12
    end

    context 'when field has a resolver' do
      context 'when a valid complexity is already set' do
        let(:field) { described_class.new(name: 'test', type: GraphQL::Types::String.connection_type, resolver_class: resolver, complexity: 2, max_page_size: 100, null: true) }

        it 'uses this complexity' do
          expect(field.complexity).to eq 2
        end
      end

      context 'and is a connection' do
        let(:field) { described_class.new(name: 'test', type: GraphQL::Types::String.connection_type, resolver_class: resolver, max_page_size: 100, null: true) }

        it 'sets complexity depending on arguments for resolvers' do
          expect(field.complexity.call({}, {}, 2)).to eq 4
          expect(field.complexity.call({}, { first: 50 }, 2)).to eq 3
        end

        it 'sets complexity depending on number load limits for resolvers' do
          expect(field.complexity.call({}, { first: 1 }, 2)).to eq 2
          expect(field.complexity.call({}, { first: 1, foo: true }, 2)).to eq 4
        end
      end

      context 'and is not a connection' do
        it 'sets complexity as normal' do
          field = described_class.new(name: 'test', type: GraphQL::Types::String, resolver_class: resolver, max_page_size: 100, null: true)

          expect(field.complexity.call({}, {}, 2)).to eq 2
          expect(field.complexity.call({}, { first: 50 }, 2)).to eq 2
        end
      end
    end

    context 'calls_gitaly' do
      context 'for fields with a resolver' do
        it 'adds 1 if true' do
          with_gitaly_field = described_class.new(name: 'test', type: GraphQL::Types::String, resolver_class: resolver, null: true, calls_gitaly: true)
          without_gitaly_field = described_class.new(name: 'test', type: GraphQL::Types::String, resolver_class: resolver, null: true)
          base_result = without_gitaly_field.complexity.call({}, {}, 2)

          expect(with_gitaly_field.complexity.call({}, {}, 2)).to eq base_result + 1
        end
      end

      context 'for fields without a resolver' do
        it 'adds 1 if true' do
          field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, calls_gitaly: true)

          expect(field.complexity).to eq 2
        end
      end

      it 'defaults to false' do
        field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true)

        expect(field.base_complexity).to eq Types::BaseField::DEFAULT_COMPLEXITY
      end

      context 'with declared constant complexity value' do
        it 'has complexity set to that constant' do
          field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, complexity: 12)

          expect(field.complexity).to eq 12
        end

        it 'does not raise an error even with Gitaly calls' do
          allow(Gitlab::GitalyClient).to receive(:get_request_count).and_return([0, 1])
          field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, complexity: 12)

          expect(field.complexity).to eq 12
        end
      end
    end
  end

  describe '#resolve' do
    context "late_extensions is given" do
      it 'registers the late extensions after the regular extensions' do
        extension_class = Class.new(GraphQL::Schema::Field::ConnectionExtension)
        field = described_class.new(name: 'test', type: GraphQL::Types::String.connection_type, null: true, late_extensions: [extension_class])

        expect(field.extensions.last.class).to be(extension_class)
      end
    end
  end

  include_examples 'Gitlab-style deprecations' do
    def subject(args = {})
      base_args = { name: 'test', type: GraphQL::Types::String, null: true }

      described_class.new(**base_args.merge(args))
    end
  end

  describe '#field_authorized?' do
    let(:object) { :object }
    let(:scope_validator) { instance_double(::Gitlab::Auth::ScopeValidator) }
    let(:user) { :user }
    let(:context) { { current_user: user, scope_validator: scope_validator } }

    it 'delegates to authorization providing the scopes' do
      expect_next_instance_of(::Gitlab::Graphql::Authorize::ObjectAuthorization) do |authorization|
        expect(authorization).to receive(:ok?)
          .with(object, user, scope_validator: scope_validator)
        expect(authorization.permitted_scopes).to eq([:api, :foobar_scope])
      end

      field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, scopes: [:api, :foobar_scope])
      field.authorized?(object, nil, context)
    end

    describe 'granular token authorization' do
      let(:object) { :object }
      let(:args) { { full_path: 'group-path' } }
      let(:context) { { current_user: nil } }

      it 'forwards the field arguments to the granular scope authorization' do
        expect_next_instance_of(::Gitlab::Graphql::Authz::GranularScopeAuthorization) do |authz|
          allow(authz).to receive(:empty?).and_return(false)
          expect(authz).to receive(:ok?).with(object, context, arguments: args).and_return(true)
        end

        field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true)

        expect(field).to be_authorized(object, args, context)
      end

      it 'does not check granular directives on mutation fields' do
        mutation = Class.new(::Mutations::BaseMutation) do
          graphql_name 'TestGranularFieldMutation'

          authorize_granular_token permissions: :read_wiki, boundary_argument: :full_path, boundary_type: :group
        end

        field = described_class.new(name: 'test', type: GraphQL::Types::String, null: true, resolver_class: mutation)

        allow(Ability).to receive(:allowed?).and_return(true)
        allow_next_instance_of(::Gitlab::Graphql::Authz::GranularScopeAuthorization) do |authz|
          allow(authz).to receive(:empty?).and_return(false)
          expect(authz).not_to receive(:ok?)
        end

        expect(field).to be_authorized(nil, { input: {} }, context)
      end
    end

    describe 'parent_authorizes check' do
      let(:object) { :object }
      let(:args) { {} }
      let(:token) { instance_double(PersonalAccessToken, granular?: true, subject_to_granular_authorization?: true) }
      let(:context) { { current_user: nil, current_object: parent_type.allocate, access_token: token } }
      let(:derived) { instance_double(::Gitlab::Graphql::Authz::GranularScopeAuthorization, ok?: allowed) }
      let(:allowed) { true }

      let(:declared_type) { declared_child('TestDeclaredChild', :read_wiki) }

      let(:parent_type) do
        Class.new(::Types::BaseObject) do
          graphql_name 'TestParentAuthorizesParent'

          authorize_granular_token permissions: :read_project, boundary: :itself, boundary_type: :project
        end
      end

      let(:field) { described_class.new(name: 'child', type: declared_type, null: true) }

      def declared_child(name, permission)
        Class.new(::Types::BaseObject) do
          graphql_name name

          authorize_granular_token parent_authorizes: permission
        end
      end

      def granular_directives(type)
        type.directives.select { |d| d.is_a?(Directives::Authz::GranularScope) }
      end

      def expect_no_derived_check
        allow(::Gitlab::Graphql::Authz::GranularScopeAuthorization).to receive(:new).and_call_original
        expect(::Gitlab::Graphql::Authz::GranularScopeAuthorization).not_to receive(:new)
          .with(anything, permissions: anything)
      end

      def expect_derived_check(permissions: %w[read_wiki])
        allow(::Gitlab::Graphql::Authz::GranularScopeAuthorization).to receive(:new).and_call_original
        expect(::Gitlab::Graphql::Authz::GranularScopeAuthorization).to receive(:new)
          .with(granular_directives(parent_type), permissions: permissions).and_return(derived)
      end

      it "checks the declared permissions on the parent's boundary" do
        expect_derived_check
        expect(derived).to receive(:ok?).with(object, context, arguments: args)

        expect(field).to be_authorized(object, args, context)
      end

      context 'when the check fails' do
        let(:allowed) { false }

        it 'denies the field' do
          expect_derived_check

          expect(field).not_to be_authorized(object, args, context)
        end
      end

      context 'when the field returns a connection of the declared type' do
        let(:field) { described_class.new(name: 'child', type: declared_type.connection_type, null: true) }

        it 'checks the declared permissions' do
          expect_derived_check

          expect(field).to be_authorized(object, args, context)
        end
      end

      context 'when the token is not subject to granular authorization' do
        let(:token) do
          instance_double(PersonalAccessToken, granular?: false, subject_to_granular_authorization?: false)
        end

        it 'does not check the declared permissions' do
          expect_no_derived_check

          expect(field).to be_authorized(object, args, context)
        end
      end

      context 'when the parent object is not known' do
        let(:context) { { current_user: nil, access_token: token } }

        it 'does not check the declared permissions' do
          expect_no_derived_check

          expect(field).to be_authorized(object, args, context)
        end
      end

      it 'builds the check once per parent type' do
        expect_derived_check

        2.times { field.authorized?(object, args, context) }
      end

      context 'when the field has its own directive' do
        let(:field) do
          described_class.new(name: 'child', type: declared_type, null: true,
            directives: described_class.granular_scope_directive(
              permissions: :read_wiki, boundary: :itself, boundary_type: :project))
        end

        it 'uses the directive of the field' do
          expect_no_derived_check

          field.authorized?(object, args, context)
        end
      end

      context 'when the parent type skips its own check' do
        let(:parent_type) { declared_child('TestSkippedParent', :read_project) }

        it 'does not check the declared permissions' do
          expect_no_derived_check

          expect(field).to be_authorized(object, args, context)
        end
      end

      context 'when the returned type does not declare permissions' do
        let(:declared_type) { GraphQL::Types::String }

        it 'does not check anything' do
          expect_no_derived_check

          expect(field).to be_authorized(object, args, context)
        end
      end

      context 'when the field returns a union' do
        let(:possible_types) { [declared_child('TestUnionA', :read_wiki), declared_child('TestUnionB', other)] }
        let(:union) do
          types = possible_types
          Class.new(::Types::BaseUnion) do
            graphql_name 'TestParentAuthorizesUnion'
            possible_types(*types)
          end
        end

        let(:field) { described_class.new(name: 'child', type: union, null: true) }

        before do
          schema = class_double(GraphQL::Schema, possible_types: possible_types)
          context.define_singleton_method(:schema) { schema }
        end

        context 'when all possible types declare the same permissions' do
          let(:other) { :read_wiki }

          it 'checks the declared permissions' do
            expect_derived_check

            expect(field).to be_authorized(object, args, context)
          end
        end

        context 'when the possible types declare different permissions' do
          let(:other) { :read_project }

          it 'does not check anything' do
            expect_no_derived_check

            expect(field).to be_authorized(object, args, context)
          end
        end
      end

      context 'when a query runs with a granular token' do
        let_it_be(:project) { create(:project) }
        let_it_be(:user) { create(:user, developer_of: project) }

        let(:token_permissions) { [:read_project, :read_wiki] }
        let(:token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: token_permissions)
        end

        let(:child_type) do
          Class.new(::Types::BaseObject) do
            graphql_name 'TestParentAuthorizesChild'

            authorize_granular_token parent_authorizes: :read_wiki

            field :name, GraphQL::Types::String, null: true
          end
        end

        let(:schema) do
          child = child_type
          project_type = Class.new(::Types::BaseObject) do
            graphql_name 'TestParentAuthorizesProject'

            authorize_granular_token permissions: :read_project, boundary: :itself, boundary_type: :project

            field :child, child, null: true

            def child
              { name: 'child' }
            end
          end

          projects = [project, project]
          query_type = Class.new(::Types::BaseObject) do
            graphql_name 'Query'

            field :projects, [project_type], null: true

            define_method(:projects) { projects }
          end

          Class.new(GraphQL::Schema) { query(query_type) }
        end

        subject(:children) do
          result = schema.execute('{ projects { child { name } } }',
            context: { current_user: user, access_token: token })

          result.dig('data', 'projects').map { |p| p['child'] }
        end

        it 'returns the child, checking each permission once for the project' do
          expect(::Authz::Tokens::AuthorizeGranularScopesService).to receive(:new).twice.and_call_original

          expect(children).to eq([{ 'name' => 'child' }, { 'name' => 'child' }])
        end

        context 'when the token lacks the declared permission' do
          let(:token_permissions) { [:read_project] }

          it 'returns no child' do
            expect(children).to eq([nil, nil])
          end
        end
      end
    end
  end
end
