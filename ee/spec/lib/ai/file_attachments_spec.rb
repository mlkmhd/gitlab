# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FileAttachments, feature_category: :duo_agent_platform do
  describe '.allowed?' do
    let_it_be(:user) { create(:user) }
    let_it_be(:other_user) { create(:user) }
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }

    def stub_instance_setting(value)
      allow(::Ai::Setting).to receive(:for_current_or_default_organization)
        .and_return(instance_double(::Ai::Setting, duo_workflow_file_attachments_enabled: value))
    end

    before do
      stub_feature_flags(dap_web_chat_file_attachments: user)
    end

    context 'on GitLab.com', :saas do
      it 'is true when the flag is enabled for the user, whatever the settings', :aggregate_failures do
        stub_instance_setting(false)

        expect(described_class.allowed?(subgroup, user: user)).to be(true)
        expect(described_class.allowed?(nil, user: user)).to be(true)
      end

      it 'is false when the flag is not enabled for the user' do
        expect(described_class.allowed?(subgroup, user: other_user)).to be(false)
      end
    end

    context 'on self-managed and Dedicated' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'is false without a saved instance setting or default organization' do
        expect(described_class.allowed?(subgroup, user: user)).to be(false)
      end

      context 'with a saved instance setting' do
        where(:instance_setting) { [true, false] }

        with_them do
          before do
            stub_instance_setting(instance_setting)
          end

          it 'follows the instance setting, with or without a namespace', :aggregate_failures do
            expect(described_class.allowed?(subgroup, user: user)).to be(instance_setting)
            expect(described_class.allowed?(nil, user: user)).to be(instance_setting)
          end

          it 'is false when the flag is not enabled for the user' do
            expect(described_class.allowed?(subgroup, user: other_user)).to be(false)
          end
        end
      end
    end

    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dap_web_chat_file_attachments: false)
        stub_instance_setting(true)
      end

      it 'is false without checking the setting', :aggregate_failures do
        expect(described_class.allowed?(subgroup, user: user)).to be(false)
        expect(::Ai::Setting).not_to have_received(:for_current_or_default_organization)
      end
    end
  end
end
