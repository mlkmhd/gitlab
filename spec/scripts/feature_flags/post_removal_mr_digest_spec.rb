# frozen_string_literal: true

require 'spec_helper'
require './scripts/feature_flags/post_removal_mr_digest'

RSpec.describe FeatureFlags::PostRemovalMrDigest, feature_category: :tooling do
  let(:logger) { StringIO.new }
  let(:api_helper) { instance_double(Keeps::Helpers::GitlabApiHelper) }
  let(:notes_url) do
    'https://gitlab.com/api/v4/projects/gitlab-org%2Fquality%2Fengineering-productivity%2Fteam/issues/597/notes'
  end

  let(:merge_requests) do
    [
      { 'web_url' => 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/1', 'title' => 'Remove `a_flag`' },
      { 'web_url' => 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/2', 'title' => 'Remove `b_flag`' }
    ]
  end

  let(:existing_notes) { [] }

  subject(:digest) { described_class.new(logger: logger) }

  before do
    allow(digest).to receive(:api_helper).and_return(api_helper)

    allow(api_helper).to receive(:query_api) do |url, &block|
      results = url.include?('/notes') ? existing_notes : merge_requests
      results.each(&block)
    end
  end

  describe '#execute' do
    it 'asks for merge requests in any state, so quickly merged ones are still reported' do
      allow(api_helper).to receive(:post).and_return(instance_double(HTTParty::Response, success?: true))

      digest.execute

      expect(api_helper).to have_received(:query_api).with(a_string_matching(/merge_requests\?/))
      expect(api_helper).not_to have_received(:query_api).with(a_string_including('state='))
    end

    it 'posts one note listing every merge request' do
      expect(api_helper).to receive(:post) do |url, body|
        expect(url).to eq(notes_url)
        expect(body[:body]).to include(merge_requests.first['web_url'], merge_requests.second['web_url'])

        instance_double(HTTParty::Response, success?: true)
      end

      digest.execute
    end

    context 'when there are no merge requests' do
      let(:merge_requests) { [] }

      it 'does not post a note' do
        expect(api_helper).not_to receive(:post)

        digest.execute
      end
    end

    context 'when every merge request was already noted' do
      let(:existing_notes) do
        [{ 'body' => "Previously: #{merge_requests.first['web_url']} and #{merge_requests.second['web_url']}" }]
      end

      it 'does not post a note again' do
        expect(api_helper).not_to receive(:post)

        digest.execute
      end
    end

    context 'when only some merge requests were already noted' do
      let(:existing_notes) { [{ 'body' => "Previously: #{merge_requests.first['web_url']}" }] }

      it 'posts a note listing only the new ones' do
        expect(api_helper).to receive(:post) do |_url, body|
          expect(body[:body]).to include(merge_requests.second['web_url'])
          expect(body[:body]).not_to include(merge_requests.first['web_url'])

          instance_double(HTTParty::Response, success?: true)
        end

        digest.execute
      end
    end

    context 'when a noted MR URL is a prefix of the incoming one' do
      let(:merge_requests) do
        [{ 'web_url' => 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/1', 'title' => 'Remove `a_flag`' }]
      end

      let(:existing_notes) do
        [{ 'body' => 'Previously: https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12' }]
      end

      it 'still posts the MR rather than treating it as already noted' do
        expect(api_helper).to receive(:post) do |_url, body|
          expect(body[:body]).to include(merge_requests.first['web_url'])

          instance_double(HTTParty::Response, success?: true)
        end

        digest.execute
      end
    end

    context 'when the tracking issue URL cannot be parsed' do
      before do
        stub_env('FEATURE_FLAG_REMOVAL_TRACKING_ISSUE_URL', 'not-a-url')
      end

      it 'raises' do
        expect { digest.execute }.to raise_error(described_class::Error, /Cannot parse tracking issue URL/)
      end
    end

    context 'when the tracking issue URL is a group-level work item' do
      before do
        stub_env('FEATURE_FLAG_REMOVAL_TRACKING_ISSUE_URL', 'https://gitlab.com/groups/some-group/-/work_items/12')
      end

      it 'raises rather than building a projects API path that 404s' do
        expect { digest.execute }.to raise_error(described_class::Error, /Cannot parse tracking issue URL/)
      end
    end

    context 'when the lookback window from the environment is malformed' do
      let(:now) { Time.utc(2026, 11, 2, 12) }

      before do
        stub_env('FEATURE_FLAG_REMOVAL_LOOKBACK_DAYS', 'not-a-number')
        allow(api_helper).to receive(:post).and_return(instance_double(HTTParty::Response, success?: true))
      end

      it 'falls back to the default window' do
        travel_to(now) { digest.execute }

        created_after = (now - described_class::DEFAULT_LOOKBACK_DAYS.days).iso8601
        expect(api_helper).to have_received(:query_api)
          .with(a_string_including("created_after=#{created_after}"))
      end
    end

    context 'when posting the note fails' do
      it 'raises' do
        allow(api_helper).to receive(:post).and_return(
          instance_double(HTTParty::Response, success?: false, code: 500, body: 'boom')
        )

        expect { digest.execute }.to raise_error(described_class::Error, /Failed to post note/)
      end
    end
  end

  describe '#api_helper' do
    let(:helper) { instance_double(Keeps::Helpers::GitlabApiHelper) }

    it 'builds one helper from the feature flag removal token and reuses it' do
      stub_env('FEATURE_FLAG_REMOVAL_API_TOKEN', 'removal-token')
      expect(Keeps::Helpers::GitlabApiHelper).to receive(:new).once.with(token: 'removal-token').and_return(helper)

      digest = described_class.new(logger: logger)

      expect(digest.send(:api_helper)).to be(helper)
      expect(digest.send(:api_helper)).to be(helper)
    end

    it 'falls back to the housekeeper token' do
      stub_env('FEATURE_FLAG_REMOVAL_API_TOKEN', nil)
      stub_env('HOUSEKEEPER_GITLAB_API_TOKEN', 'housekeeper-token')
      expect(Keeps::Helpers::GitlabApiHelper).to receive(:new).with(token: 'housekeeper-token').and_return(helper)

      expect(described_class.new(logger: logger).send(:api_helper)).to be(helper)
    end
  end
end
