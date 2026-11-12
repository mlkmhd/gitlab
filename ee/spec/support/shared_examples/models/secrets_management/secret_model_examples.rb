# frozen_string_literal: true

RSpec.shared_examples 'a secret custom metadata value' do |attribute|
  describe "#{attribute} bytesize" do
    it 'allows a value of 512 bytes' do
      secret.public_send(:"#{attribute}=", 'a' * 512)

      expect(secret).to be_valid
    end

    it 'rejects a value of 513 bytes' do
      secret.public_send(:"#{attribute}=", 'a' * 513)

      expect(secret).not_to be_valid
      expect(secret.errors[attribute]).to include('is too long (513 B). The maximum size is 512 B.')
    end

    it 'counts bytes, not characters' do
      # 200 characters, but 600 bytes
      secret.public_send(:"#{attribute}=", '密' * 200)

      expect(secret).not_to be_valid
      expect(secret.errors[attribute]).to include('is too long (600 B). The maximum size is 512 B.')
    end
  end

  describe "#{attribute} printable characters" do
    it 'allows letters, marks, numbers, punctuation, symbols and spaces in any script' do
      secret.public_send(:"#{attribute}=", "Café_1, 密码 ✓ (prod) - e\u0301")

      expect(secret).to be_valid
    end

    ["line1\nline2", "col1\tcol2", "non\u00A0breaking", "zero\u200Bwidth"].each do |value|
      it "rejects #{value.inspect}" do
        secret.public_send(:"#{attribute}=", value)

        expect(secret).not_to be_valid
        expect(secret.errors[attribute]).to include('contains unprintable characters.')
      end
    end
  end
end

RSpec.shared_examples 'a secret model' do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }

    describe 'name format' do
      it 'allows valid names' do
        valid_names = %w[SECRET_KEY test_123 ABC123 secret]

        valid_names.each do |name|
          secret.name = name
          expect(secret).to be_valid
        end
      end

      it 'rejects invalid names' do
        invalid_names = ['secret-key', 'secret.key', 'secret key', '123-secret', 'secret!']

        invalid_names.each do |name|
          secret.name = name
          expect(secret).not_to be_valid
          expect(secret.errors[:name]).to include("can contain only letters, digits and '_'.")
        end
      end
    end

    it_behaves_like 'a secret custom metadata value', :description
    it { is_expected.to allow_value(nil).for(:description) }
    it { is_expected.not_to allow_value('').for(:description) }

    it_behaves_like 'a secret custom metadata value', :environment
  end

  describe 'attributes' do
    it 'has expected attributes' do
      expect(secret).to have_attributes(
        name: 'TEST_SECRET',
        metadata_version: 0
      )
    end
  end

  describe 'dirty tracking' do
    it 'tracks changes to environment' do
      expect(secret.environment_changed?).to be_falsey

      secret.environment = 'staging'
      expect(secret.environment_changed?).to be_truthy
      expect(secret.environment_was).to eq('production')
    end
  end

  describe '#==' do
    let(:other_secret) { secret.dup }

    it 'returns true for secrets with same attributes' do
      expect(secret).to eq(other_secret)
    end

    it 'returns false for secrets with different attributes' do
      other_secret.name = 'DIFFERENT'
      expect(secret).not_to eq(other_secret)
    end

    it 'returns false for different object types' do
      expect(secret).not_to eq('not a secret')
    end
  end

  describe '#status' do
    subject(:status_subject) { secret }

    let(:threshold) { described_class::STALE_THRESHOLD }

    shared_examples 'status is' do |expected|
      it "returns #{expected}" do
        expect(status_subject.status).to eq(expected)
      end
    end

    shared_examples 'validates status' do |expected|
      it "validates correctly for #{expected}" do
        expect(status_subject).to be_valid
      end

      it "validates update rules for #{expected}" do
        if expected == 'COMPLETED'
          expect(status_subject.valid_for_update?).to be_truthy
        else
          expect(status_subject.valid_for_update?).to be_falsey
        end
      end
    end

    context 'when creation timestamps are evaluated (no updates yet)', :freeze_time do
      let(:update_started_at)   { nil }
      let(:update_completed_at) { nil }

      before do
        secret.update_started_at   = update_started_at.to_s
        secret.update_completed_at = update_completed_at.to_s
        secret.create_started_at   = create_started_at.to_s
        secret.create_completed_at = create_completed_at.to_s
      end

      context 'when both timestamps are nil' do
        let(:create_started_at)   { nil }
        let(:create_completed_at) { nil }

        it_behaves_like 'status is', 'COMPLETED'
        it_behaves_like 'validates status', 'COMPLETED'
      end

      context 'when started recently and not completed' do
        let(:create_started_at)   { (threshold / 2).ago }
        let(:create_completed_at) { nil }

        it_behaves_like 'status is', 'CREATE_IN_PROGRESS'
        it_behaves_like 'validates status', 'CREATE_IN_PROGRESS'
      end

      context 'when started exactly at threshold' do
        let(:create_started_at)   { threshold.ago }
        let(:create_completed_at) { nil }

        it_behaves_like 'status is', 'CREATE_STALE'
        it_behaves_like 'validates status', 'CREATE_STALE'
      end

      context 'when started long ago (stale)' do
        let(:create_started_at)   { (threshold * 2).ago }
        let(:create_completed_at) { nil }

        it_behaves_like 'status is', 'CREATE_STALE'
        it_behaves_like 'validates status', 'CREATE_STALE'
      end

      context 'when completed normally' do
        let(:create_started_at)   { 6.minutes.ago }
        let(:create_completed_at) { 5.minutes.ago }

        it_behaves_like 'status is', 'COMPLETED'
        it_behaves_like 'validates status', 'COMPLETED'
      end
    end

    context 'when update timestamps are evaluated (creation completed and valid)', :freeze_time do
      let(:create_started_at)   { 6.minutes.ago }
      let(:create_completed_at) { 5.minutes.ago }

      before do
        secret.create_started_at   = create_started_at.to_s
        secret.create_completed_at = create_completed_at.to_s
        secret.update_started_at   = update_started_at.to_s
        secret.update_completed_at = update_completed_at.to_s
      end

      context 'when update started recently and is in progress' do
        let(:update_started_at)   { (threshold / 2).ago }
        let(:update_completed_at) { nil }

        it_behaves_like 'status is', 'UPDATE_IN_PROGRESS'
        it_behaves_like 'validates status', 'UPDATE_IN_PROGRESS'
      end

      context 'when update started exactly at threshold' do
        let(:update_started_at)   { threshold.ago }
        let(:update_completed_at) { nil }

        it_behaves_like 'status is', 'UPDATE_STALE'
        it_behaves_like 'validates status', 'UPDATE_STALE'
      end

      context 'when update started long ago and not completed' do
        let(:update_started_at)   { (threshold * 2).ago }
        let(:update_completed_at) { nil }

        it_behaves_like 'status is', 'UPDATE_STALE'
        it_behaves_like 'validates status', 'UPDATE_STALE'
      end

      context 'when update started long ago but completed in time' do
        let(:update_started_at)   { (threshold * 2).ago }
        let(:update_completed_at) { ((threshold * 2) - 1.minute).ago }

        it_behaves_like 'status is', 'COMPLETED'
        it_behaves_like 'validates status', 'COMPLETED'
      end

      context 'when no update timestamps are present' do
        let(:update_started_at)   { nil }
        let(:update_completed_at) { nil }

        it_behaves_like 'status is', 'COMPLETED'
        it_behaves_like 'validates status', 'COMPLETED'
      end
    end
  end
end
