# frozen_string_literal: true

require 'rubocop_spec_helper'
require_relative '../../../../../rubocop/cop/gitlab/authz/use_ability_allowed'

RSpec.describe RuboCop::Cop::Gitlab::Authz::UseAbilityAllowed, feature_category: :permissions do
  it 'flags can? on a receiver and corrects it to Ability.allowed?' do
    expect_offense(<<~RUBY)
      current_user.can?(:read_project, project)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
    RUBY

    expect_correction(<<~RUBY)
      Ability.allowed?(current_user, :read_project, project)
    RUBY
  end

  it 'corrects a call without a subject' do
    expect_offense(<<~RUBY)
      user.can?(:access_api)
      ^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
    RUBY

    expect_correction(<<~RUBY)
      Ability.allowed?(user, :access_api)
    RUBY
  end

  it 'corrects a call with a non-literal ability and keyword options' do
    expect_offense(<<~RUBY)
      @user.can?(ability, subject, cache: false)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
    RUBY

    expect_correction(<<~RUBY)
      Ability.allowed?(@user, ability, subject, cache: false)
    RUBY
  end

  it 'corrects a call on a compound receiver' do
    expect_offense(<<~RUBY)
      context[:current_user].can?(:read_admin_cicd)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
    RUBY

    expect_correction(<<~RUBY)
      Ability.allowed?(context[:current_user], :read_admin_cicd)
    RUBY
  end

  it 'corrects a call whose arguments span several lines' do
    expect_offense(<<~RUBY)
      user.can?(:read_virtual_registry,
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
        group.virtual_registry_policy_subject)
    RUBY

    expect_correction(<<~RUBY)
      Ability.allowed?(user, :read_virtual_registry,
        group.virtual_registry_policy_subject)
    RUBY
  end

  it 'flags a call without parentheses but does not correct it' do
    expect_offense(<<~RUBY)
      user.can? :read_project, project
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
    RUBY

    expect_no_corrections
  end

  it 'flags &.can? but does not correct it' do
    expect_offense(<<~RUBY)
      current_user&.can?(:read_project, project)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object. `Ability.allowed?` evaluates the policy for a nil user, so check the anonymous result before dropping `&.`.
    RUBY

    expect_no_corrections
  end

  it 'corrects a can? call inside the receiver before the outer call' do
    expect_offense(<<~RUBY)
      (u.can?(:a) ? u : v).can?(:b, s)
       ^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Ability.allowed?(user, ability, subject)` instead of calling `can?` on an object.
    RUBY

    expect_correction(<<~RUBY)
      Ability.allowed?((Ability.allowed?(u, :a) ? u : v), :b, s)
    RUBY
  end

  it 'does not flag can? on a policy object' do
    expect_no_offenses(<<~RUBY)
      IdentityProviderPolicy.new(current_user, provider).can?(:unlink)
      DeclarativePolicy.policy_for(current_user, project).can?(:read_project)
    RUBY
  end

  it 'does not flag a can? that takes the user as an argument' do
    expect_no_offenses(<<~RUBY)
      presenter.can?(current_user, :read_project, project)
      presenter&.can?(current_user, :read_project, project)
    RUBY
  end

  it 'does not flag can? on a constant' do
    expect_no_offenses(<<~RUBY)
      ::Users::Anonymous.can?(:read_project, project)
      Gitlab::SlashCommands::BaseCommand.can?(user, :read_project, project)
    RUBY
  end

  it 'does not flag the bare can? helper' do
    expect_no_offenses(<<~RUBY)
      can?(current_user, :read_project, project)
    RUBY
  end

  it 'does not flag Ability.allowed?' do
    expect_no_offenses(<<~RUBY)
      Ability.allowed?(current_user, :read_project, project)
    RUBY
  end
end
