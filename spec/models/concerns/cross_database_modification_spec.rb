# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CrossDatabaseModification, feature_category: 'database' do
  describe '.transaction' do
    it 'adds the current gitlab schema to gitlab_transactions_stack', :aggregate_failures do
      ApplicationRecord.transaction do
        expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_main)

        Project.first
      end

      expect(ApplicationRecord.gitlab_transactions_stack).to be_empty

      Ci::ApplicationRecord.transaction do
        expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_ci)

        Project.first
      end

      expect(ApplicationRecord.gitlab_transactions_stack).to be_empty

      PackageMetadata::ApplicationRecord.transaction do
        expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_pm)

        Project.first
      end

      expect(ApplicationRecord.gitlab_transactions_stack).to be_empty

      Project.transaction do
        expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_main_org)

        Project.first
      end

      expect(ApplicationRecord.gitlab_transactions_stack).to be_empty

      Ci::Pipeline.transaction do
        expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_ci)

        Project.first
      end

      expect(ApplicationRecord.gitlab_transactions_stack).to be_empty

      ApplicationRecord.transaction do
        expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_main)

        Ci::Pipeline.transaction do
          expect(ApplicationRecord.gitlab_transactions_stack).to contain_exactly(:gitlab_main, :gitlab_ci)

          Project.first
        end
      end

      expect(ApplicationRecord.gitlab_transactions_stack).to be_empty
    end

    it 'yields' do
      expect { |block| ApplicationRecord.transaction(&block) }.to yield_control
    end

    # Feature specs share one connection between the test thread and the Puma thread,
    # so the test thread can roll back a transaction that a request opened.
    context 'when another thread rolls back the transaction' do
      it 'removes the schema from the stack of the thread that opened the transaction', :aggregate_failures do
        opened = Queue.new
        resume = Queue.new

        request_thread = Thread.new do
          Project.transaction do
            opened << Project.connection.current_transaction.records.last
            resume.pop
          end

          ApplicationRecord.gitlab_transactions_stack.dup
        end

        opened.pop.rolledback!
        resume << true

        expect(request_thread.value).to be_empty
        expect(ApplicationRecord.gitlab_transactions_stack).to be_empty
      end
    end
  end
end
