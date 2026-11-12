# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::GitlabCom::DuoCoreTodoNotificationWorker, feature_category: :acquisition do
  it 'deduplicates scheduled jobs until executed', :aggregate_failures do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include({ including_scheduled: true })
  end

  it 'defers on the todos table health signal' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org, tables: [:todos], delay_by: 1.minute
    )
  end

  describe '#perform' do
    let_it_be(:users) { create_list(:user, 3) }
    let_it_be_with_reload(:namespace) { create(:group, developers: users) }
    let(:namespace_id) { namespace.id }

    subject(:perform) { described_class.new.perform(namespace_id) }

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [namespace_id] }
    end

    it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed

    context 'when duo core features are enabled' do
      context 'when namespace exists' do
        before_all do
          namespace.namespace_settings.update!(duo_core_features_enabled: true)
        end

        it 'creates todos for eligible users' do
          create(:user) # unrelated user who should not receive a todo

          expect { perform }.to change { Todo.count }.by(3)

          expect(Todo.all.pluck(:user_id)).to match_array(users.map(&:id))
        end

        context 'when the kill switch is disabled', :clean_gitlab_redis_feature_flag, stub_feature_flags: false do
          before do
            Feature.disable(:process_duo_core_todo_notifications)
          end

          it 'does not create todos' do
            expect(GitlabSubscriptions::AddOnEligibleUsersFinder).not_to receive(:new)

            expect { perform }.not_to change { Todo.count }
          end
        end

        context 'when processing is stopped after the first batch' do
          let(:batches) { [users.first(2), users.last(1)] }

          before do
            relation = instance_double(ActiveRecord::Relation)
            allow(relation).to receive(:find_in_batches).and_yield(batches.first).and_yield(batches.last)

            allow_next_instance_of(GitlabSubscriptions::AddOnEligibleUsersFinder) do |finder|
              allow(finder).to receive(:execute).and_return(relation)
            end

            allow_next_instance_of(TodoService) do |service|
              allow(service).to receive(:duo_core_access_granted).and_wrap_original do |method, batch|
                method.call(batch)
                stop_processing
              end
            end
          end

          context 'when the kill switch is disabled', :clean_gitlab_redis_feature_flag, stub_feature_flags: false do
            let(:stop_processing) { Feature.disable(:process_duo_core_todo_notifications) }

            it 'creates todos only for the first batch' do
              expect { perform }.to change { Todo.count }.by(2)
            end
          end

          context 'when duo core features are disabled' do
            let(:stop_processing) { namespace.namespace_settings.update!(duo_core_features_enabled: false) }

            it 'creates todos only for the first batch' do
              expect { perform }.to change { Todo.count }.by(2)
            end
          end

          context 'when the namespace is deleted' do
            let(:stop_processing) { allow(Namespace).to receive(:find_by_id).with(namespace.id).and_return(nil) }

            it 'creates todos only for the first batch' do
              expect { perform }.to change { Todo.count }.by(2)
            end
          end

          context 'when another process disables the setting after a batch that creates no todos',
            :use_sql_query_cache do
            # A batch that creates no todos leaves the query cache intact. `dirties: false` keeps this
            # write from clearing it, like a write from another process.
            let(:stop_processing) do
              NamespaceSetting.uncached(dirties: false) do
                namespace.namespace_settings.update!(duo_core_features_enabled: false)
              end
            end

            before do
              batches.first.each { |user| create(:todo, :duo_core_access, user: user) }
            end

            it 'stops before the next batch' do
              expect { perform }.not_to change { Todo.count }
            end
          end

          context 'when the kill switch is disabled by another process with a memoized flipper',
            :clean_gitlab_redis_feature_flag, :request_store, stub_feature_flags: false do
            # A thread has no request store, like another Sidekiq process, so this write cannot reset our memo.
            let(:stop_processing) { Thread.new { Feature.disable(:process_duo_core_todo_notifications) }.join }

            it 'creates todos only for the first batch' do
              expect { perform }.to change { Todo.count }.by(2)
            end
          end
        end
      end

      context 'when namespace does not exist' do
        let(:namespace_id) { non_existing_record_id }

        it 'does not create todos and exist gracefully' do
          expect { perform }.not_to change { Todo.count }
        end
      end
    end

    context 'when duo core features are disabled' do
      before_all do
        namespace.namespace_settings.update!(duo_core_features_enabled: false)
      end

      it 'does not create todos' do
        expect { perform }.not_to change { Todo.count }
      end
    end
  end
end
