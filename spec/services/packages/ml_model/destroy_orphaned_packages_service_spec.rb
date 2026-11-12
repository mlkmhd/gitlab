# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::MlModel::DestroyOrphanedPackagesService, feature_category: :mlops do
  describe '#execute' do
    let_it_be(:project) { create(:project) }
    let_it_be(:orphaned_packages) { create_list(:ml_model_package, 3, :pending_destruction, project: project) }
    let_it_be(:package_with_file) { create(:ml_model_package, :pending_destruction, project: project) }
    let_it_be(:package_file) { create(:package_file, :pending_destruction, package: package_with_file) }
    let_it_be(:other_orphaned_package) { create(:ml_model_package, :pending_destruction) }

    let(:package_ids) { [*orphaned_packages, package_with_file].map(&:id) }

    subject(:execute) { described_class.new(package_ids).execute }

    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)
    end

    it 'destroys the given orphaned packages in batches', :aggregate_failures do
      expect { execute }.to change { Packages::Package.count }.by(-3)

      expect(Packages::Package.id_in(orphaned_packages.map(&:id))).to be_empty
      expect(package_with_file.reload).to be_pending_destruction
      expect(other_orphaned_package.reload).to be_pending_destruction
    end

    context 'when a file is added to a package after the orphan check' do
      let(:package) { orphaned_packages.first }

      before do
        allow(Packages::MlModel::Package).to receive(:lock_orphaned_ids).and_wrap_original do |method, ids, limit|
          method.call(ids, limit).tap do |locked_ids|
            create(:package_file, package: package) if locked_ids.include?(package.id)
          end
        end
      end

      it 'keeps the package and its file', :aggregate_failures do
        expect { execute }.to change { Packages::Package.count }.by(-2)

        expect(package.reload).to be_pending_destruction
        expect(package.package_files.count).to eq(1)
      end
    end

    context 'when the delete fails' do
      let(:error) { ActiveRecord::QueryCanceled.new('canceling statement due to statement timeout') }

      before do
        allow(Packages::MlModel::Package).to receive(:id_in).and_raise(error)
      end

      it 'tracks the error without raising it' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

        expect { execute }.not_to raise_error
      end
    end

    context 'when the time limit passes' do
      before do
        stub_const("#{described_class}::TIME_LIMIT", -1.second)
      end

      it 'stops after the current batch' do
        expect { execute }.to change { Packages::Package.count }.by(-2)
      end
    end
  end
end
