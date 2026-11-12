# frozen_string_literal: true

RSpec.shared_examples 'MLflow|an endpoint that requires authentication' do
  context 'when not authenticated' do
    let(:headers) { {} }

    it "is Unauthorized" do
      is_expected.to have_gitlab_http_status(:unauthorized)
    end
  end

  context 'when user does not have access' do
    let(:access_token) { tokens[:different_user] }

    it "is Not Found" do
      is_expected.to have_gitlab_http_status(:not_found)
    end
  end
end

RSpec.shared_examples 'MLflow|an endpoint that requires read_model_registry' do
  context 'when user does not have read_model_registry' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
                          .with(current_user, :read_model_registry, project)
                          .and_return(false)
    end

    it "is Not Found" do
      is_expected.to have_gitlab_http_status(:not_found)
    end
  end
end

RSpec.shared_examples 'MLflow|an endpoint that requires write_model_registry' do
  context 'when user does not have read_model_registry' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
                          .with(current_user, :write_model_registry, project)
                          .and_return(false)
    end

    it "is Not Found" do
      is_expected.to have_gitlab_http_status(:unauthorized)
    end
  end
end

RSpec.shared_examples 'MLflow|Not Found - Resource Does Not Exist' do
  it "is Resource Does Not Exist", :aggregate_failures do
    is_expected.to have_gitlab_http_status(:not_found)

    expect(json_response).to include({ "error_code" => 'RESOURCE_DOES_NOT_EXIST' })
  end
end

RSpec.shared_examples 'MLflow|Requires api scope and write permission' do
  context 'when user has access but token has wrong scope' do
    let(:access_token) { tokens[:read] }

    it { is_expected.to have_gitlab_http_status(:forbidden) }
  end

  context 'when user has access but is not allowed to write' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
                          .with(current_user, :write_model_experiments, project)
                          .and_return(false)
    end

    it "is Unauthorized" do
      is_expected.to have_gitlab_http_status(:unauthorized)
    end
  end
end

RSpec.shared_examples 'MLflow|Requires read_api scope' do
  context 'when user has access but token has wrong scope' do
    let(:access_token) { tokens[:no_access] }

    it { is_expected.to have_gitlab_http_status(:forbidden) }
  end
end

RSpec.shared_examples 'MLflow|Bad Request' do
  it "is Bad Request" do
    is_expected.to have_gitlab_http_status(:bad_request)
  end
end

RSpec.shared_examples 'MLflow|tracks the internal event' do |event_name, additional_properties = {}|
  it "tracks #{event_name}", :clean_gitlab_redis_shared_state do
    expect { api_response }
      .to trigger_internal_events(event_name)
        .with(category: 'InternalEventTracking', user: current_user, project: project,
          additional_properties: additional_properties)
      .and increment_usage_metrics(
        "counts.count_total_#{event_name}_weekly",
        "counts.count_total_#{event_name}_monthly"
      )
  end
end

RSpec.shared_examples 'MLflow|shared error cases' do
  it_behaves_like 'MLflow|an endpoint that requires authentication'

  context 'when model experiments is unavailable' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
                          .with(current_user, :read_model_experiments, project)
                          .and_return(false)
    end

    it "is Not Found" do
      is_expected.to have_gitlab_http_status(:not_found)
    end
  end
end

RSpec.shared_examples 'MLflow|shared model registry error cases' do
  it_behaves_like 'MLflow|an endpoint that requires authentication'
  it_behaves_like 'MLflow|an endpoint that requires read_model_registry'
end

RSpec.shared_examples 'MLflow|Bad Request on missing required' do |keys|
  keys.each do |key|
    context "when \"#{key}\" is missing" do
      let(:params) { default_params.tap { |p| p.delete(key) } }

      it_behaves_like 'MLflow|Bad Request'
    end
  end
end

RSpec.shared_examples 'MLflow|an invalid request' do
  it_behaves_like 'MLflow|Bad Request'
end

RSpec.shared_examples 'MLflow|an authenticated resource' do
  it_behaves_like 'MLflow|an endpoint that requires authentication'
  it_behaves_like 'MLflow|Requires read_api scope'
end

RSpec.shared_examples 'MLflow|a read-only model registry resource' do
  it_behaves_like 'MLflow|an endpoint that requires authentication'
  it_behaves_like 'MLflow|an endpoint that requires read_model_registry'
end

RSpec.shared_examples 'MLflow|a read/write model registry resource' do
  it_behaves_like 'MLflow|an endpoint that requires authentication'
  it_behaves_like 'MLflow|an endpoint that requires read_model_registry'
  it_behaves_like 'MLflow|an endpoint that requires write_model_registry'
end

# Includers define `access_token`, `perform_request`, `add_records` (records with the same associations as the
# existing ones) and `rendered_count` (how many records the last response renders).
RSpec.shared_examples 'MLflow|a request with constant queries' do
  it 'does not run queries per record', :use_sql_query_cache do
    perform_request # a cold first request runs one-off queries that would inflate the control
    control = ActiveRecord::QueryRecorder.new(skip_cached: false) { perform_request }
    control_count = rendered_count

    add_records

    expect { perform_request }.not_to exceed_all_query_limit(control)
    expect(response).to have_gitlab_http_status(:ok)
    expect(rendered_count).to be > control_count
  end
end

RSpec.shared_examples 'MLflow|an endpoint that validates pagination parameters' do
  context 'with invalid pagination parameters' do
    where(:pagination_params, :message) do
      [
        [{ 'max_results' => 0 }, 'max_results must be at least 1'],
        [{ 'max_results' => -5 }, 'max_results must be at least 1'],
        [{ 'page_token' => 'not-a-token!' }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('not json') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('[1]') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"name":"x","_kd":"n"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"x","_kd":"n"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"99999999999999999999","_kd":"n"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":99999999999999999999,"_kd":"n"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"zzz"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"p"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","unknown":"x"}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","created_at":[1,2]}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","name":{"a":1}}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","created_at":true}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","created_at":"garbage"}') },
          'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","name":5}') }, 'Invalid page_token'],
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","metric_value":"garbage"}') },
          'Invalid page_token'],
        # A cursor for another sort: no endpoint defaults to the `updated_at` order.
        [{ 'page_token' => Base64.urlsafe_encode64('{"id":"1","_kd":"n","updated_at":"2024-01-01T00:00:00Z"}') },
          'Invalid page_token']
      ]
    end

    with_them do
      let(:params) { default_params.merge(pagination_params) }

      it 'returns an invalid parameter error', :aggregate_failures do
        is_expected.to have_gitlab_http_status(:bad_request)
        expect(json_response).to include('error_code' => 'INVALID_PARAMETER_VALUE', 'message' => message)
      end
    end
  end
end
