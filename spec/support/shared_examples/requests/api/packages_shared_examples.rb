# frozen_string_literal: true

RSpec.shared_examples 'deploy token for package GET requests' do
  context 'with deploy token headers' do
    let(:headers) { basic_auth_header(deploy_token.username, deploy_token.token) }

    subject { get api(url), headers: headers }

    before do
      project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
    end

    context 'valid token' do
      it_behaves_like 'returning response status', :success
    end

    context 'invalid token' do
      let(:headers) { basic_auth_header(deploy_token.username, 'bar') }

      it_behaves_like 'returning response status', :unauthorized
    end
  end
end

RSpec.shared_examples 'deploy token for package uploads' do
  context 'with deploy token headers' do
    let(:headers) { basic_auth_header(deploy_token.username, deploy_token.token).merge(workhorse_headers) }

    before do
      project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
    end

    context 'valid token' do
      it_behaves_like 'returning response status', :success
    end

    context 'invalid token' do
      let(:headers) { basic_auth_header(deploy_token.username, 'bar').merge(workhorse_headers) }

      it_behaves_like 'returning response status', :unauthorized
    end
  end
end

RSpec.shared_examples 'does not cause n^2 queries' do
  it 'avoids N^2 database queries' do
    # we create a package to set the baseline for expected queries from 1 package
    create(
      :npm_package, :with_build,
      name: "@#{project.root_namespace.path}/my-package",
      project: project,
      version: "0.0.1"
    )

    control = ActiveRecord::QueryRecorder.new do
      get api(url)
    end

    5.times do |n|
      create(
        :npm_package, :with_build,
        name: "@#{project.root_namespace.path}/my-package",
        project: project,
        version: "#{n}.0.0"
      )
    end

    expect do
      get api(url)
    end.not_to exceed_query_limit(control)
  end

  it 'loads only the newest build info of each package, in one query', :aggregate_failures do
    package_with_history, other_package = create_list(:npm_package, 2, :with_build, project: project)
    create_list(:package_build_info, 2, package: package_with_history)

    loaded_build_infos = 0
    count_build_infos = ->(*, payload) do
      loaded_build_infos += payload[:record_count] if payload[:class_name] == 'Packages::BuildInfo'
    end

    recorder = ActiveSupport::Notifications.subscribed(count_build_infos, 'instantiation.active_record') do
      ActiveRecord::QueryRecorder.new { get api(url) }
    end

    expect(recorder.log.grep(/packages_build_infos/).size).to eq(1)
    expect(loaded_build_infos).to eq(2)
    expect(json_response.find { |package| package['id'] == other_package.id }['pipeline']['id'])
      .to eq(other_package.last_build_info.pipeline_id)
  end
end

RSpec.shared_examples 'job token for package GET requests' do
  context 'with job token headers' do
    let(:headers) { basic_auth_header(::Gitlab::Auth::CI_JOB_USER, job.token) }

    subject { get api(url), headers: headers }

    before do
      project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
      project.add_developer(user)
    end

    context 'valid token' do
      it_behaves_like 'returning response status', :success
    end

    context 'invalid token' do
      let(:headers) { basic_auth_header(::Gitlab::Auth::CI_JOB_USER, 'bar') }

      it_behaves_like 'returning response status', :unauthorized
    end

    context 'invalid user' do
      let(:headers) { basic_auth_header('foo', job.token) }

      it_behaves_like 'returning response status', :unauthorized
    end
  end
end

RSpec.shared_examples 'enforcing read_packages job token policy' do
  it_behaves_like 'enforcing job token policies', :read_packages,
    allow_public_access_for_enabled_project_features: :package_registry do
    let(:headers) { job_basic_auth_header(target_job) }
  end
end

RSpec.shared_examples 'job token for package uploads' do |authorize_endpoint: false, accept_invalid_username: false|
  context 'with job token headers' do
    let(:headers) { basic_auth_header(::Gitlab::Auth::CI_JOB_USER, job.token).merge(workhorse_headers) }

    before do
      project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
      project.add_developer(user)
    end

    context 'valid token' do
      it_behaves_like 'returning response status', :success

      unless authorize_endpoint
        it 'creates a package with build info' do
          expect { subject }.to change { Packages::Package.count }.by(1)

          pkg = ::Packages::Package.order_created
                                   .last

          expect(pkg.build_infos).to be_present
        end
      end
    end

    context 'invalid token' do
      let(:headers) { basic_auth_header(::Gitlab::Auth::CI_JOB_USER, 'bar').merge(workhorse_headers) }

      it_behaves_like 'returning response status', :unauthorized
    end

    context 'invalid user' do
      let(:headers) { basic_auth_header('foo', job.token).merge(workhorse_headers) }

      if accept_invalid_username
        it_behaves_like 'returning response status', :success
      else
        it_behaves_like 'returning response status', :unauthorized
      end
    end
  end
end

