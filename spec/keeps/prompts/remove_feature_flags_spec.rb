# frozen_string_literal: true

require 'fast_spec_helper'
require './keeps/prompts/remove_feature_flags'
require './keeps/helpers/milestones'

RSpec.describe ::Keeps::Prompts::RemoveFeatureFlags, feature_category: :global_search do
  let(:logger) do
    Object.new.tap do |obj|
      def obj.puts(message)
        # Just a stub to capture the message
        message
      end
    end
  end

  let(:feature_flag) { Struct.new(:name, :rollout_issue_url).new('test_feature_flag', 'https://gitlab.com/issue/123') }
  let(:milestones_helper) { instance_double(::Keeps::Helpers::Milestones, next_milestone: '15.0') }

  describe '#fetch' do
    subject(:remove_feature_flags) { described_class.new(logger) }

    before do
      allow_next_instance_of(described_class) do |instance|
        allow(instance).to receive(:milestones_helper).and_return(milestones_helper)
      end
    end

    context 'when flag is enabled' do
      let(:flag_enabled) { true }

      context 'with Ruby spec files' do
        let(:file) { 'path/to/file_spec.rb' }

        it 'returns the RSpec prompt for enabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include(
            'Branches of tests that have stubbed the feature flag as disabled should be entirely removed'
          )
        end
      end

      context 'with Ruby files' do
        let(:file) { 'path/to/file.rb' }
        let(:logic_text) do
          'If you see a branch of logic with `if Feature.enabled?(:test_feature_flag)` ' \
            'you should simplify the logic assuming the check returns `true`'
        end

        it 'returns the Ruby prompt for enabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include(logic_text)
        end
      end

      context 'with Markdown files' do
        let(:file) { 'path/to/file.md' }

        it 'returns the Markdown prompt for enabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('CRITICAL FORMATTING REQUIREMENT: After making any changes')
          expect(result).to include('Feature flag `test_feature_flag` removed.')
          expect(result).to include('Remember: The document must pass markdown linting')
        end
      end

      context 'with JavaScript spec files' do
        let(:file) { 'path/to/file_spec.js' }

        it 'returns the JavaScript spec prompt for enabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('Jest Test Files Feature Flag Removal Guidelines')
          expect(result).to include('testFeatureFlag')
        end
      end

      context 'with JavaScript files' do
        let(:file) { 'path/to/file.js' }

        it 'returns the JavaScript prompt for enabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('JavaScript Feature Flag Removal Guidelines')
          expect(result).to include('testFeatureFlag')
        end
      end

      context 'with Vue files' do
        let(:file) { 'path/to/file.vue' }

        it 'returns the Vue prompt for enabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('Vue.js Feature Flag Removal Guidelines')
          expect(result).to include('this.glFeatures.testFeatureFlag')
        end
      end

      context 'with truly unsupported file types' do
        let(:file) { 'path/to/file.txt' }

        it 'logs a warning and returns nil' do
          expect(logger).to receive(:puts).with(/Unexpected file extension/)
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)
          expect(result).to be_nil
        end
      end
    end

    context 'when flag is disabled' do
      let(:flag_enabled) { false }

      context 'with Ruby spec files' do
        let(:file) { 'path/to/file_spec.rb' }

        it 'returns the RSpec prompt for disabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('The feature flag has been disabled')
          expect(result).to include('Be sure to keep the entire context block in that case')
        end
      end

      context 'with Ruby files' do
        let(:file) { 'path/to/file.rb' }
        let(:logic_text) do
          'If you see a branch of logic with `if Feature.enabled?(:test_feature_flag)` ' \
            'you should simplify the logic assuming the check returns `false`'
        end

        it 'returns the Ruby prompt for disabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('The feature flag has been disabled')
          expect(result).to include(logic_text)
        end
      end

      context 'with Markdown files' do
        let(:file) { 'path/to/file.md' }

        it 'returns the Markdown prompt for markdown files' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          # Even though flag is disabled, the markdown prompt uses the same logic as enabled
          expect(result).to include('The feature flag has already been enabled')
        end
      end

      context 'with JavaScript spec files' do
        let(:file) { 'path/to/file_spec.js' }

        it 'returns the JavaScript spec prompt for disabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('The feature flag has been disabled')
          expect(result).to include('Jest Test Files Feature Flag Removal Guidelines')
        end
      end

      context 'with JavaScript files' do
        let(:file) { 'path/to/file.js' }

        it 'returns the JavaScript prompt for disabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('The feature flag has been disabled')
          expect(result).to include('JavaScript Feature Flag Removal Guidelines')
        end
      end

      context 'with Vue files' do
        let(:file) { 'path/to/file.vue' }

        it 'returns the Vue prompt for disabled flags' do
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)

          expect(result).to include('Your job is to remove old feature flags from code')
          expect(result).to include('feature flag is called `test_feature_flag`')
          expect(result).to include('The feature flag has been disabled')
          expect(result).to include('Vue.js Feature Flag Removal Guidelines')
        end
      end

      context 'with truly unsupported file types' do
        let(:file) { 'path/to/file.txt' }

        it 'logs a warning and returns nil' do
          expect(logger).to receive(:puts).with(/Unexpected file extension/)
          result = remove_feature_flags.fetch(feature_flag, file, flag_enabled)
          expect(result).to be_nil
        end
      end
    end
  end

  describe '#goal' do
    subject(:remove_feature_flags) { described_class.new(logger) }

    let(:seed_files) { ['app/models/a_model.rb'] }

    before do
      allow_next_instance_of(described_class) do |instance|
        allow(instance).to receive(:milestones_helper).and_return(milestones_helper)
      end
    end

    it 'names the flag and points at the playbook' do
      result = remove_feature_flags.goal(feature_flag, true, seed_files: seed_files)

      expect(result).to include('Remove the `test_feature_flag` feature flag')
      expect(result).to include(described_class::PLAYBOOK_PATH)
    end

    it 'points at a playbook file that exists' do
      # The goal only embeds the path, so a renamed or moved playbook would otherwise silently
      # strip every per-language rule from the session.
      expect(File.exist?(described_class::PLAYBOOK_PATH)).to be(true)
    end

    it 'lists the seeded files as a starting point rather than the whole scope' do
      result = remove_feature_flags.goal(feature_flag, true, seed_files: seed_files)

      expect(result).to include('app/models/a_model.rb')
      expect(result).to include('only a starting point')
    end

    it 'notes when the text search found nothing' do
      result = remove_feature_flags.goal(feature_flag, true, seed_files: [])

      expect(result).to include('A text search for the flag found no files.')
    end

    it 'asks for the frontend and backend checks to be run' do
      result = remove_feature_flags.goal(feature_flag, true, seed_files: seed_files)

      expect(result).to include('rubocop')
      expect(result).to include('prettier')
      expect(result).to include('rspec')
      expect(result).to include('jest')
    end

    context 'when the flag is disabled' do
      it 'tells the agent to keep the disabled path' do
        result = remove_feature_flags.goal(feature_flag, false, seed_files: seed_files)

        expect(result).to include('The flag is disabled in production')
        expect(result).to include('resolves to `false`')
      end
    end
  end
end
