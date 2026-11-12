# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::Cleanup::ExecutePolicyService, feature_category: :package_registry do
  let_it_be(:project) { create(:project) }
  let_it_be_with_reload(:policy) { create(:packages_cleanup_policy, project: project) }

  let(:service) { described_class.new(policy) }

  describe '#execute' do
    subject(:execute) { service.execute }

    context 'when the duplicated files of a package are not next to each other' do
      let_it_be(:package_a) { create(:generic_package, project: project) }
      let_it_be(:package_b) { create(:generic_package, project: project) }
      let_it_be(:file_a1) { create(:package_file, package: package_a, file_name: 'file_name1') }
      let_it_be(:file_b1) { create(:package_file, package: package_b, file_name: 'file_name1') }
      let_it_be(:file_a2) { create(:package_file, package: package_a, file_name: 'file_name1') }

      before do
        policy.update!(keep_n_duplicated_package_files: '1')
        stub_const("#{described_class.name}::PACKAGES_BATCH_SIZE", 1)
      end

      it 'keeps only the most recent package file' do
        expect { execute }.to change { package_a.package_files.installable.count }.from(2).to(1)
          .and not_change { package_b.package_files.installable.count }

        expect(package_a.package_files.installable).to contain_exactly(file_a2)
        expect(execute.payload[:counts]).to eq(
          marked_package_files_total_count: 1,
          unique_package_id_and_file_name_total_count: 1,
          marked_packages_total_count: 0
        )
      end
    end

    context 'with the keep_n_duplicated_files parameter' do
      let_it_be(:package1) { create(:generic_package, project: project) }
      let_it_be(:package2) { create(:generic_package, project: project) }
      let_it_be(:package3) { create(:generic_package, project: project) }
      let_it_be(:package4) { create(:generic_package, :pending_destruction, project: project) }

      let_it_be(:package_file1_1) { create(:package_file, package: package1, file_name: 'file_name1') }
      let_it_be(:package_file1_2) { create(:package_file, package: package1, file_name: 'file_name1') }
      let_it_be(:package_file1_3) { create(:package_file, package: package1, file_name: 'file_name1') }

      let_it_be(:package_file1_4) { create(:package_file, package: package1, file_name: 'file_name2') }
      let_it_be(:package_file1_5) { create(:package_file, package: package1, file_name: 'file_name2') }
      let_it_be(:package_file1_6) { create(:package_file, package: package1, file_name: 'file_name2') }
      let_it_be(:package_file1_7) do
        create(:package_file, :pending_destruction, package: package1, file_name: 'file_name2')
      end

      let_it_be(:package_file2_1) { create(:package_file, package: package2, file_name: 'file_name1') }
      let_it_be(:package_file2_2) { create(:package_file, package: package2, file_name: 'file_name1') }
      let_it_be(:package_file2_3) { create(:package_file, package: package2, file_name: 'file_name1') }
      let_it_be(:package_file2_4) { create(:package_file, package: package2, file_name: 'file_name1') }

      let_it_be(:package_file3_1) { create(:package_file, package: package3, file_name: 'file_name_test') }

      let_it_be(:package_file4_1) do
        create(:package_file, :pending_destruction, package: package4, file_name: 'file_name1')
      end

      let_it_be(:package_file4_2) do
        create(:package_file, :pending_destruction, package: package4, file_name: 'file_name1')
      end

      let(:package_files_1) { package1.package_files.installable }
      let(:package_files_2) { package2.package_files.installable }
      let(:package_files_3) { package3.package_files.installable }

      context 'when set to less than the total number of duplicated files' do
        before do
          # for each package file duplicate, we keep only the most recent one
          policy.update!(keep_n_duplicated_package_files: '1')
        end

        shared_examples 'keeping the most recent package files' do
          let(:response_payload) do
            {
              counts: {
                marked_package_files_total_count: 7,
                unique_package_id_and_file_name_total_count: 3,
                marked_packages_total_count: 0
              },
              timeout: false
            }
          end

          it 'only keeps the most recent package files' do
            expect { execute }.to change { ::Packages::PackageFile.installable.count }.by(-7)

            expect(package_files_1).to contain_exactly(package_file1_3, package_file1_6)
            expect(package_files_2).to contain_exactly(package_file2_4)
            expect(package_files_3).to contain_exactly(package_file3_1)

            expect(execute).to be_success
            expect(execute.message).to eq("Packages cleanup policy executed for project #{project.id}")
            expect(execute.payload).to eq(response_payload)
          end
        end

        it_behaves_like 'keeping the most recent package files'

        context 'when the service needs to loop' do
          before do
            stub_const("#{described_class.name}::PACKAGES_BATCH_SIZE", 1)
          end

          it_behaves_like 'keeping the most recent package files' do
            before do
              expect(::Packages::MarkPackageFilesForDestructionService)
                .to receive(:new).exactly(3).times.and_call_original
            end
          end

          context 'when a timeout is hit' do
            let(:response_payload) do
              {
                counts: {
                  marked_package_files_total_count: 4,
                  unique_package_id_and_file_name_total_count: 3,
                  marked_packages_total_count: 0
                },
                timeout: true
              }
            end

            let(:service_timeout_response) do
              ServiceResponse.error(
                message: 'Timeout while marking package files as pending destruction',
                payload: { marked_package_files_count: 0 }
              )
            end

            before do
              mock_service_timeout(on_iteration: 3)
            end

            it 'keeps part of the most recent package files' do
              expect { execute }
                .to change { ::Packages::PackageFile.installable.count }.by(-4)
                .and not_change { package_files_2.count } # untouched because of the timeout
                .and not_change { package_files_3.count } # untouched because of the timeout

              expect(package_files_1).to contain_exactly(package_file1_3, package_file1_6)
              expect(execute).to be_success
              expect(execute.message).to eq("Packages cleanup policy executed for project #{project.id}")
              expect(execute.payload).to eq(response_payload)
            end

            def mock_service_timeout(on_iteration:)
              execute_call_count = 1
              expect_next_instances_of(::Packages::MarkPackageFilesForDestructionService, 3) do |service|
                expect(service).to receive(:execute).and_wrap_original do |m, *args, **kwargs|
                  # timeout if we are on the right iteration
                  if execute_call_count == on_iteration
                    service_timeout_response
                  else
                    execute_call_count += 1
                    m.call(*args, **kwargs)
                  end
                end
              end
            end
          end
        end
      end

      context 'when set to more than the total number of duplicated files' do
        before do
          # using the biggest value for keep_n_duplicated_package_files
          policy.update!(keep_n_duplicated_package_files: '50')
        end

        it 'keeps all package files' do
          expect { execute }.not_to change { ::Packages::PackageFile.installable.count }
        end
      end

      context 'when set to all' do
        before do
          policy.update!(keep_n_duplicated_package_files: 'all')
        end

        it 'skips the policy' do
          expect(::Packages::MarkPackageFilesForDestructionService).not_to receive(:new)
          expect { execute }.not_to change { ::Packages::PackageFile.installable.count }
        end
      end

      context 'for conan packages' do
        let_it_be(:conan_package) { create(:conan_package, project: project) }
        let(:manifest_filename) { 'conanmanifest.txt' }

        before do
          policy.update!(keep_n_duplicated_package_files: '1')
        end

        context 'with recipe & package manifest files' do
          it 'keeps the two manifest files' do
            expect { execute }.not_to change {
              conan_package.package_files.installable.with_file_name(manifest_filename).count
            }
          end
        end

        context 'with multiple recipe files' do
          let_it_be(:conan_recipe_manifest) do
            create(:conan_package_file, :conan_recipe_manifest, package: conan_package)
          end

          let_it_be(:conan_package_manifest) do
            create(:conan_package_file, :conan_package_manifest, package: conan_package)
          end

          it 'keeps the most recent recipe files' do
            expect { execute }.to change { conan_package.package_files.installable.count }.by(-2)
            expect(conan_package.package_files.installable.with_file_name(manifest_filename)).to contain_exactly(
              conan_recipe_manifest, conan_package_manifest
            )
          end
        end
      end
    end

    context 'with the delete_generic_packages_not_downloaded_in_days parameter' do
      let_it_be(:never_downloaded) { create(:generic_package, project: project, created_at: 40.days.ago) }
      let_it_be(:not_downloaded_recently) do
        create(:generic_package, project: project, created_at: 40.days.ago, last_downloaded_at: 31.days.ago)
      end

      let_it_be(:downloaded_recently) do
        create(:generic_package, project: project, created_at: 40.days.ago, last_downloaded_at: 1.day.ago)
      end

      let_it_be(:created_recently) { create(:generic_package, project: project, created_at: 1.day.ago) }
      let_it_be(:processing) { create(:generic_package, :processing, project: project, created_at: 40.days.ago) }
      let_it_be(:npm_package) { create(:npm_package, project: project, created_at: 40.days.ago) }
      let_it_be(:other_project_package) { create(:generic_package, created_at: 40.days.ago) }

      let_it_be(:uploaded_recently) { create(:generic_package, project: project, created_at: 40.days.ago) }

      let_it_be(:never_downloaded_file) { create(:package_file, package: never_downloaded, created_at: 40.days.ago) }
      let_it_be(:not_downloaded_recently_file) do
        create(:package_file, package: not_downloaded_recently, created_at: 40.days.ago)
      end

      let_it_be(:downloaded_recently_file) do
        create(:package_file, package: downloaded_recently, created_at: 40.days.ago)
      end

      let_it_be(:never_downloaded_processing_file) do
        create(:package_file, :processing, package: never_downloaded, created_at: 40.days.ago)
      end

      # A fixed version, such as `nightly`, that gets a new file without being downloaded.
      let_it_be(:uploaded_recently_old_file) do
        create(:package_file, package: uploaded_recently, created_at: 40.days.ago)
      end

      let_it_be(:uploaded_recently_new_file) do
        create(:package_file, package: uploaded_recently, created_at: 1.hour.ago)
      end

      let(:stale_packages) { [never_downloaded, not_downloaded_recently] }

      before do
        policy.update!(keep_n_duplicated_package_files: 'all', delete_generic_packages_not_downloaded_in_days: 30)
      end

      it 'marks stale generic packages and their files for destruction' do
        expect(execute).to be_success
        expect(execute.payload).to eq(
          counts: {
            marked_package_files_total_count: 3,
            unique_package_id_and_file_name_total_count: 0,
            marked_packages_total_count: 2
          },
          timeout: false
        )

        expect(::Packages::Package.pending_destruction).to match_array(stale_packages)
        expect(::Packages::PackageFile.pending_destruction)
          .to contain_exactly(never_downloaded_file, never_downloaded_processing_file, not_downloaded_recently_file)
      end

      it 'keeps a package that got a new file within the window' do
        execute

        expect(uploaded_recently.reload).not_to be_pending_destruction
        expect(uploaded_recently_new_file.reload).not_to be_pending_destruction
      end

      context 'when the duplicated files cleanup times out' do
        before do
          policy.update!(keep_n_duplicated_package_files: '1')
          allow(service).to receive(:cleanup_duplicated_files).and_return(:timeout)
        end

        it 'still marks stale generic packages' do
          expect(execute.payload[:timeout]).to be(true)
          expect(::Packages::Package.pending_destruction).to match_array(stale_packages)
        end
      end

      context 'when the generic rule times out' do
        before do
          policy.update!(keep_n_duplicated_package_files: '1')
          allow(service).to receive(:delete_generic_packages_not_downloaded).and_return(:timeout)
        end

        it 'skips the duplicated files cleanup' do
          expect(service).not_to receive(:cleanup_duplicated_files)

          expect(execute.payload[:timeout]).to be(true)
        end
      end

      context 'when marking more packages than one update batch' do
        before do
          stub_const("#{described_class.name}::MARK_PACKAGES_FOR_DESTRUCTION_BATCH_SIZE", 1)
        end

        it 'marks all of them' do
          expect(execute.payload[:counts][:marked_packages_total_count]).to eq(2)
          expect(::Packages::Package.pending_destruction).to match_array(stale_packages)
        end

        context 'when the batch deadline passes between update batches' do
          before do
            allow(::Packages::Package).to receive(:id_in).and_wrap_original do |method, ids|
              allow(service).to receive(:batch_deadline).and_return(1.second.ago)
              method.call(ids)
            end
          end

          it 'stops after the current batch and reports a timeout' do
            expect(execute.payload[:timeout]).to be(true)
            expect(execute.payload[:counts][:marked_packages_total_count]).to eq(1)
            expect(::Packages::Package.pending_destruction.count).to eq(1)
          end
        end
      end

      context 'with a delete protection rule matching a stale package' do
        before_all do
          create(:package_protection_rule, project: project, package_type: :generic,
            package_name_pattern: never_downloaded.name, minimum_access_level_for_delete: :owner)
        end

        it 'skips the protected package' do
          execute

          expect(::Packages::Package.pending_destruction).to contain_exactly(not_downloaded_recently)
        end
      end

      context 'with a push-only protection rule matching a stale package' do
        before_all do
          create(:package_protection_rule, project: project, package_type: :generic,
            package_name_pattern: never_downloaded.name, minimum_access_level_for_delete: nil)
        end

        it 'still marks the package' do
          execute

          expect(::Packages::Package.pending_destruction).to match_array(stale_packages)
        end
      end

      context 'when the batch deadline has passed' do
        before do
          allow(service).to receive(:batch_deadline).and_return(1.second.ago)
        end

        it 'stops and reports a timeout' do
          expect(execute.payload[:timeout]).to be(true)
          expect(::Packages::Package.pending_destruction).to be_empty
        end
      end

      context 'when marking package files times out' do
        before do
          allow_next_instance_of(::Packages::MarkPackageFilesForDestructionService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Timeout', payload: { marked_package_files_count: 1 })
            )
          end
        end

        it 'stops without marking the packages' do
          expect(execute.payload[:timeout]).to be(true)
          expect(execute.payload[:counts][:marked_package_files_total_count]).to eq(1)
          expect(::Packages::Package.pending_destruction).to be_empty
        end
      end

      context 'when the service needs to loop' do
        before do
          stub_const("#{described_class.name}::NOT_DOWNLOADED_PACKAGES_BATCH_SIZE", 1)
        end

        it 'marks stale generic packages across batches' do
          execute

          expect(::Packages::Package.pending_destruction).to match_array(stale_packages)
        end
      end

      context 'when the parameter is not set' do
        before do
          policy.update!(delete_generic_packages_not_downloaded_in_days: nil)
        end

        it 'does not mark any packages' do
          expect { execute }.not_to change { ::Packages::Package.pending_destruction.count }
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(packages_cleanup_delete_generic_not_downloaded: false)
        end

        it 'does not mark any packages' do
          expect { execute }.not_to change { ::Packages::Package.pending_destruction.count }
        end
      end
    end

    context 'for maven snapshot packages' do
      let_it_be(:package) { create(:maven_package, project: project, version: '1.0-SNAPSHOT', package_files: []) }

      # created out of build order, so the newest build does not have the highest ids
      # a same-second pair at the top and an older build with the highest number pin the build order
      let_it_be(:build3_files) { snapshot_files('20240102.090000-10', %w[jar pom jar.sha256]) }
      let_it_be(:build1_files) { snapshot_files('20240101.100000-11', %w[jar pom]) }
      let_it_be(:build2_files) { snapshot_files('20240102.090000-9', %w[jar pom]) }
      let_it_be(:metadata_files) { create_list(:package_file, 2, :xml, package: package) }

      let(:installable_files) { package.package_files.installable }

      before do
        policy.update!(keep_n_duplicated_package_files: '1')
      end

      it 'keeps the newest copy of each file and the newest metadata file' do
        expect { execute }.to change { installable_files.count }.by(-5)

        expect(installable_files).to contain_exactly(*build3_files, metadata_files.last)
        expect(execute.payload[:counts]).to eq(
          marked_package_files_total_count: 5,
          unique_package_id_and_file_name_total_count: 3,
          marked_packages_total_count: 0
        )
      end

      context 'with more than one file batch' do
        before do
          stub_const("#{described_class.name}::MAVEN_SNAPSHOT_FILES_BATCH_SIZE", 2)
        end

        it 'ranks each file name across batches' do
          execute

          expect(installable_files).to contain_exactly(*build3_files, metadata_files.last)
        end
      end

      context 'with more than one package batch' do
        let_it_be(:second_package) do
          create(:maven_package, project: project, version: '2.0-SNAPSHOT', package_files: [])
        end

        let_it_be(:second_old_build) do
          create(:package_file, :jar, package: second_package, file_name: 'my-app-2.0-20240101.100000-1.jar')
        end

        let_it_be(:second_new_build) do
          create(:package_file, :jar, package: second_package, file_name: 'my-app-2.0-20240102.100000-2.jar')
        end

        before do
          stub_const("#{described_class.name}::PACKAGES_BATCH_SIZE", 1)
        end

        it 'cleans up the snapshot builds of every package' do
          execute

          expect(installable_files).to contain_exactly(*build3_files, metadata_files.last)
          expect(second_package.package_files.installable).to contain_exactly(second_new_build)
        end
      end

      context 'when keeping two builds' do
        before do
          # The model only allows 1, 10 or more, so skip validation to test the cut at 2 with three builds.
          policy.update_column(:keep_n_duplicated_package_files, '2')
        end

        it 'removes only the oldest build' do
          expect { execute }.to change { installable_files.count }.by(-2)

          expect(installable_files).to match_array(build3_files + build2_files + metadata_files)
        end
      end

      context 'when the newest build is already pending destruction' do
        before_all do
          create(:package_file, :jar, :pending_destruction, package: package,
            file_name: 'my-app-1.0-20240103.090000-12.jar')
        end

        it 'keeps the newest installable build' do
          execute

          expect(installable_files).to contain_exactly(*build3_files, metadata_files.last)
        end
      end

      context 'when a later build only deploys a classifier' do
        let_it_be(:split_package) do
          create(:maven_package, project: project, version: '3.0-SNAPSHOT', package_files: [])
        end

        before_all do
          %w[20240101.100000-5.jar 20240101.100000-5.pom 20240101.110000-6-linux.jar].each do |suffix|
            create(:package_file, :jar, package: split_package, file_name: "my-app-3.0-#{suffix}")
          end
        end

        it 'keeps the newest copy of each file' do
          expect { execute }.not_to change { split_package.package_files.installable.count }
        end
      end

      context 'with a snapshot package in another project' do
        let_it_be(:other_project_package) { create(:maven_package, version: '1.0-SNAPSHOT', package_files: []) }

        before_all do
          %w[20230101.100000-1 20230102.100000-2].each do |build|
            create(:package_file, :jar, package: other_project_package, file_name: "my-app-1.0-#{build}.jar")
          end
        end

        it 'does not touch the other project' do
          expect { execute }.not_to change { other_project_package.package_files.installable.count }
        end
      end

      context 'with a generic package whose version ends in -SNAPSHOT' do
        let_it_be(:generic) { create(:generic_package, project: project, version: '1.0-SNAPSHOT', package_files: []) }

        before_all do
          %w[20230101.100000-1 20230102.100000-2].each do |build|
            create(:package_file, :generic, package: generic, file_name: "my-app-1.0-#{build}.jar")
          end
        end

        it 'does not treat the files as builds' do
          expect { execute }.not_to change { generic.package_files.installable.count }
        end
      end

      context 'when the packages_cleanup_policy_maven_snapshot_builds feature flag is disabled' do
        before do
          stub_feature_flags(packages_cleanup_policy_maven_snapshot_builds: false)
        end

        it 'only removes the older metadata file' do
          expect { execute }.to change { installable_files.count }.by(-1)
        end
      end

      context 'when set to keep more builds' do
        before do
          policy.update!(keep_n_duplicated_package_files: '10')
        end

        it 'keeps all builds' do
          expect { execute }.not_to change { installable_files.count }
        end

        it 'does not list the files of packages with no old builds' do
          expect(service).not_to receive(:remove_old_maven_snapshot_builds_for)

          execute
        end
      end

      context 'when the version is a release' do
        let_it_be(:release) { create(:maven_package, project: project, version: '1.0', package_files: []) }

        before_all do
          %w[20240101.100000-1 20240102.100000-2].each do |build|
            create(:package_file, :jar, package: release, file_name: "my-app-1.0-#{build}.jar")
          end
        end

        it 'does not treat the files as builds' do
          expect { execute }.not_to change { release.package_files.installable.count }
        end
      end

      context 'when a timeout is hit' do
        before do
          # leave one metadata file, so only the snapshot builds call the service
          ::Packages::PackageFile.id_in(metadata_files.first).update_all(status: :pending_destruction)

          allow_next_instance_of(::Packages::MarkPackageFilesForDestructionService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Timeout', payload: { marked_package_files_count: 0 })
            )
          end
        end

        it 'stops and reports the timeout' do
          expect(execute.payload[:timeout]).to be(true)
        end
      end

      context 'when the deadline passes while listing the files' do
        before do
          ::Packages::PackageFile.id_in(metadata_files.first).update_all(status: :pending_destruction)
          stub_const("#{described_class}::MAX_EXECUTION_TIME", -1.second)
        end

        it 'stops before marking any file and reports the timeout' do
          expect(::Packages::MarkPackageFilesForDestructionService).not_to receive(:new)

          expect { execute }.not_to change { installable_files.count }
          expect(execute.payload[:timeout]).to be(true)
        end
      end

      context 'when the version only matches the snapshot suffix in lowercase' do
        let_it_be(:lowercase) { create(:maven_package, project: project, version: '1.0-snapshot', package_files: []) }

        before_all do
          %w[20240101.100000-1 20240102.100000-2].each do |build|
            create(:package_file, :jar, package: lowercase, file_name: "my-app-1.0-#{build}.jar")
          end
        end

        it 'does not treat the files as builds' do
          expect { execute }.not_to change { lowercase.package_files.installable.count }
        end
      end

      def snapshot_files(build, extensions)
        extensions.map do |extension|
          create(:package_file, :jar, package: package, file_name: "my-app-1.0-#{build}.#{extension}")
        end
      end
    end
  end
end
