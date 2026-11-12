# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Mention::ConversationMessage, feature_category: :dap_code_review do
  let_it_be(:duo_code_review_bot) { build_stubbed(:user, :duo_code_review_bot) }
  let_it_be(:user) { build_stubbed(:user, username: 'jane') }

  describe '.render' do
    it 'renders a user note with the username of the author and an escaped body' do
      note = build_stubbed(:note, author: user, note: 'Is <b>this</b> fine?')

      expect(described_class.render(note))
        .to eq("<message author=\"@jane\">\nIs &lt;b&gt;this&lt;/b&gt; fine?\n</message>")
    end

    it 'renders a note from Duo with the GitLabDuo author' do
      note = build_stubbed(:note, author: duo_code_review_bot, note: 'One minor finding.')

      expect(described_class.render(note)).to eq("<message author=\"GitLabDuo\">\nOne minor finding.\n</message>")
    end

    it 'truncates the body to max_length' do
      note = build_stubbed(:note, author: user, note: 'a' * 20)

      expect(described_class.render(note, max_length: 10))
        .to eq("<message author=\"@jane\">\n#{'a' * 7}...\n</message>")
    end
  end
end
