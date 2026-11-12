# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::NotesUpdateRateLimit, feature_category: :code_review_workflow do
  let_it_be(:user) { build_stubbed(:user) }

  let(:host_class) do
    Class.new do
      include Gitlab::NotesUpdateRateLimit

      attr_reader :current_user, :rate_limit_call

      def initialize(current_user)
        @current_user = current_user
      end

      def check_rate_limit!(key, **options, &block)
        @rate_limit_call = { key: key, options: options, block: block }
      end
    end
  end

  let(:host) { host_class.new(user) }

  describe '#check_notes_update_rate_limit!' do
    before do
      stub_application_setting(notes_create_limit_allowlist: ['allowed_user'])
    end

    it 'checks the notes_update limit for the current user with the notes allowlist' do
      host.check_notes_update_rate_limit!

      expect(host.rate_limit_call).to include(
        key: :notes_update,
        options: { scope: { user: user }, users_allowlist: ['allowed_user'] }
      )
    end

    it 'passes the block on to check_rate_limit!' do
      block = proc { :throttled }

      host.check_notes_update_rate_limit!(&block)

      expect(host.rate_limit_call[:block]).to eq(block)
    end

    context 'when the notes_update_rate_limit feature flag is disabled' do
      before do
        stub_feature_flags(notes_update_rate_limit: false)
      end

      it 'does not check the limit' do
        host.check_notes_update_rate_limit!

        expect(host.rate_limit_call).to be_nil
      end
    end
  end
end
