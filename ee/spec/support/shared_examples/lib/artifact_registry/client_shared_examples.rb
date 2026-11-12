# frozen_string_literal: true

# label distinguishes invocations that share a status and body_class, which the repositories list has several of. Only
# the repositories read reports list_class, so expect_no_list_class opts a case into asserting the key is absent rather
# than merely unchecked. Endpoints that never report it leave the flag off.
RSpec.shared_examples 'rejecting an unexpected success body' do |status:, body:, body_class:, label: nil,
  list_class: nil, expect_no_list_class: false|
  it "raises UnavailableError for a #{status} carrying a #{body_class} body#{label && " (#{label})"}",
    :aggregate_failures do
    allow(Gitlab::ErrorTracking).to receive(:log_exception)
    stub_request(http_method, request_url).to_return(status: status, body: body, headers: json_headers)

    expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
    expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
      instance_of(described_class::UnavailableError),
      hash_including(
        { status: status, url: base_url, body_class: body_class, list_class: list_class }.compact
      )
    )

    next unless expect_no_list_class

    expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
      instance_of(described_class::UnavailableError), hash_excluding(:list_class)
    )
  end
end

RSpec.shared_examples 'rejecting an invalid argument before any request' do
  it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
    request = stub_ar_list(body: list_response.to_json)

    expect { perform }.to raise_error(ArgumentError)
    expect(token_exchange).not_to have_received(:token_for)
    expect(request).not_to have_been_requested
  end
end
