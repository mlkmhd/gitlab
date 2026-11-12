# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:secrets_management:openbao', :silence_stdout, feature_category: :secrets_management do
  before do
    Rake.application.rake_require 'tasks/gitlab/secrets_management/openbao'
  end

  describe 'recovery_key:store' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:recovery_key:store') }

    let(:encoded_jwt) { "encoded_jwt.a.key" }
    let(:returned_recovery_key) { "ffffffffff38b1f97d18a63fb044015a9c776aa7f6c0e071c22bd25c062e586e" }
    let(:active_recovery_key) { SecretsManagement::RecoveryKey.active.take }
    let(:returned_keys) { [returned_recovery_key] }
    let(:recovery_response) do
      {
        "request_id" => "e1dfe66c-e97b-9ff3-acaf-3a6b24c64250",
        "lease_id" => "",
        "renewable" => false,
        "lease_duration" => 0,
        "data" => {
          "backup" => false,
          "complete" => true,
          "keys" => returned_keys,
          "keys_base64" => ["Suei4Rc4sfl9GKY/sEQBWpx3aqf2wOBxwivSXAYuWG4="],
          "n" => 1,
          "pgp_fingerprints" => nil,
          "t" => 1,
          "verification_nonce" => "",
          "verification_required" => false
        },
        "wrap_info" => nil,
        "warnings" => nil,
        "auth" => nil
      }
    end

    before do
      allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
        allow(smj).to receive(:encoded).and_return(encoded_jwt)
      end

      allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
        allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
      end
    end

    it 'saves the returned key to database' do
      expect { task }.to change { SecretsManagement::RecoveryKey.count }

      expect(active_recovery_key.key).to eq(returned_recovery_key)
      expect(active_recovery_key.active).to be true
    end

    context 'if there already exists a RecoveryKey in the database' do
      let(:current_recovery_key) { "a" * 64 }
      let!(:old_recovery_key) { create(:sm_recovery_key, key: current_recovery_key, active: true) }

      it 'does not call the OpenBao API and does not change the stored key' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        expect { task }.not_to change { SecretsManagement::RecoveryKey.count }

        old_recovery_key.reload
        expect(old_recovery_key.active).to be true
      end

      it 'prints a message directing the user to recovery_key:show' do
        expect { task }.to output(
          /Recovery key already generated in OpenBao and stored in the GitLab database/
        ).to_stdout
      end
    end

    context 'when the response contains a null key' do
      let(:recovery_response) do
        {
          "request_id" => "e1dfe66c-e97b-9ff3-acaf-3a6b24c64250",
          "lease_id" => "",
          "renewable" => false,
          "lease_duration" => 0,
          "data" => {
            "backup" => false,
            "complete" => true,
            "n" => 1,
            "pgp_fingerprints" => nil,
            "t" => 1,
            "verification_nonce" => "",
            "verification_required" => false
          },
          "wrap_info" => nil,
          "warnings" => nil,
          "auth" => nil
        }
      end

      it "does not persist anything" do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
          expect(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.not_to change { SecretsManagement::RecoveryKey.count }
      end

      it 'prints a message explaining the key cannot be retrieved via this task' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
          allow(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.to output(/OpenBao recovery key already generated and consumed/).to_stdout
      end
    end

    context 'when the api raises an exception' do
      let(:exception_class) { SecretsManagement::SecretsManagerClient::ApiError }

      it 'logs the exception by calling track_and_raise_exception' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          expect(smc).to receive(:init_rotate_recovery).and_raise(exception_class)
        end

        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_raise(exception_class)

        expect { task }.to raise_exception(exception_class)
      end
    end
  end

  describe 'recovery_key:fetch' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:recovery_key:fetch') }

    let(:encoded_jwt) { "encoded_jwt.a.key" }
    let(:returned_recovery_key) { "ffffffffff38b1f97d18a63fb044015a9c776aa7f6c0e071c22bd25c062e586e" }
    let(:recovery_response) do
      {
        "data" => {
          "keys" => [returned_recovery_key]
        }
      }
    end

    context 'when the user declines with n' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not call the OpenBao API' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        task
      end

      it 'does not display the key' do
        expect { task }.not_to output(/#{returned_recovery_key}/).to_stdout
      end
    end

    context 'when the user presses enter without input' do
      before do
        allow($stdin).to receive(:gets).and_return("\n")
      end

      it 'does not call the OpenBao API' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        task
      end
    end

    context 'when the user confirms with y' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")

        allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
          allow(smj).to receive(:encoded).and_return(encoded_jwt)
        end

        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
        end
      end

      it 'displays the recovery key' do
        expect { task }.to output(/#{returned_recovery_key}/).to_stdout
      end

      it 'does not save the key to the database' do
        expect { task }.not_to change { SecretsManagement::RecoveryKey.count }
      end
    end

    context 'when an active recovery key is already stored in the database' do
      let!(:existing_key) { create(:sm_recovery_key, active: true) }

      it 'does not call the OpenBao API' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        task
      end

      it 'does not prompt for confirmation' do
        expect($stdin).not_to receive(:gets)

        task
      end

      it 'prints a helpful message' do
        expect { task }.to output(/already stored in the database/).to_stdout
      end
    end

    context 'when OpenBao returns no keys' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")

        allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
          allow(smj).to receive(:encoded).and_return(encoded_jwt)
        end
      end

      it 'cancels the rotation and does not display a key' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return({ "data" => {} })
          expect(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.not_to output(/#{returned_recovery_key}/).to_stdout
      end

      it 'prints a message explaining the key cannot be retrieved again' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return({ "data" => {} })
          allow(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.to output(/OpenBao recovery key already generated and consumed/).to_stdout
      end
    end

    context 'when the API raises an exception' do
      let(:exception_class) { SecretsManagement::SecretsManagerClient::ApiError }

      before do
        allow($stdin).to receive(:gets).and_return("y\n")

        allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
          allow(smj).to receive(:encoded).and_return(encoded_jwt)
        end
      end

      it 'logs the exception by calling track_and_raise_exception' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          expect(smc).to receive(:init_rotate_recovery).and_raise(exception_class)
        end

        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_raise(exception_class)

        expect { task }.to raise_exception(exception_class)
      end
    end
  end

  describe 'recovery_key:show' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:recovery_key:show') }

    context 'when no active recovery key exists in the database' do
      it 'prints a message and does not prompt' do
        expect($stdin).not_to receive(:gets)

        expect { task }.to output(/No recovery key found in database/).to_stdout
      end
    end

    context 'when an active recovery key exists in the database' do
      let(:stored_key) { "#{'abcdef1234' * 6}abcd" }
      let!(:recovery_key) { create(:sm_recovery_key, key: stored_key, active: true) }

      context 'when the user confirms with y' do
        before do
          allow($stdin).to receive(:gets).and_return("y\n")
        end

        it 'prints the recovery key' do
          expect { task }.to output(/#{stored_key}/).to_stdout
        end

        it 'does not call the OpenBao API' do
          expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

          task
        end
      end

      context 'when the user declines with n' do
        before do
          allow($stdin).to receive(:gets).and_return("n\n")
        end

        it 'does not print the key' do
          expect { task }.not_to output(/#{stored_key}/).to_stdout
        end
      end

      context 'when the user presses enter without input' do
        before do
          allow($stdin).to receive(:gets).and_return("\n")
        end

        it 'does not print the key' do
          expect { task }.not_to output(/#{stored_key}/).to_stdout
        end
      end
    end
  end

  describe 'root_token:generate' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:root_token:generate') }

    let(:client) { instance_double(SecretsManagement::SecretsManagerClient) }
    let(:recovery_key) { "ffffffffff38b1f97d18a63fb044015a9c776aa7f6c0e071c22bd25c062e586e" }
    let(:root_token) { "s.#{'Ab1' * 8}" }
    let(:otp) { "abcdefghijklmnopqrstuvwxyz" }
    let(:encoded_token) { Base64.strict_encode64(xor(root_token, otp)).delete("=") }
    let(:status_response) { { "data" => { "started" => false, "required" => 1, "progress" => 0 } } }
    let(:init_response) { { "data" => { "started" => true, "nonce" => "the-nonce", "otp" => otp } } }
    let(:update_response) { { "data" => { "complete" => true, "encoded_token" => encoded_token } } }
    let(:confirmations) { ["y\n"] }

    before do
      allow(SecretsManagement::GlobalSecretsManagerJwt).to receive(:new)
        .and_return(instance_double(SecretsManagement::GlobalSecretsManagerJwt, encoded: "encoded_jwt"))
      allow(SecretsManagement::SecretsManagerClient).to receive(:new).and_return(client)
      allow(client).to receive_messages(
        generate_root_token_status: status_response,
        init_generate_root_token: init_response,
        update_generate_root_token: update_response,
        cancel_generate_root_token: nil
      )
      allow($stdin).to receive(:gets).and_return(*confirmations)
      allow(Gitlab::TaskHelpers).to receive(:prompt_for_password).and_return(recovery_key)
    end

    def xor(value, otp)
      value.bytes.zip(otp.bytes).map { |value_byte, otp_byte| value_byte ^ otp_byte }.pack("C*")
    end

    context 'when the user confirms and OpenBao accepts the recovery key' do
      it 'prints the decoded root token' do
        expect { task }.to output(/#{Regexp.escape(root_token)}/).to_stdout
      end

      it 'does not print the recovery key' do
        expect { task }.not_to output(/#{recovery_key}/).to_stdout
      end

      it 'submits the recovery key with the nonce of the attempt' do
        expect(client).to receive(:update_generate_root_token).with(key: recovery_key, nonce: "the-nonce")

        task
      end

      it 'does not cancel the completed attempt' do
        expect(client).not_to receive(:cancel_generate_root_token)

        task
      end

      it 'signs a new JWT for each OpenBao client' do
        task

        expect(SecretsManagement::GlobalSecretsManagerJwt).to have_received(:new).twice
      end
    end

    context 'when the user declines' do
      let(:confirmations) { ["n\n"] }

      it 'aborts without calling OpenBao or asking for the recovery key', :aggregate_failures do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)

        expect { task }.to output(/Aborted/).to_stdout
      end
    end

    context 'when OpenBao has no recovery key' do
      let(:status_response) { { "data" => { "started" => false, "required" => 0, "progress" => 0 } } }

      it 'tells the user to create one and does not start an attempt', :aggregate_failures do
        expect(client).not_to receive(:init_generate_root_token)
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)

        expect { task }.to output(/OpenBao has no recovery key/).to_stdout
      end
    end

    context 'when a root token generation is already in progress' do
      let(:status_response) { { "data" => { "started" => true, "required" => 1, "progress" => 0 } } }

      context 'when the user agrees to cancel it' do
        let(:confirmations) { %W[y\n y\n] }

        it 'cancels it and generates a root token', :aggregate_failures do
          expect(client).to receive(:cancel_generate_root_token).ordered
          expect(client).to receive(:init_generate_root_token).ordered.and_return(init_response)

          expect { task }.to output(/#{Regexp.escape(root_token)}/).to_stdout
        end
      end

      context 'when the user declines to cancel it' do
        let(:confirmations) { %W[y\n n\n] }

        it 'leaves it in place and does not start an attempt', :aggregate_failures do
          expect(client).not_to receive(:cancel_generate_root_token)
          expect(client).not_to receive(:init_generate_root_token)

          expect { task }.to output(/Aborted/).to_stdout
        end
      end
    end

    context 'when an active recovery key is stored in the database' do
      let(:stored_recovery_key) { "a" * 64 }

      before do
        create(:sm_recovery_key, key: stored_recovery_key, active: true)
      end

      it 'submits the stored recovery key without asking for one', :aggregate_failures do
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)
        expect(client).to receive(:update_generate_root_token).with(key: stored_recovery_key, nonce: "the-nonce")

        expect { task }.to output(/Using the recovery key stored in the GitLab database/).to_stdout
      end

      it 'does not print the stored recovery key' do
        expect { task }.not_to output(/#{stored_recovery_key}/).to_stdout
      end
    end

    context 'when only an inactive recovery key is stored in the database' do
      before do
        create(:sm_recovery_key, key: "a" * 64, active: false)
      end

      it 'asks for the recovery key' do
        expect(client).to receive(:update_generate_root_token).with(key: recovery_key, nonce: "the-nonce")

        task

        expect(Gitlab::TaskHelpers).to have_received(:prompt_for_password)
      end
    end

    context 'when no recovery key is entered' do
      let(:recovery_key) { "" }

      it 'aborts without starting an attempt' do
        expect(client).not_to receive(:init_generate_root_token)

        expect { task }.to output(/No recovery key entered/).to_stdout
      end
    end

    context 'when OpenBao rejects the recovery key' do
      let(:error) do
        SecretsManagement::SecretsManagerClient::ServiceUnavailableError.new(
          "root generation aborted: unable to authenticate: recovery key verification failed"
        )
      end

      before do
        allow(client).to receive(:update_generate_root_token).and_raise(error)
      end

      it 'cancels the attempt and raises the error', :aggregate_failures do
        expect(client).to receive(:cancel_generate_root_token)
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(error).and_raise(error)

        expect { task }.to raise_error(error.class)
      end

      it 'does not print the recovery key' do
        allow(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_raise(error)

        expect { expect { task }.to raise_error(error.class) }.not_to output(/#{recovery_key}/).to_stdout
      end

      context 'when cancelling the attempt also fails' do
        before do
          allow(client).to receive(:cancel_generate_root_token)
            .and_raise(SecretsManagement::SecretsManagerClient::ConnectionError, "connection refused")
        end

        it 'says so and still raises the original error', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(error).and_raise(error)

          expect { expect { task }.to raise_error(error.class) }
            .to output(/Could not cancel the root token generation attempt/).to_stdout
        end
      end
    end

    context 'when OpenBao does not complete the attempt' do
      let(:update_response) { { "data" => { "complete" => false, "progress" => 0, "required" => 1 } } }

      it 'cancels the attempt and prints no root token', :aggregate_failures do
        expect(client).to receive(:cancel_generate_root_token)

        expect { task }.to output(/did not complete the root token generation/).to_stdout
      end
    end

    context 'when the encoded token is not valid base64' do
      let(:encoded_token) { "!!!!" }

      it 'raises a decode error' do
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception)
          .with(an_instance_of(SecretsManagement::RakeTask::GenerateRootToken::DecodeError))
          .and_call_original

        expect { task }.to raise_error(SecretsManagement::RakeTask::GenerateRootToken::DecodeError)
      end
    end

    context 'when the encoded token does not match the OTP length' do
      let(:encoded_token) { Base64.strict_encode64("short").delete("=") }

      it 'raises a decode error' do
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception)
          .with(an_instance_of(SecretsManagement::RakeTask::GenerateRootToken::DecodeError))
          .and_call_original

        expect { task }.to raise_error(SecretsManagement::RakeTask::GenerateRootToken::DecodeError)
      end
    end
  end

  describe 'secrets_manager_policy:update' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:secrets_manager_policy:update') }

    let(:client) { instance_double(SecretsManagement::SecretsManagerClient) }
    let(:new_policy) { File.read(SecretsManagement::RakeTask::UpdateSecretsManagerPolicy::POLICY_FILE) }
    let(:current_policy) { 'path "*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }' }
    let(:read_back_policy) { new_policy }
    let(:server_version) { "2.6.2+v2.6.2-gitlab1" }
    let(:recovery_shares_required) { 1 }
    let(:confirmations) { ["\n"] }

    before do
      create(:sm_recovery_key, active: true)
      allow($stdin).to receive(:gets).and_return(*confirmations)
      allow(SecretsManagement::GlobalSecretsManagerJwt).to receive(:new)
        .and_return(instance_double(SecretsManagement::GlobalSecretsManagerJwt, encoded: "encoded_jwt"))
      allow(SecretsManagement::SecretsManagerClient).to receive(:new).and_return(client)
      allow(client).to receive_messages(
        server_version: server_version,
        generate_root_token_status: { "data" => { "required" => recovery_shares_required } },
        write_policy_text: nil
      )
      allow(client).to receive(:read_policy_text).with('secrets_manager')
        .and_return(current_policy, read_back_policy)
    end

    context 'when DRY_RUN is not set' do
      it 'prints both policies and writes nothing', :aggregate_failures do
        expect(client).not_to receive(:write_policy_text)

        expect { task }.to output(
          /#{Regexp.escape(current_policy)}.*#{Regexp.escape(new_policy)}.*Dry run, nothing was written/m
        ).to_stdout
      end

      it 'does not warn when OpenBao has a recovery key' do
        expect { task }.not_to output(/WARNING/).to_stdout
      end
    end

    context 'when DRY_RUN is false' do
      before do
        stub_env('DRY_RUN', 'false')
      end

      it 'writes the policy from secrets_manager_policy.hcl' do
        expect(client).to receive(:write_policy_text).with('secrets_manager', new_policy)

        expect { task }.to output(/Applied the new secrets_manager policy/).to_stdout
      end

      context 'when the policy read back does not match' do
        let(:read_back_policy) { current_policy }

        it 'exits with an error' do
          expect { task }.to raise_error(SystemExit)
            .and output(/ERROR: the secrets_manager policy read back from OpenBao does not match/).to_stderr
        end
      end

      context 'when there is no current policy' do
        let(:current_policy) { nil }

        it 'writes the policy' do
          expect(client).to receive(:write_policy_text).with('secrets_manager', new_policy)

          expect { task }.to output(/Applied the new secrets_manager policy/).to_stdout
        end
      end

      it 'does not ask for a root token', :aggregate_failures do
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)

        expect { task }.not_to output(/needs a root token|revoke it now/).to_stdout
      end

      context 'when OpenBao denies the write with the privileged JWT' do
        let(:permission_denied) do
          SecretsManagement::SecretsManagerClient::ApiError.new("1 error occurred:\n\t* permission denied")
        end

        let(:root_token) { "s.root-token" }

        before do
          allow(client).to receive(:write_policy_text).with('secrets_manager', new_policy)
            .and_raise(permission_denied)
          allow(client).to receive(:write_policy_text).with('secrets_manager', new_policy, token: root_token)
          allow(Gitlab::TaskHelpers).to receive(:prompt_for_password).and_return("#{root_token}\n")
        end

        it 'writes the policy with the root token and warns to revoke it', :aggregate_failures do
          expected_output = Regexp.new(
            "needs a root token.*revoke it when this task finishes.*Applied the new secrets_manager policy.*" \
              "WARNING: Root tokens do not expire.*revoke it now with `bao token revoke -self`",
            Regexp::MULTILINE
          )

          expect { task }.to output(expected_output).to_stdout
          expect(client).to have_received(:write_policy_text).with('secrets_manager', new_policy, token: root_token)
        end

        it 'does not print the root token' do
          expect { task }.not_to output(/#{Regexp.escape(root_token)}/).to_stdout
        end

        context 'when no root token is entered' do
          let(:root_token) { "" }

          it 'exits before writing again', :aggregate_failures do
            expect { task }.to raise_error(SystemExit)
              .and output(/No root token entered. Nothing was written/).to_stderr
            expect(client).not_to have_received(:write_policy_text).with('secrets_manager', new_policy, token: anything)
          end
        end

        context 'when OpenBao denies the write with the root token' do
          before do
            allow(client).to receive(:write_policy_text).with('secrets_manager', new_policy, token: root_token)
              .and_raise(permission_denied)
          end

          it 'exits with an error' do
            expect { task }.to raise_error(SystemExit)
              .and output(/ERROR: OpenBao denied the write with this root token. Nothing was written/).to_stderr
          end
        end

        context 'when the write with the root token fails for another reason' do
          let(:error) { SecretsManagement::SecretsManagerClient::ApiError.new("invalid policy") }

          before do
            allow(client).to receive(:write_policy_text).with('secrets_manager', new_policy, token: root_token)
              .and_raise(error)
          end

          it 'raises the error' do
            expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(error).and_raise(error)

            expect { task }.to raise_error(error.class)
          end
        end
      end

      context 'when the write fails for another reason' do
        let(:error) { SecretsManagement::SecretsManagerClient::ApiError.new("invalid policy") }

        before do
          allow(client).to receive(:write_policy_text).and_raise(error)
        end

        it 'raises the error' do
          expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(error).and_raise(error)

          expect { task }.to raise_error(error.class)
        end
      end
    end

    context 'when the policy is already applied with different formatting' do
      let(:current_policy) { "#{new_policy.gsub(/#.*$/, '').squeeze("\n")}\n\n" }

      before do
        stub_env('DRY_RUN', 'false')
      end

      it 'writes nothing' do
        expect(client).not_to receive(:write_policy_text)

        expect { task }.to output(/already up to date/).to_stdout
      end
    end

    context 'when OpenBao has no recovery key' do
      let(:recovery_shares_required) { 0 }

      it 'warns that a real run refuses', :aggregate_failures do
        expect(client).not_to receive(:write_policy_text)

        expect { task }.to output(/WARNING: OpenBao has no recovery key.*refuses until a recovery key exists/m)
          .to_stdout
      end

      context 'when DRY_RUN is false' do
        before do
          stub_env('DRY_RUN', 'false')
        end

        it 'always exits with an error before writing', :aggregate_failures do
          expect(client).not_to receive(:write_policy_text)

          expect { task }.to raise_error(SystemExit)
            .and output(/ERROR: OpenBao has no recovery key/).to_stderr
        end
      end
    end

    context 'when the GitLab database has no recovery key' do
      before do
        SecretsManagement::RecoveryKey.delete_all
      end

      it 'notes that a real run asks for confirmation', :aggregate_failures do
        expect($stdin).not_to receive(:gets)

        expect { task }.to output(/NOTE: The GitLab database has no recovery key.*asks you to confirm/m).to_stdout
      end

      context 'when DRY_RUN is false' do
        before do
          stub_env('DRY_RUN', 'false')
        end

        context 'when the user confirms they have the recovery key' do
          let(:confirmations) { ["y\n"] }

          it 'writes the policy' do
            expect(client).to receive(:write_policy_text).with('secrets_manager', new_policy)

            expect { task }.to output(/Applied the new/).to_stdout
          end
        end

        context 'when the user does not confirm' do
          let(:confirmations) { ["n\n"] }

          it 'exits before writing', :aggregate_failures do
            expect(client).not_to receive(:write_policy_text)

            expect { task }.to raise_error(SystemExit).and output(/Aborted. Nothing was written/).to_stderr
          end
        end
      end
    end

    context 'when OpenBao is exactly 2.6.0' do
      let(:server_version) { "2.6.0" }

      it 'proceeds' do
        expect { task }.to output(/Dry run, nothing was written/).to_stdout
      end
    end

    context 'when OpenBao is older than 2.6.0' do
      let(:server_version) { "2.5.5+v2.5.5-gitlab2" }

      it 'exits with an error before reading the policy', :aggregate_failures do
        expect(client).not_to receive(:read_policy_text)

        expect { task }.to raise_error(SystemExit)
          .and output(/OpenBao 2.5.5\+v2.5.5-gitlab2 is not supported/).to_stderr
      end
    end

    context 'when the OpenBao version cannot be parsed' do
      let(:server_version) { nil }

      it 'exits with an error before reading the policy', :aggregate_failures do
        expect(client).not_to receive(:read_policy_text)

        expect { task }.to raise_error(SystemExit).and output(/OpenBao version unknown is not supported/).to_stderr
      end
    end
  end
end
