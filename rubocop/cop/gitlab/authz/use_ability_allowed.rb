# frozen_string_literal: true

module RuboCop
  module Cop
    module Gitlab
      module Authz
        # Flags `can?` called on an object, such as `user.can?`, outside policy files.
        #
        # `User#can?` and `PolicyActor#can?` only call `Ability.allowed?`, and
        # they are being removed so models stop carrying permission logic.
        # See https://gitlab.com/gitlab-org/gitlab/-/work_items/638221.
        #
        # The receiver's type is unknown, so the autocorrect is unsafe: a few
        # objects that are not policy actors define their own `can?`.
        # `&.can?` is not autocorrected, because `Ability.allowed?` evaluates
        # the policy for a nil user where `&.can?` returned nil.
        #
        # Calls on a constant, such as `::Users::Anonymous.can?`, and the bare
        # `can?(user, ability, subject)` helper are not flagged.
        #
        # @example
        #   # bad
        #   current_user.can?(:read_project, project)
        #   current_user&.can?(:read_project, project)
        #
        #   # good
        #   Ability.allowed?(current_user, :read_project, project)
        #   can?(current_user, :read_project, project)
        class UseAbilityAllowed < ::RuboCop::Cop::Base
          extend AutoCorrector

          MSG = 'Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.'

          MSG_SAFE_NAVIGATION = "#{MSG} `Ability.allowed?` evaluates the policy for a nil user, " \
            'so check the anonymous result before dropping `&.`.'.freeze

          RESTRICT_ON_SEND = %i[can?].freeze

          # `User#can?` and `PolicyActor#can?` take at most an ability and a subject.
          # Presenters, controllers and parsers define `can?(user, ability, subject)`.
          MAX_POSITIONAL_ARGUMENTS = 2

          # @!method policy_object?(node)
          def_node_matcher :policy_object?, <<~PATTERN
            {
              (send (const _ #policy_class_name?) :new ...)
              (send _ :policy_for ...)
            }
          PATTERN

          def on_send(node)
            return unless flaggable?(node)

            add_offense(node) do |corrector|
              next unless rewritable?(node)

              corrector.replace(method_range(node), 'Ability.allowed?(')
              corrector.insert_before(node.first_argument, "#{node.receiver.source}, ")
            end
          end

          def on_csend(node)
            return unless flaggable?(node)

            add_offense(node, message: MSG_SAFE_NAVIGATION)
          end

          private

          def flaggable?(node)
            receiver = node.receiver

            return false if receiver.nil? || receiver.const_type? || policy_object?(receiver)

            positional_argument_count(node) <= MAX_POSITIONAL_ARGUMENTS
          end

          # A `can?` inside the receiver gets its own correction, which would overlap this one.
          # The next autocorrect pass corrects the outer call.
          def rewritable?(node)
            node.parenthesized? &&
              node.arguments.any? &&
              node.receiver.each_node(:send, :csend).none? { |inner| inner.method?(:can?) }
          end

          def positional_argument_count(node)
            node.arguments.count { |argument| !argument.type?(:hash, :block_pass) }
          end

          def policy_class_name?(name)
            name.to_s.end_with?('Policy')
          end

          # From the start of the receiver through the opening parenthesis.
          def method_range(node)
            node.source_range.with(end_pos: node.loc.begin.end_pos)
          end
        end
      end
    end
  end
end
