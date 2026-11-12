# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineCreation::Requests, :clean_gitlab_redis_shared_state, feature_category: :pipeline_composition do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:project) { merge_request.project }

  describe '.failed' do
    context 'when given a pipeline creation key and ID' do
      it 'sets the pipeline creation to the failed status' do
        request = described_class.start_for_merge_request(merge_request)

        described_class.failed(request, 'Insufficient permissions')

        expect(described_class.hget(request)).to match(
          { 'status' => 'failed', 'error' => 'Insufficient permissions', 'id' => request['id'],
            'user_initiated' => false, 'started_at' => a_kind_of(Numeric) }
        )
      end
    end

    context 'when given a ref request' do
      it 'deletes the request' do
        request = described_class.start_for_ref(project, 'refs/heads/feature')

        described_class.failed(request, 'Insufficient permissions')

        expect(described_class.hget(request)).to be_nil
      end
    end

    context 'when not given a request' do
      it 'returns nil' do
        expect(described_class.failed(nil, 'Insufficient permissions')).to be_nil
      end
    end
  end

  describe '.succeeded' do
    context 'when given a pipeline creation key and ID' do
      it 'sets the pipeline creation to the succeeded status' do
        request = described_class.start_for_merge_request(merge_request)

        described_class.succeeded(request, 1)

        expect(described_class.hget(request)).to match(
          { 'status' => 'succeeded', 'pipeline_id' => 1, 'id' => request['id'], 'user_initiated' => false,
            'started_at' => a_kind_of(Numeric) }
        )
      end
    end

    context 'when given a ref request' do
      it 'deletes the request' do
        request = described_class.start_for_ref(project, 'refs/heads/feature')

        described_class.succeeded(request, 1)

        expect(described_class.hget(request)).to be_nil
      end
    end

    context 'when not given a request' do
      it 'returns nil' do
        expect(described_class.succeeded(nil, 1)).to be_nil
      end
    end
  end

  describe '.keep_alive' do
    it 'extends the expiry of the request key' do
      request = described_class.start_for_project(project)
      Gitlab::Redis::SharedState.with { |r| r.expire(request['key'], 10) }

      described_class.keep_alive(request)

      ttl = Gitlab::Redis::SharedState.with { |r| r.ttl(request['key']) }
      expect(ttl).to be_within(5).of(described_class::REDIS_EXPIRATION_TIME)
    end

    it 'uses the given ttl' do
      request = described_class.start_for_project(project)

      described_class.keep_alive(request, ttl: 900)

      ttl = Gitlab::Redis::SharedState.with { |r| r.ttl(request['key']) }
      expect(ttl).to be_within(5).of(900)
    end

    it 'does not shorten the key expiry, including on a later write' do
      request = described_class.start_for_merge_request(merge_request)
      described_class.keep_alive(request, ttl: 900)

      described_class.keep_alive(request)
      described_class.start_for_merge_request(merge_request)

      ttl = Gitlab::Redis::SharedState.with { |r| r.ttl(request['key']) }
      expect(ttl).to be_within(5).of(900)
    end

    it 'does nothing without a request' do
      expect(described_class.keep_alive(nil)).to be_nil
    end

    context 'when given a ref request' do
      let(:ref) { 'refs/heads/feature' }
      let(:request) { described_class.start_for_ref(project, ref) }

      def key_ttl
        Gitlab::Redis::SharedState.with { |r| r.ttl(request['key']) }
      end

      it 'keeps the request in progress past the age cutoff until the given ttl' do
        described_class.keep_alive(request, ttl: 1.hour)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_ref?(project, ref)).to be(true)
        end

        travel_to((1.hour + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_ref?(project, ref)).to be(false)
        end
      end

      it 'does not shorten the key expiry or kept_alive_until, for example when a resume fails' do
        described_class.keep_alive(request, ttl: 1.hour)
        kept_alive_until = described_class.hget(request)['kept_alive_until']

        described_class.keep_alive(request)

        expect(key_ttl).to be_within(5).of(1.hour.to_i)
        expect(described_class.hget(request)['kept_alive_until']).to eq(kept_alive_until)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_ref?(project, ref)).to be(true)
        end
      end

      it 'keeps the request in progress when another request on the ref is started and finished' do
        described_class.keep_alive(request, ttl: 1.hour)

        other_request = described_class.start_for_ref(project, ref)
        described_class.succeeded(other_request, 1)

        expect(key_ttl).to be_within(5).of(1.hour.to_i)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_ref?(project, ref)).to be(true)
        end
      end

      it 'restores a request that expired while the job waited longer than the ttl' do
        described_class.keep_alive(request, ttl: 1.hour)
        # Redis does not follow travel_to, so delete the key as its expiry would.
        Gitlab::Redis::SharedState.with { |r| r.del(request['key']) }

        travel_to((1.hour + 1).seconds.from_now) do
          described_class.keep_alive(request)

          expect(described_class.hget(request)).to include('status' => 'in_progress', 'id' => request['id'])
          expect(described_class.pipeline_creating_for_ref?(project, ref)).to be(true)
        end
      end

      it 'restores a missing request for the given ttl' do
        described_class.succeeded(request, 1)

        described_class.keep_alive(request, ttl: 1.hour)

        expect(key_ttl).to be_within(5).of(1.hour.to_i)
        expect(described_class.hget(request)['kept_alive_until']).to be_within(5).of(1.hour.from_now.to_f)
      end

      it 'restores a missing request for the usual expiry by default' do
        described_class.succeeded(request, 1)

        described_class.keep_alive(request)

        expect(key_ttl).to be_within(5).of(described_class::REDIS_EXPIRATION_TIME)
        expect(described_class.hget(request)['kept_alive_until'])
          .to be_within(5).of(Time.current.to_f + described_class::REDIS_EXPIRATION_TIME)
      end
    end

    context 'when given a merge request request' do
      let(:request) { described_class.start_for_merge_request(merge_request) }

      it 'keeps the request in progress past the age cutoff until the given ttl' do
        described_class.keep_alive(request, ttl: 1.hour)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be(true)
        end

        travel_to((1.hour + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be(false)
        end
      end

      it 'does not keep other requests of the merge request in progress past the age cutoff' do
        other_request = described_class.start_for_merge_request(merge_request)
        described_class.keep_alive(request, ttl: 1.hour)
        described_class.succeeded(request, 1)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          expect(described_class.hget(other_request)['status']).to eq('in_progress')
          expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be(false)
        end
      end

      it 'restores a request that expired while the job waited longer than the ttl' do
        described_class.keep_alive(request, ttl: 1.hour)
        Gitlab::Redis::SharedState.with { |r| r.del(request['key']) }

        travel_to((1.hour + 1).seconds.from_now) do
          described_class.keep_alive(request)

          expect(described_class.hget(request))
            .to include('status' => 'in_progress', 'id' => request['id'], 'user_initiated' => false)
          expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be(true)
        end
      end

      it 'does not change a finished request' do
        described_class.succeeded(request, 1)

        expect { described_class.keep_alive(request, ttl: 1.hour) }
          .not_to change { described_class.hget(request) }
      end
    end
  end

  describe '.start_for_project' do
    it 'stores a pipeline creation for the project and returns its key and ID' do
      allow(SecureRandom).to receive(:uuid).and_return('test-id')

      request = described_class.start_for_project(project)

      expect(request).to match({
        'key' => described_class.request_key(project, 'test-id'),
        'id' => 'test-id',
        'started_at' => a_kind_of(Numeric)
      })
      expect(described_class.hget(request)).to match(
        { 'status' => 'in_progress', 'id' => 'test-id', 'started_at' => a_kind_of(Numeric) }
      )
    end

    it 'records started_at as an epoch timestamp that round-trips through Redis' do
      freeze_time do
        request = described_class.start_for_project(project)

        expect(request['started_at']).to eq(Time.current.to_f)
        expect(described_class.hget(request)['started_at']).to eq(Time.current.to_f)
      end
    end
  end

  describe '.start_for_merge_request' do
    it 'stores a pipeline creation for the merge request and returns its key and ID' do
      allow(SecureRandom).to receive(:uuid).and_return('test-id')

      request = described_class.start_for_merge_request(merge_request)

      allow(SecureRandom).to receive(:uuid).and_return('test-id-2')

      request2 = described_class.start_for_merge_request(merge_request)

      described_class.succeeded(request, 1)

      expect(request).to match({
        'key' => described_class.merge_request_key(merge_request),
        'id' => 'test-id',
        'user_initiated' => false,
        'started_at' => a_kind_of(Numeric)
      })

      expect(described_class.hget(request)).to match(
        { 'status' => 'succeeded', 'pipeline_id' => 1, 'id' => 'test-id', 'user_initiated' => false,
          'started_at' => a_kind_of(Numeric) }
      )
      expect(described_class.hget(request2)).to match(
        { 'status' => 'in_progress', 'id' => 'test-id-2', 'user_initiated' => false,
          'started_at' => a_kind_of(Numeric) }
      )
    end

    context 'when user initiated' do
      it 'stores the pipeline creation as user initiated' do
        request = described_class.start_for_merge_request(merge_request, user_initiated: true)

        expect(request['user_initiated']).to be(true)
        expect(described_class.hget(request)).to match(
          { 'status' => 'in_progress', 'id' => request['id'], 'user_initiated' => true,
            'started_at' => a_kind_of(Numeric) }
        )
      end
    end
  end

  describe '.pipeline_creating_for_merge_request?' do
    context 'when there are pipeline creations for the merge request' do
      it 'returns true' do
        described_class.start_for_merge_request(merge_request)

        expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be_truthy
      end
    end

    context 'when there are no pipeline creations for the merge request' do
      it 'returns false' do
        expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be_falsey
      end
    end

    context 'when an in-progress request is older than the expiration time' do
      it 'returns false' do
        described_class.start_for_merge_request(merge_request)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          expect(described_class.pipeline_creating_for_merge_request?(merge_request)).to be(false)
        end
      end
    end
  end

  describe '.get_request' do
    it 'returns the data for the request' do
      request = described_class.start_for_project(project)

      expect(described_class.get_request(project, request['id'])).to match(
        { 'status' => described_class::IN_PROGRESS, 'id' => request['id'], 'started_at' => a_kind_of(Numeric) }
      )
    end
  end

  describe '.hset' do
    it 'writes the pipeline creation to the Redis cache' do
      request = { 'key' => 'test_key', 'id' => 'test_id' }
      described_class.hset(request, 'status')

      expect(described_class.hget(request)).to eq({ 'status' => 'status', 'id' => 'test_id' })
    end

    it 'expires the cache after 5 minutes' do
      request = { 'key' => 'test_key', 'id' => 'test_id' }
      described_class.hset(request, 'status')

      ttl = Gitlab::Redis::SharedState.with { |r| r.ttl('test_key') }
      expect(ttl).to be_within(5).of(described_class::REDIS_EXPIRATION_TIME)
    end

    it 'extends a shorter expiry' do
      request = { 'key' => 'test_key', 'id' => 'test_id' }
      described_class.hset(request, 'status')
      Gitlab::Redis::SharedState.with { |r| r.expire('test_key', 10) }

      described_class.hset(request, 'status')

      ttl = Gitlab::Redis::SharedState.with { |r| r.ttl('test_key') }
      expect(ttl).to be_within(5).of(described_class::REDIS_EXPIRATION_TIME)
    end

    it 'does not shorten a longer expiry' do
      request = { 'key' => 'test_key', 'id' => 'test_id' }
      described_class.hset(request, 'status')
      Gitlab::Redis::SharedState.with { |r| r.expire('test_key', 900) }

      described_class.hset(request, 'status')

      ttl = Gitlab::Redis::SharedState.with { |r| r.ttl('test_key') }
      expect(ttl).to be_within(5).of(900)
    end
  end

  describe '.hget' do
    it 'returns the data for the request' do
      request = described_class.start_for_merge_request(merge_request)

      expect(described_class.hget(request)).to match(
        { 'status' => described_class::IN_PROGRESS, 'id' => request['id'], 'user_initiated' => false,
          'started_at' => a_kind_of(Numeric) }
      )
    end
  end

  describe '.project_request?' do
    it 'is true for a project request' do
      expect(described_class.project_request?(project, described_class.start_for_project(project))).to be(true)
    end

    it 'is false for ref and merge request requests' do
      expect(described_class.project_request?(project, described_class.start_for_ref(project, 'refs/heads/a')))
        .to be(false)
      expect(described_class.project_request?(project, described_class.start_for_merge_request(merge_request)))
        .to be(false)
    end
  end

  describe '.ref_request?' do
    it 'is true for a ref request' do
      expect(described_class.ref_request?(described_class.start_for_ref(project, 'refs/heads/a'))).to be(true)
    end

    it 'is false for project and merge request requests' do
      expect(described_class.ref_request?(described_class.start_for_project(project))).to be(false)
      expect(described_class.ref_request?(described_class.start_for_merge_request(merge_request))).to be(false)
    end
  end

  describe '.request_key' do
    it 'returns the Redis cache key for a single pipeline creation request' do
      request_id = described_class.generate_id

      expect(described_class.request_key(project, request_id)).to eq(
        "pipeline_creation:projects:{#{project.id}}:request:{#{request_id}}"
      )
    end
  end

  describe '.merge_request_key' do
    it 'returns the Redis cache key for the project' do
      expect(described_class.merge_request_key(merge_request)).to eq(
        "pipeline_creation:projects:{#{merge_request.project.id}}:mrs:{#{merge_request.id}}"
      )
    end
  end

  describe '.generate_id' do
    it 'creates a unique ID for the pipeline creation' do
      expect(SecureRandom).to receive(:uuid)

      described_class.generate_id
    end
  end

  describe '.merge_request_from_key' do
    context 'when key is nil' do
      it 'returns nil' do
        expect(described_class.merge_request_from_key(nil)).to be_nil
      end
    end

    context 'when key does not match the expected format' do
      it 'returns nil' do
        expect(described_class.merge_request_from_key('invalid_key')).to be_nil
      end
    end

    context 'when key matches format but MR does not exist' do
      it 'returns nil' do
        key = "pipeline_creation:projects:{123}:mrs:{999999999}"
        expect(described_class.merge_request_from_key(key)).to be_nil
      end
    end

    context 'when key matches format and MR exists' do
      it 'returns the merge request' do
        key = described_class.merge_request_key(merge_request)
        expect(described_class.merge_request_from_key(key)).to eq(merge_request)
      end
    end
  end

  describe '.start_for_ref' do
    let_it_be(:ref_project) { create(:project) }
    let(:ref) { 'refs/heads/feature-branch' }

    it 'stores a pipeline creation for the ref and returns its key and ID' do
      allow(SecureRandom).to receive(:uuid).and_return('test-id')

      request = described_class.start_for_ref(ref_project, ref)

      expect(request).to match({
        'key' => described_class.ref_key(ref_project, ref),
        'id' => 'test-id',
        'started_at' => a_kind_of(Numeric)
      })
      expect(described_class.hget(request)).to match(
        { 'status' => 'in_progress', 'id' => 'test-id', 'started_at' => a_kind_of(Numeric) }
      )
    end

    it 'allows multiple requests for the same ref' do
      allow(SecureRandom).to receive(:uuid).and_return('test-id-1')
      request1 = described_class.start_for_ref(ref_project, ref)

      allow(SecureRandom).to receive(:uuid).and_return('test-id-2')
      request2 = described_class.start_for_ref(ref_project, ref)

      described_class.succeeded(request1, 1)

      expect(described_class.hget(request1)).to be_nil
      expect(described_class.hget(request2)).to include('status' => 'in_progress', 'id' => 'test-id-2')
    end
  end

  describe '.pipeline_creating_for_ref?' do
    let_it_be(:ref_project) { create(:project) }
    let(:ref) { 'refs/heads/feature-branch' }

    context 'when there are in-progress pipeline creations for the ref' do
      it 'returns true' do
        described_class.start_for_ref(ref_project, ref)

        expect(described_class.pipeline_creating_for_ref?(ref_project, ref)).to be true
      end
    end

    context 'when all pipeline creations for the ref are completed' do
      it 'returns false' do
        request = described_class.start_for_ref(ref_project, ref)
        described_class.succeeded(request, 1)

        expect(described_class.pipeline_creating_for_ref?(ref_project, ref)).to be false
      end
    end

    context 'when there are no pipeline creations for the ref' do
      it 'returns false' do
        expect(described_class.pipeline_creating_for_ref?(ref_project, ref)).to be false
      end
    end

    context 'when some requests are completed and some are in progress' do
      it 'returns true' do
        request1 = described_class.start_for_ref(ref_project, ref)
        described_class.start_for_ref(ref_project, ref)
        described_class.succeeded(request1, 1)

        expect(described_class.pipeline_creating_for_ref?(ref_project, ref)).to be true
      end
    end

    context 'when an in-progress request is older than the expiration time' do
      it 'returns false even though later writes kept the key alive' do
        described_class.start_for_ref(ref_project, ref)

        travel_to((described_class::REDIS_EXPIRATION_TIME + 1).seconds.from_now) do
          later_request = described_class.start_for_ref(ref_project, ref)
          described_class.succeeded(later_request, 1)

          expect(described_class.for_ref(ref_project, ref).size).to eq(1)
          expect(described_class.pipeline_creating_for_ref?(ref_project, ref)).to be false
        end
      end
    end
  end

  describe '.for_ref' do
    let_it_be(:ref_project) { create(:project) }
    let(:ref) { 'refs/heads/feature-branch' }

    it 'returns the requests still in flight for the ref' do
      allow(SecureRandom).to receive(:uuid).and_return('test-id-1')
      request1 = described_class.start_for_ref(ref_project, ref)

      allow(SecureRandom).to receive(:uuid).and_return('test-id-2')
      described_class.start_for_ref(ref_project, ref)

      described_class.succeeded(request1, 1)

      requests = described_class.for_ref(ref_project, ref)

      expect(requests).to contain_exactly(
        { 'status' => 'in_progress', 'id' => 'test-id-2', 'started_at' => a_kind_of(Numeric) }
      )
    end
  end

  describe '.ref_key' do
    let_it_be(:ref_project) { create(:project) }

    it 'returns the Redis cache key for the ref' do
      ref = 'refs/heads/feature-branch'
      ref_hash = Digest::SHA256.hexdigest(ref)

      expect(described_class.ref_key(ref_project, ref)).to eq(
        "pipeline_creation:projects:{#{ref_project.id}}:ref:{#{ref_hash}}"
      )
    end
  end
end
