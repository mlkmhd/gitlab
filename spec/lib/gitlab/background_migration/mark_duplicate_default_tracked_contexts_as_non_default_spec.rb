# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::MarkDuplicateDefaultTrackedContextsAsNonDefault,
  feature_category: :vulnerability_management do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:routes) { table(:routes) }
  let(:tracked_contexts) { table(:security_project_tracked_contexts, database: :sec) }

  let!(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let(:root_refs) { {} }
  let(:sub_batch_size) { 100 }

  let(:migration) do
    described_class.new(
      start_cursor: [tracked_contexts.minimum(:id)],
      end_cursor: [tracked_contexts.maximum(:id)],
      batch_table: :security_project_tracked_contexts,
      batch_column: :id,
      sub_batch_size: sub_batch_size,
      pause_ms: 0,
      connection: SecApplicationRecord.connection
    )
  end

  subject(:perform_migration) { migration.perform }

  before do
    allow(described_class::Repository).to receive(:new).and_wrap_original do |original, full_path, container, **kwargs|
      original.call(full_path, container, **kwargs).tap do |repository|
        allow(repository).to receive(:root_ref) do
          root_ref = root_refs[container.id]
          root_ref = root_ref.call if root_ref.respond_to?(:call)
          root_ref.is_a?(Exception) ? raise(root_ref) : root_ref
        end
      end
    end
  end

  describe '#perform' do
    let!(:project) { create_project('project') }

    context 'when root_ref matches one of the default contexts' do
      let!(:old_default) { create_tracked_context(project, 'master', is_default: true, created_at: 2.days.ago) }
      let!(:real_default) { create_tracked_context(project, 'main', is_default: true, created_at: 1.day.ago) }

      before do
        root_refs[project.id] = 'main'
      end

      it 'keeps the context matching root_ref as default and flips the rest', :aggregate_failures do
        perform_migration

        expect(default_names(project)).to contain_exactly('main')
        expect(tracked_contexts.where(project_id: project.id).count).to eq(2)
      end

      it 'logs the kept and flipped contexts' do
        allow(Gitlab::BackgroundMigration::Logger).to receive(:info)

        perform_migration

        expect(Gitlab::BackgroundMigration::Logger).to have_received(:info).with(
          hash_including(
            Labkit::Fields::GL_PROJECT_ID => project.id,
            kept_id: real_default.id,
            flipped_ids: [old_default.id],
            updated_count: 1
          )
        )
      end

      it 'reads the default branch with N+1 Gitaly calls allowed' do
        expect(Gitlab::GitalyClient).to receive(:allow_n_plus_1_calls).and_call_original

        perform_migration
      end

      context 'when another process flips the duplicate first' do
        before do
          root_refs[project.id] = -> do
            tracked_contexts.where(id: old_default.id).update_all(is_default: false)
            'main'
          end
        end

        it 'logs a warning with the updated count', :aggregate_failures do
          allow(Gitlab::BackgroundMigration::Logger).to receive(:warn)

          perform_migration

          expect(default_names(project)).to contain_exactly('main')
          expect(Gitlab::BackgroundMigration::Logger).to have_received(:warn).with(
            hash_including(
              message: 'Marked duplicate default tracked contexts as non-default',
              Labkit::Fields::GL_PROJECT_ID => project.id,
              kept_id: real_default.id,
              flipped_ids: [old_default.id],
              updated_count: 0
            )
          )
        end
      end
    end

    context 'when the duplicates are spread across sub-batches' do
      let(:sub_batch_size) { 1 }

      # Looking up `project_id`s with `DISTINCT` + `LIMIT` would pick the lowest ones in the batch.
      # `project` has the lowest `project_id` but its only default context has the highest id, so it
      # would keep taking the place of the projects with duplicates.
      let!(:other_project) { create_project('other-project') }
      let!(:third_project) { create_project('third-project') }

      let!(:other_old_default) do
        create_tracked_context(other_project, 'master', is_default: true, created_at: 2.days.ago)
      end

      let!(:other_real_default) do
        create_tracked_context(other_project, 'main', is_default: true, created_at: 1.day.ago)
      end

      let!(:third_old_default) do
        create_tracked_context(third_project, 'master', is_default: true, created_at: 2.days.ago)
      end

      let!(:third_real_default) do
        create_tracked_context(third_project, 'main', is_default: true, created_at: 1.day.ago)
      end

      let!(:single_default) { create_tracked_context(project, 'main', is_default: true) }

      before do
        root_refs[other_project.id] = 'main'
        root_refs[third_project.id] = 'main'
      end

      it 'fixes every project with duplicates and leaves the single default alone', :aggregate_failures do
        perform_migration

        expect(default_names(other_project)).to contain_exactly('main')
        expect(default_names(third_project)).to contain_exactly('main')
        expect(default_names(project)).to contain_exactly('main')
      end
    end

    shared_examples 'leaves the project unchanged and logs it' do
      it 'keeps every default context and logs the project', :aggregate_failures do
        allow(Gitlab::BackgroundMigration::Logger).to receive(:warn)

        expect { perform_migration }.not_to change { default_names(skipped_project).sort }

        expect(Gitlab::BackgroundMigration::Logger).to have_received(:warn).with(
          hash_including(
            message: 'Skipped duplicate default tracked contexts with no default branch match',
            Labkit::Fields::GL_PROJECT_ID => skipped_project.id,
            tracked_context_ids: match_array(tracked_contexts.where(project_id: skipped_project.id).pluck(:id))
          )
        )
      end
    end

    context 'when root_ref matches none of the default contexts' do
      let(:skipped_project) { project }

      before do
        create_tracked_context(project, 'old', is_default: true, created_at: 2.days.ago)
        create_tracked_context(project, 'new', is_default: true, created_at: 1.day.ago)
        root_refs[project.id] = 'renamed'
      end

      it_behaves_like 'leaves the project unchanged and logs it'
    end

    context 'when root_ref only matches a tag context' do
      let(:skipped_project) { project }

      before do
        create_tracked_context(project, 'old', is_default: true, created_at: 2.days.ago)
        create_tracked_context(project, 'main', is_default: true, created_at: 1.day.ago, context_type: 2)
        root_refs[project.id] = 'main'
      end

      it_behaves_like 'leaves the project unchanged and logs it'
    end

    context 'when root_ref is nil' do
      let(:skipped_project) { project }

      before do
        create_tracked_context(project, 'a', is_default: true, created_at: 2.days.ago)
        create_tracked_context(project, 'b', is_default: true, created_at: 1.day.ago)
      end

      it_behaves_like 'leaves the project unchanged and logs it'
    end

    context 'when the repository does not exist' do
      let(:skipped_project) { project }

      before do
        create_tracked_context(skipped_project, 'a', is_default: true, created_at: 2.days.ago)
        create_tracked_context(skipped_project, 'b', is_default: true, created_at: 1.day.ago)
        allow(described_class::Repository).to receive(:new).and_call_original
      end

      it_behaves_like 'leaves the project unchanged and logs it'

      context 'with legacy storage' do
        let(:skipped_project) { create_project('legacy-project', storage_version: 0) }

        it_behaves_like 'leaves the project unchanged and logs it'
      end
    end

    context 'when the project does not exist' do
      let(:skipped_project) { Struct.new(:id).new(non_existing_record_id) }

      before do
        create_tracked_context(skipped_project, 'a', is_default: true, created_at: 2.days.ago)
        create_tracked_context(skipped_project, 'b', is_default: true, created_at: 1.day.ago)
      end

      it_behaves_like 'leaves the project unchanged and logs it'
    end

    context 'when Gitaly raises an error' do
      let!(:oldest_default) { create_tracked_context(project, 'a', is_default: true, created_at: 2.days.ago) }
      let!(:real_default) { create_tracked_context(project, 'main', is_default: true, created_at: 1.day.ago) }

      let!(:other_project) { create_project('other-project') }
      let!(:other_old_default) do
        create_tracked_context(other_project, 'master', is_default: true, created_at: 2.days.ago)
      end

      let!(:other_real_default) do
        create_tracked_context(other_project, 'main', is_default: true, created_at: 1.day.ago)
      end

      before do
        root_refs[other_project.id] = 'main'
      end

      shared_examples 'skips the project' do |error_class|
        it 'logs and skips the project without failing the batch', :aggregate_failures do
          expect(Gitlab::BackgroundMigration::Logger).to receive(:warn).with(
            hash_including(
              message: 'Skipped duplicate default tracked contexts after an error reading the default branch',
              Labkit::Fields::GL_PROJECT_ID => project.id,
              tracked_context_ids: contain_exactly(oldest_default.id, real_default.id),
              Labkit::Fields::ERROR_TYPE => error_class
            )
          )

          expect { perform_migration }.not_to raise_error

          expect(default_names(project)).to contain_exactly('a', 'main')
          expect(default_names(other_project)).to contain_exactly('main')
        end
      end

      context 'with a command error' do
        before do
          root_refs[project.id] = Gitlab::Git::CommandError.new('boom')
        end

        it_behaves_like 'skips the project', 'Gitlab::Git::CommandError'
      end

      context 'with a missing storage' do
        before do
          root_refs[project.id] = RuntimeError.new('storage not found')
        end

        it_behaves_like 'skips the project', 'RuntimeError'
      end

      context 'with a transient error' do
        before do
          root_refs[project.id] = Gitlab::Git::CommandTimedOut.new('timed out')
        end

        it 're-raises so the batch is retried', :aggregate_failures do
          expect { perform_migration }.to raise_error(Gitlab::Git::CommandTimedOut)

          expect(default_names(project)).to contain_exactly('a', 'main')
        end
      end

      context 'with a command error caused by Gitaly being unavailable' do
        before do
          root_refs[project.id] = Gitlab::Git::CommandError.new(GRPC::Unavailable.new('Gitaly is down'))
        end

        it 're-raises so the batch is retried', :aggregate_failures do
          expect { perform_migration }.to raise_error(Gitlab::Git::CommandError)

          expect(default_names(project)).to contain_exactly('a', 'main')
        end
      end

      context 'with a code error' do
        where(:error) do
          [
            NoMethodError.new("undefined method 'foo' for nil"),
            NameError.new('uninitialized constant Foo'),
            TypeError.new('no implicit conversion of nil into String')
          ]
        end

        with_them do
          before do
            root_refs[project.id] = error
          end

          it 're-raises so the batch fails', :aggregate_failures do
            expect { perform_migration }.to raise_error(error.class)

            expect(default_names(project)).to contain_exactly('a', 'main')
          end
        end
      end
    end

    context 'with a database error while building the project path' do
      let!(:oldest_default) { create_tracked_context(project, 'a', is_default: true, created_at: 2.days.ago) }
      let!(:real_default) { create_tracked_context(project, 'main', is_default: true, created_at: 1.day.ago) }

      where(:error) do
        [
          ActiveRecord::QueryCanceled.new('canceling statement due to statement timeout'),
          ActiveRecord::ConnectionNotEstablished.new('connection lost'),
          ActiveRecord::ConnectionFailed.new('server closed the connection unexpectedly')
        ]
      end

      with_them do
        before do
          root_refs[project.id] = 'main'

          # Spec projects have no route row, so full_path goes through build_full_path and reads the parent.
          allow_next_found_instance_of(described_class::Project) do |found_project|
            allow(found_project).to receive(:parent).and_raise(error)
          end
        end

        it 're-raises so the batch is retried', :aggregate_failures do
          expect { perform_migration }.to raise_error(error.class)

          expect(default_names(project)).to contain_exactly('a', 'main')
        end
      end
    end

    context 'when a project has a single default context' do
      let!(:default_context) { create_tracked_context(project, 'main', is_default: true) }
      let!(:non_default_context) { create_tracked_context(project, 'feature', is_default: false) }

      it 'does not change any context and does not call Gitaly' do
        expect(described_class::Repository).not_to receive(:new)

        expect { perform_migration }.not_to change { tracked_contexts.order(:id).pluck(:is_default, :updated_at) }
      end
    end

    context 'with non-default contexts on a project with duplicates' do
      let!(:old_default) { create_tracked_context(project, 'master', is_default: true, created_at: 2.days.ago) }
      let!(:real_default) { create_tracked_context(project, 'main', is_default: true, created_at: 1.day.ago) }
      let!(:non_default_context) { create_tracked_context(project, 'feature', is_default: false) }

      before do
        root_refs[project.id] = 'main'
      end

      it 'does not touch the non-default context' do
        expect { perform_migration }.not_to change { non_default_context.reload.attributes }
      end
    end

    context 'when run twice' do
      let!(:first_default) { create_tracked_context(project, 'a', is_default: true, created_at: 3.days.ago) }
      let!(:second_default) { create_tracked_context(project, 'b', is_default: true, created_at: 2.days.ago) }
      let!(:real_default) { create_tracked_context(project, 'main', is_default: true, created_at: 1.day.ago) }

      before do
        root_refs[project.id] = 'main'
      end

      it 'is idempotent', :aggregate_failures do
        perform_migration

        expect(default_names(project)).to contain_exactly('main')

        expect { migration.perform }.not_to change { tracked_contexts.order(:id).pluck(:is_default, :updated_at) }
      end
    end

    it 'never deletes tracked contexts' do
      create_tracked_context(project, 'a', is_default: true, created_at: 2.days.ago)
      create_tracked_context(project, 'b', is_default: true, created_at: 1.day.ago)

      expect { perform_migration }.not_to change { tracked_contexts.count }
    end
  end

  describe 'project routes' do
    let!(:project) { create_project('project') }

    before do
      routes.create!(
        source_id: project.id,
        source_type: 'Project',
        namespace_id: project.project_namespace_id,
        path: 'project/project',
        name: 'project / project'
      )
    end

    it 'preloads the route that matches the project', :aggregate_failures do
      loaded_project = described_class::Project.preload(:route).find(project.id)

      expect(loaded_project.route.path).to eq('project/project')
      expect(loaded_project.full_path).to eq('project/project')
    end
  end

  def create_project(path, storage_version: 2)
    namespace = namespaces.create!(name: path, path: path, organization_id: organization.id)

    projects.create!(
      name: path,
      path: path,
      namespace_id: namespace.id,
      project_namespace_id: namespace.id,
      organization_id: organization.id,
      storage_version: storage_version
    )
  end

  def create_tracked_context(project, context_name, is_default:, created_at: Time.current, context_type: 1)
    tracked_contexts.create!(
      project_id: project.id,
      context_name: context_name,
      context_type: context_type,
      state: 2,
      is_default: is_default,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def default_names(project)
    tracked_contexts.where(project_id: project.id, is_default: true).pluck(:context_name)
  end
end
