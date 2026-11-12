# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ci::Runner, :clean_gitlab_redis_shared_state, feature_category: :runner_core do
  include StubGitlabCalls
  include RedisHelpers
  include WorkhorseHelpers

  let(:registration_token) { 'abcdefg123456' }

  before do
    stub_application_setting(ci_job_live_trace_enabled: true)
    stub_gitlab_calls
    allow_any_instance_of(::Ci::Runner).to receive(:cache_attributes)
  end

  describe '/api/v4/runners' do
    describe 'POST /api/v4/runners/verify', :freeze_time, :clean_gitlab_redis_cache do
      let_it_be_with_reload(:runner) { create(:ci_runner, :unregistered, token_expires_at: 3.days.from_now) }

      let(:params) { nil }

      subject(:verify) { post api('/runners/verify'), params: params }

      it_behaves_like 'runner migrations backoff' do
        let(:request) { verify }
      end

      context 'when no token is provided' do
        it 'returns 400 error' do
          verify

          expect(response).to have_gitlab_http_status :bad_request
        end
      end

      context 'when invalid token is provided' do
        let(:params) { { token: 'invalid-token' } }

        it 'returns 403 error' do
          verify

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when valid token is provided' do
        let(:params) { { token: runner.token } }

        context 'with glrt-prefixed token' do
          let_it_be(:registration_token) { 'glrt-abcdefg123456' }
          let_it_be(:runner) do
            create(:ci_runner, :unregistered, registration_type: :authenticated_user,
              token: registration_token, token_expires_at: 3.days.from_now)
          end

          it 'verifies Runner credentials' do
            verify

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response).to eq({
              'id' => runner.id,
              'token' => runner.token,
              'token_expires_at' => runner.token_expires_at.iso8601(3)
            })
          end

          it 'does not update creation_state' do
            expect { verify }.not_to change { runner.reload.creation_state }.from('started')
          end
        end

        it 'verifies Runner credentials' do
          verify

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq(
            'id' => runner.id,
            'token' => runner.token,
            'token_expires_at' => runner.token_expires_at.iso8601(3)
          )
        end

        it 'updates contacted_at' do
          expect { verify }.to change { runner.reload.contacted_at }.from(nil).to(Time.current)
        end

        it 'does not update creation_state' do
          expect { verify }.not_to change { runner.reload.creation_state }.from('started')
        end

        context 'with non-expiring runner token' do
          before do
            runner.update!(token_expires_at: nil)
          end

          it 'verifies Runner credentials' do
            verify

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response).to eq(
              'id' => runner.id,
              'token' => runner.token,
              'token_expires_at' => nil
            )
          end
        end

        it_behaves_like 'storing arguments in the application context for the API' do
          let(:expected_params) { { client_id: "runner/#{runner.id}" } }

          # TODO: remove this once the following issue is resolved
          # https://gitlab.com/gitlab-org/gitlab/-/work_items/599571
          before do
            allow(Gitlab::AppLogger).to receive(:info).with(
              a_hash_including(
                Labkit::Fields::CLASS_NAME => "Ci::Runners::PartitionedTokenFinder"
              )
            )
          end
        end

        context 'with a group runner' do
          let_it_be(:group, freeze: true) { create(:group) }
          let_it_be(:runner, freeze: true) { create(:ci_runner, :group, groups: [group]) }

          it_behaves_like 'storing arguments in the application context for the API' do
            let(:expected_params) { { organization_id: group.organization_id } }
          end
        end

        context 'when system_id is provided' do
          let(:params) { { token: runner.token, system_id: 's_some_system_id' } }

          it 'creates a runner_manager' do
            expect { verify }.to change { Ci::RunnerManager.count }.by(1)
          end

          context 'when the runner reached ci_runner_manager_creation_ceiling', :clean_gitlab_redis_shared_state do
            before do
              Ci::Runners::RunnerManagerCreationCeiling.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])
            end

            it 'responds with 429 for a new system_id without creating a runner_manager' do
              expect { verify }.not_to change { Ci::RunnerManager.count }

              expect(response).to have_gitlab_http_status(:too_many_requests)
              expect(response.headers['Retry-After']).to eq(10.minutes.to_i)
              expect(json_response.dig('message', 'error')).to eq(
                ::API::Ci::Helpers::Runner::RUNNER_MANAGER_CREATION_CEILING_MESSAGE
              )
            end

            it 'still verifies an existing system_id' do
              create(:ci_runner_machine, runner: runner, system_xid: 's_existing_system_id')

              post api('/runners/verify'), params: { token: runner.token, system_id: 's_existing_system_id' }

              expect(response).to have_gitlab_http_status(:ok)
            end
          end

          context 'when the runner already created runner_manager_creation_limit managers',
            :clean_gitlab_redis_rate_limiting do
            def verify_with(system_id)
              post api('/runners/verify'), params: { token: runner.token, system_id: system_id }
            end

            before do
              stub_application_setting(runner_manager_creation_limit: 1)

              verify_with('s_first_system_id')
            end

            it 'responds with 429 for a new system_id without creating a runner_manager' do
              expect { verify }.not_to change { Ci::RunnerManager.count }

              expect(response).to have_gitlab_http_status(:too_many_requests)
              expect(response.headers['Retry-After']).to eq(10.minutes.to_i)
            end

            it 'still verifies an existing system_id' do
              verify_with('s_first_system_id')

              expect(response).to have_gitlab_http_status(:ok)
            end

            it 'still creates a runner_manager for another runner' do
              other_runner = create(:ci_runner)

              expect do
                post api('/runners/verify'), params: { token: other_runner.token, system_id: 's_some_system_id' }
              end.to change { other_runner.runner_managers.count }.by(1)

              expect(response).to have_gitlab_http_status(:ok)
            end

            context 'when runner_manager_creation_limit is set to 0' do
              before do
                stub_application_setting(runner_manager_creation_limit: 0)
              end

              it 'creates the runner_manager' do
                expect { verify }.to change { Ci::RunnerManager.count }.by(1)

                expect(response).to have_gitlab_http_status(:ok)
              end
            end

            context 'when enforce_runner_manager_creation_limit is disabled' do
              before do
                stub_feature_flags(enforce_runner_manager_creation_limit: false)
              end

              it 'creates the runner_manager' do
                expect { verify }.to change { Ci::RunnerManager.count }.by(1)

                expect(response).to have_gitlab_http_status(:ok)
              end
            end
          end
        end
      end

      context 'when the runner organization is in maintenance mode' do
        let_it_be_with_reload(:organization) { create(:organization) }

        let(:params) { { token: runner.token } }

        def request
          verify
        end

        context 'with a group runner' do
          let_it_be(:group) { create(:group, organization: organization) }
          let_it_be_with_reload(:runner) do
            create(:ci_runner, :group, groups: [group], token_expires_at: 3.days.from_now)
          end

          it_behaves_like 'an API request enforcing organization maintenance mode'
        end

        context 'with a project runner' do
          let_it_be(:project) { create(:project, organization: organization) }
          let_it_be_with_reload(:runner) do
            create(:ci_runner, :project, projects: [project], token_expires_at: 3.days.from_now)
          end

          it_behaves_like 'an API request enforcing organization maintenance mode'
        end

        context 'with an instance runner whose organization is not resolved' do
          let_it_be_with_reload(:runner) do
            create(:ci_runner, :instance, token_expires_at: 3.days.from_now)
          end

          before do
            organization.start_maintenance(maintenance_reason: 'migration')
            organization.confirm_maintenance
          end

          it 'is not affected by maintenance mode enforcement' do
            verify

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when non-expired token is provided' do
        let(:params) { { token: runner.token } }

        it 'verifies Runner credentials' do
          runner["token_expires_at"] = 10.days.from_now
          runner.save!
          verify

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq(
            'id' => runner.id,
            'token' => runner.token,
            'token_expires_at' => runner.token_expires_at.iso8601(3)
          )
        end
      end

      context 'when expired token is provided' do
        let(:params) { { token: runner.token } }

        it 'does not verify Runner credentials' do
          runner["token_expires_at"] = 10.days.ago
          runner.save!
          verify

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end
  end
end
