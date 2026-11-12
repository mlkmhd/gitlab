# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Tasks::Gitlab::Permissions::Graphql::ParentAuthorizesCheck, feature_category: :permissions do
  let(:check) { described_class.new(schema) }
  let(:declared) { :read_wiki }
  let(:skipped) { skipped_type('Skipped', parent_authorizes: declared) }
  let(:root_fields) { {} }
  let(:mutation) { nil }

  let(:schema) do
    query = query_type(root_fields)
    mutation_type = mutation && root_mutation_type(mutation)

    Class.new(GraphQL::Schema) do
      query(query)
      mutation(mutation_type) if mutation_type
    end
  end

  def skipped_type(name, parent_authorizes: nil, fields: {}, reason: :parent_authorizes)
    Class.new(Types::BaseObject) do
      graphql_name name

      if parent_authorizes
        authorize_granular_token parent_authorizes: parent_authorizes
      else
        authorize_granular_token skip_reason: reason
      end

      field :name, GraphQL::Types::String, null: true, description: 'Name.'

      fields.each do |field_name, type|
        field field_name, type, null: true, description: 'Child.'
      end
    end
  end

  def parent_type(name, permission, child, field_permission: nil, boundary_type: :project, null: true)
    Class.new(Types::BaseObject) do
      graphql_name name

      authorize_granular_token permissions: permission, boundary: :itself, boundary_type: boundary_type

      field :child, child, null: null, description: 'Child.',
        directives: field_permission &&
          granular_scope_directive(permissions: field_permission, boundary: :itself, boundary_type: :project)
    end
  end

  def query_type(fields)
    Class.new(Types::BaseObject) do
      graphql_name 'Query'
      has_no_fields(true) if fields.empty?

      fields.each do |field_name, (type, permission)|
        field field_name, type, null: true, description: 'Root field.',
          directives: permission && granular_scope_directive(permissions: permission, boundary_type: :instance)
      end
    end
  end

  def root_mutation_type(mutation)
    Class.new(Types::BaseObject) do
      graphql_name 'Mutation'

      field :create_thing, mutation: mutation
    end
  end

  def violation(field, **details)
    { kind: 'type', name: 'Skipped', source: nil, field: field }.merge(details)
  end

  describe '#undeclared_types' do
    subject(:undeclared) { check.undeclared_types.keys }

    let(:declared) { nil }

    context 'when a type with its own check returns the type' do
      let(:root_fields) { { a: parent_type('ParentA', :read_project, skipped) } }

      it { is_expected.to contain_exactly('Skipped') }

      context 'when the type declares a permission' do
        let(:declared) { :read_wiki }

        it { is_expected.to be_empty }
      end
    end

    context 'when only a root field returns the type' do
      let(:root_fields) { { skipped: [skipped, :read_project] } }

      it { is_expected.to be_empty }
    end
  end

  describe '#violations' do
    subject(:violations) { check.violations }

    context 'when a type with its own check returns the type' do
      let(:root_fields) { { a: parent_type('ParentA', :read_project, skipped) } }

      it 'relies on the runtime check' do
        expect(violations).to be_empty
      end

      context 'when the field returns a connection of the type' do
        let(:root_fields) { { a: parent_type('ParentA', :read_project, skipped.connection_type) } }

        it 'relies on the runtime check' do
          expect(violations).to be_empty
        end
      end

      context 'when the parent boundary is not a boundary of the permission' do
        let(:root_fields) { { a: parent_type('ParentA', :read_project, skipped, boundary_type: :instance) } }

        it 'reports the field' do
          expect(violations[:parent_permission_boundary_mismatch]).to contain_exactly(
            violation('ParentA.child', permission: :read_wiki, boundary_type: :instance,
              assignable_boundaries: %i[group project])
          )
        end
      end

      context 'when the permission is not a policy ability' do
        before do
          allow(ProjectPolicy).to receive(:ability_map).and_return(DeclarativePolicy::Base::AbilityMap.new({}))
        end

        it 'reports the field' do
          expect(violations[:parent_permission_not_a_policy_ability]).to contain_exactly(
            violation('ParentA.child', permission: :read_wiki, boundary_type: :project)
          )
        end
      end

      context 'when the field is non-null' do
        let(:root_fields) { { a: parent_type('ParentA', :read_project, skipped, null: false) } }

        it 'reports the field, because a denied check would null the parent' do
          expect(violations[:parent_permissions_on_non_null_field]).to contain_exactly(
            violation('ParentA.child', permissions: Set[:read_wiki])
          )
        end

        context "when the permission is in an assignable permission with the parent's" do
          let(:declared) { :read_language }

          it 'does not report the field' do
            expect(violations).not_to have_key(:parent_permissions_on_non_null_field)
          end
        end
      end
    end

    context 'when the field has its own directive' do
      let(:root_fields) { { a: parent_type('ParentA', :read_project, skipped, field_permission: field_permission) } }

      context 'when the directive includes the declared permission' do
        let(:field_permission) { [:read_wiki, :read_project] }

        it { is_expected.to be_empty }
      end

      context 'when the directive does not include the declared permission' do
        let(:field_permission) { :read_project }

        it 'reports the field' do
          expect(violations[:parent_permissions_not_on_field_directive]).to contain_exactly(
            violation('ParentA.child', permissions: Set[:read_wiki])
          )
        end
      end
    end

    context 'when a root field returns the type' do
      let(:root_fields) { { skipped: [skipped, root_permission] } }

      context 'when the root field has no directive' do
        let(:root_permission) { nil }

        it 'reports the field' do
          expect(violations[:unchecked_parent_authorizes_field]).to contain_exactly(violation('Query.skipped'))
        end
      end

      context 'when the root field checks the declared permission' do
        let(:root_permission) { :read_wiki }

        it { is_expected.to be_empty }
      end
    end

    context 'when a mutation payload returns the type' do
      let(:payload_type) { skipped }
      let(:mutation) do
        type = payload_type
        mutation_directive = mutation_directive_args

        Class.new(Mutations::BaseMutation) do
          graphql_name 'CreateThing'

          authorize_granular_token(**mutation_directive) if mutation_directive

          field :thing, type, null: true, description: 'Thing.'
        end
      end

      context 'when the mutation has its own check' do
        let(:mutation_directive_args) do
          { permissions: :read_wiki, boundary_argument: :project_path, boundary_type: :project }
        end

        it { is_expected.to be_empty }
      end

      context 'when the mutation skips its check' do
        let(:mutation_directive_args) { { skip_reason: :external_service_authorizes } }

        it 'reports the payload field' do
          expect(violations[:unchecked_parent_authorizes_field]).to contain_exactly(
            violation('CreateThingPayload.thing')
          )
        end
      end

      context 'when the mutation has no directive' do
        let(:mutation_directive_args) { nil }

        it 'leaves it to the todo file' do
          expect(violations).to be_empty
        end
      end

      context 'when the payload returns another skipped type that returns the type' do
        let(:payload_type) { skipped_type('Wrapper', fields: { child: skipped }) }

        context 'when the mutation has its own check' do
          let(:mutation_directive_args) do
            { permissions: :read_wiki, boundary_argument: :project_path, boundary_type: :project }
          end

          it { is_expected.to be_empty }
        end

        context 'when the mutation skips its check' do
          let(:mutation_directive_args) { { skip_reason: :external_service_authorizes } }

          it 'reports the field' do
            expect(violations[:parent_permissions_missing_on_path]).to contain_exactly(
              violation('Wrapper.child', permissions: Set[:read_wiki])
            )
          end
        end
      end
    end

    context 'when a field on another skipped type returns the type' do
      let(:wrapper) { skipped_type('Wrapper', parent_authorizes: wrapper_permission, fields: { child: skipped }) }
      let(:wrapper_permission) { nil }
      let(:root_fields) { { a: parent_type('ParentA', :read_project, wrapper) } }

      it 'reports the field when a path does not check the declared permission' do
        expect(violations[:parent_permissions_missing_on_path]).to contain_exactly(
          violation('Wrapper.child', permissions: Set[:read_wiki])
        )
      end

      context 'when the skipped owner declares the permission' do
        let(:wrapper_permission) { :read_wiki }

        it { is_expected.to be_empty }
      end

      context 'when the field that returns the owner checks the permission' do
        let(:root_fields) { { a: parent_type('ParentA', :read_project, wrapper, field_permission: :read_wiki) } }

        it { is_expected.to be_empty }
      end

      context 'when a root field returns the owner' do
        let(:root_fields) { { wrapper: [wrapper, root_permission] } }

        context 'when the root field checks the permission' do
          let(:root_permission) { :read_wiki }

          it { is_expected.to be_empty }
        end

        context 'when the root field does not check the permission' do
          let(:root_permission) { :read_project }

          it 'reports the field' do
            expect(violations[:parent_permissions_missing_on_path]).to contain_exactly(
              violation('Wrapper.child', permissions: Set[:read_wiki])
            )
          end
        end
      end

      context 'when the skipped types return each other' do
        let(:root_fields) do
          first = skipped_type('First')
          second = skipped_type('Second', fields: { first: first, child: skipped })
          first.field :second, second, null: true, description: 'Second.'

          { a: parent_type('ParentA', :read_project, second) }
        end

        it 'checks every path around the cycle' do
          expect(violations[:parent_permissions_missing_on_path]).to contain_exactly(
            violation('Second.child', permissions: Set[:read_wiki])
          )
        end

        context 'when every path into the cycle checks the permission' do
          let(:root_fields) do
            first = skipped_type('First')
            second = skipped_type('Second', fields: { first: first, child: skipped })
            first.field :second, second, null: true, description: 'Second.'

            { a: parent_type('ParentA', :read_project, second, field_permission: :read_wiki) }
          end

          it { is_expected.to be_empty }
        end
      end
    end

    context 'when a field returns an interface whose possible types declare different permissions' do
      let(:interface) do
        Module.new do
          include Types::BaseInterface

          graphql_name 'Thing'

          field :name, GraphQL::Types::String, null: true, description: 'Name.'
        end
      end

      let(:field_permission) { nil }

      let(:root_fields) do
        thing = interface
        checked = parent_type('Checked', :read_project, GraphQL::Types::String).tap { |type| type.implements(thing) }
        skipped.implements(thing)

        {
          a: parent_type('ParentA', :read_project, interface, field_permission: field_permission),
          b: parent_type('ParentB', :read_project, checked),
          c: parent_type('ParentC', :read_project, skipped)
        }
      end

      it 'reports the field, because it checks none of them' do
        expect(violations[:inconsistent_parent_permissions]).to contain_exactly(
          { kind: 'type', name: 'Thing', source: nil, field: 'ParentA.child',
            declarations: { 'Checked' => [], 'Skipped' => [:read_wiki] } }
        )
      end

      context 'when the field has its own directive with the permissions' do
        let(:field_permission) { [:read_wiki, :read_project] }

        it { is_expected.to be_empty }
      end
    end
  end
end
