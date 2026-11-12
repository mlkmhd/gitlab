# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddUniversalProgrammingLanguagesLanguageIdNotNullConstraint,
  migration: :gitlab_main_cell_local,
  feature_category: :source_code_management do
  using RSpec::Parameterized::TableSyntax

  let(:connection) { ApplicationRecord.connection }
  let(:constraint_name) { 'check_4e6f0ff707' }
  let(:constraints) do
    Gitlab::Database::PostgresConstraint.check_constraints
      .by_table_identifier('public.programming_languages').where(name: constraint_name)
  end

  let(:language) do
    table(:programming_languages).create!(name: 'Ruby', color: '#701516', created_at: Time.current, language_id: nil)
  end

  subject(:run_migration) { migrate! }

  before do
    connection.execute("ALTER TABLE programming_languages DROP CONSTRAINT IF EXISTS #{constraint_name}")
  end

  describe '#up' do
    context 'when the constraint does not exist' do
      it 'adds and validates the constraint' do
        run_migration

        expect(constraints).to contain_exactly(have_attributes(
          definition: 'CHECK ((language_id IS NOT NULL))', constraint_valid: true
        ))
      end
    end

    context 'when the constraint already exists (as on GitLab.com)' do
      where(:validated) { [true, false] }

      with_them do
        before do
          connection.execute(<<~SQL)
            ALTER TABLE programming_languages
            ADD CONSTRAINT #{constraint_name} CHECK (language_id IS NOT NULL) NOT VALID
          SQL
          connection.execute("ALTER TABLE programming_languages VALIDATE CONSTRAINT #{constraint_name}") if validated
        end

        it 'ensures the constraint is valid' do
          run_migration

          expect(constraints).to contain_exactly(have_attributes(
            definition: 'CHECK ((language_id IS NOT NULL))', constraint_valid: true
          ))
        end
      end
    end

    context 'with leftover NULL language IDs' do
      before do
        language
      end

      it 'fails validation' do
        expect { run_migration }.to raise_error(StandardError, /PG::CheckViolation:.*#{constraint_name}.*is violated/)
      end
    end
  end

  describe '#down' do
    where(:gitlab_com, :constraint_count) do
      true  | 1
      false | 0
    end

    with_them do
      before do
        allow(Gitlab).to receive(:com_except_jh?).and_return(gitlab_com)
      end

      it 'keeps the constraint only on GitLab.com' do
        run_migration

        schema_migrate_down!

        expect(constraints.count).to eq(constraint_count)
      end
    end
  end
end