RSpec.shared_examples 'a package tracking event' do |category, action, service_ping_context = true|
  let(:context) do
    [
      Gitlab::Tracking::ServicePingContext.new(
        data_source: :redis_hll,
        event: snowplow_gitlab_standard_context[:property]
      ).to_h
    ]
  end

  it "creates a gitlab tracking event #{action}", :snowplow, :aggregate_failures do
    subject

    if service_ping_context
      expect_snowplow_event(
        category: category,
        action: action,
        label: "redis_hll_counters.user_packages.user_packages_total_unique_counts_monthly",
        context: context,
        **snowplow_gitlab_standard_context
      )
    else
      expect_snowplow_event(category: category, action: action, **snowplow_gitlab_standard_context)
    end
  end
end

RSpec.shared_examples 'not a package tracking event' do |category, action|
  it 'does not create a gitlab tracking event', :snowplow, :aggregate_failures do
    subject

    expect_no_snowplow_event category: category, action: action
  end
end

RSpec.shared_examples 'bumping the package last downloaded at field' do
  it 'bumps last_downloaded_at' do
    expect { subject }
      .to change { package.reload.last_downloaded_at }.from(nil).to(instance_of(ActiveSupport::TimeWithZone))
  end
end

RSpec.shared_examples 'a successful package creation' do
  it 'creates a temporary npm package with file' do
    expect { subject }
      .to change { ::Packages::Npm::Package.for_projects(project).count }.by(1)
      .and change { Packages::PackageFile.count }.by(1)

    expect(response).to have_gitlab_http_status(:ok)
  end
end

RSpec.shared_examples 'protected package' do
  it_behaves_like 'returning response status with message', status: :forbidden,
    message: '403 Forbidden - Package protected.'
end

# Expects `subject` to send the authorize request and `maximum_size` to be the plan limit of the format.
# `body` defaults to the JSON that bad_request!(message) renders.
RSpec.shared_examples 'sending the maximum size and its error response to Workhorse' do |
  message: 'File is too large', content_type: 'application/json', body: nil
|
  it 'sends the maximum size and the Rails error response', :aggregate_failures do
    subject

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response['MaximumSize']).to eq(maximum_size)
    expect(json_response['MaximumSizeResponse']).to eq(
      'StatusCode' => 400,
      'ContentType' => content_type,
      'Body' => body || { message: "400 Bad request - #{message}" }.to_json
    )
  end
end

# Including groups define `upload_final_store_path_file`, which sends `final_store_path_file`.
RSpec.shared_context 'with a pending final store path upload' do
  let(:final_store_path) { '@final/aa/bb/pending-final-store-path-upload' }
  let(:packages_bucket) { Gitlab.config.packages.object_store.remote_directory }
  let(:fog_connection) { stub_package_file_object_storage(direct_upload: true) }
  let(:final_store_path_file) do
    object = fog_connection.directories.new(key: packages_bucket).files.create( # rubocop:disable Rails/SaveBang -- Fog API
      key: final_store_path,
      body: 'content'
    )

    fog_to_uploaded_file(object, remote_id: final_store_path)
  end

  before do
    ::Packages::PackageFileUploader.prepare_pending_direct_upload(final_store_path)
  end

  def final_store_path_pending?
    ObjectStorage::PendingDirectUpload.exists?(::Packages::PackageFileUploader.storage_location_identifier,
      final_store_path)
  end

  def final_store_path_object_exists?
    fog_connection.directories.new(key: packages_bucket).files.head(final_store_path).present?
  end
end

RSpec.shared_examples 'discarding a rejected final store path upload' do |status:|
  include_context 'with a pending final store path upload'

  it 'deletes the pending entry and the uploaded object', :clean_gitlab_redis_shared_state, :aggregate_failures do
    upload_final_store_path_file

    expect(response).to have_gitlab_http_status(status)
    expect(final_store_path_pending?).to be(false)
    expect(final_store_path_object_exists?).to be(false)
  end

  context 'when discarding fails' do
    let(:error) { StandardError.new('object storage unavailable') }

    before do
      allow(ObjectStorage::PendingDirectUpload).to receive(:discard).and_raise(error)
    end

    it 'tracks the error and keeps the response', :clean_gitlab_redis_shared_state, :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, project_id: project.id)

      upload_final_store_path_file

      expect(response).to have_gitlab_http_status(status)
    end
  end

  context 'when packages_discard_unstored_direct_uploads is disabled' do
    before do
      stub_feature_flags(packages_discard_unstored_direct_uploads: false)
    end

    it 'keeps the pending entry and the uploaded object', :clean_gitlab_redis_shared_state, :aggregate_failures do
      upload_final_store_path_file

      expect(response).to have_gitlab_http_status(status)
      expect(final_store_path_pending?).to be(true)
      expect(final_store_path_object_exists?).to be(true)
    end
  end
end

RSpec.shared_examples 'keeping a stored final store path upload' do |status:|
  include_context 'with a pending final store path upload'

  it 'completes the pending entry and keeps the uploaded object', :clean_gitlab_redis_shared_state,
    :aggregate_failures do
    upload_final_store_path_file

    expect(response).to have_gitlab_http_status(status)
    expect(final_store_path_pending?).to be(false)
    expect(final_store_path_object_exists?).to be(true)
  end
end
