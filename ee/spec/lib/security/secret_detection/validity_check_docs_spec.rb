# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::ValidityCheckDocs, feature_category: :secret_detection do
  let(:header) do
    '| Description | ID | Pipeline | Client-side | Push protection | Validity check | Validity check analyzer |'
  end

  let(:separator) { '|:--|:--|:--|:--|:--|:--|:--|' }

  let(:content) do
    <<~MARKDOWN
      ## Supported rules for rule-based detection

      #{header}
      #{separator}
      | Known both | KnownBothRule | {{< yes >}} | {{< no >}} | {{< yes >}} | stale | stale |
      | Known GSS | KnownGssRule | {{< yes >}} | {{< no >}} | {{< no >}} | stale | stale |
      | Unknown | UnknownRule | {{< yes >}} | {{< no >}} | {{< no >}} | stale | stale |

      ## A later section

      #{header}
      #{separator}
      | Known both | KnownBothRule | x | x | x | untouched | untouched |
    MARKDOWN
  end

  describe '.generate' do
    subject(:generate) { described_class.generate(content) }

    before do
      allow(described_class).to receive(:validity_by_rule_id).and_return(
        'KnownBothRule' => described_class::BOTH,
        'KnownGssRule' => described_class::GSS,
        'NewRule' => described_class::BOTH
      )
    end

    let(:new_content) { generate.first }
    let(:unlisted) { generate.last }

    it 'sets the last two columns for a rule that supports validity checks' do
      expect(new_content).to include(
        '| Known both | KnownBothRule | {{< yes >}} | {{< no >}} | {{< yes >}} | {{< yes >}} | Both |'
      )
      expect(new_content).to include(
        '| Known GSS | KnownGssRule | {{< yes >}} | {{< no >}} | {{< no >}} | ' \
          '{{< yes >}} | GitLab Secret Scanning for Source Code |'
      )
    end

    it 'sets No and None for a row whose rule has no validity check' do
      expect(new_content).to include(
        '| Unknown | UnknownRule | {{< yes >}} | {{< no >}} | {{< no >}} | {{< no >}} | None |'
      )
    end

    it 'leaves the header, separator and the first five columns unchanged' do
      expect(new_content).to include(header, separator)
      expect(new_content.scan('| {{< yes >}} | {{< no >}} |').size).to eq(3)
    end

    it 'does not touch a table under a later heading' do
      expect(new_content).to include('| Known both | KnownBothRule | x | x | x | untouched | untouched |')
    end

    it 'returns rules that have no table row' do
      expect(unlisted).to contain_exactly('NewRule')
    end

    it 'does not add a row for a rule that has none' do
      expect(new_content).not_to include('NewRule')
    end

    it 'is idempotent' do
      expect(described_class.generate(new_content).first).to eq(new_content)
    end

    context 'when the columns are reordered' do
      let(:header) do
        '| Description | ID | Validity check | Pipeline | Client-side | Push protection | Validity check analyzer |'
      end

      it 'raises instead of rewriting the wrong cells' do
        expect { generate }.to raise_error(ArgumentError, /columns moved/)
      end
    end
  end

  describe '.validity_by_rule_id' do
    subject(:rules) { described_class.send(:validity_by_rule_id) }

    let(:token_config) { {} }
    let(:partners) { {} }

    before do
      stub_const('Security::SecretDetection::TokenLookupService::TOKEN_TYPE_CONFIG', token_config)
      stub_const('Security::SecretDetection::PartnerTokens::Registry::PARTNERS', partners)
    end

    context 'when a rule is in both sources' do
      let(:token_config) { { 'shared' => { enabled_targets: [Security::SecretDetection::Scanners::GITLEAKS] } } }
      let(:partners) do
        { 'shared' => { enabled: true, enabled_targets: [Security::SecretDetection::Scanners::GSS] } }
      end

      it 'unions the scanners' do
        expect(rules).to eq('shared' => described_class::BOTH)
      end
    end

    context 'when sources have different scanners' do
      let(:token_config) { { 'lookup' => { enabled_targets: Security::SecretDetection::Scanners::ALL } } }
      let(:partners) do
        {
          'partner' => { enabled: true, enabled_targets: [Security::SecretDetection::Scanners::GSS] },
          'disabled' => { enabled: false, enabled_targets: Security::SecretDetection::Scanners::ALL }
        }
      end

      it 'labels each rule and omits rules without targets' do
        expect(rules).to eq('lookup' => described_class::BOTH, 'partner' => described_class::GSS)
      end
    end

    context 'when the scanners have no docs label' do
      let(:token_config) { { 'gitleaks_only' => { enabled_targets: [Security::SecretDetection::Scanners::GITLEAKS] } } }

      it 'raises' do
        expect { rules }.to raise_error(ArgumentError, /No docs label for scanners of gitleaks_only/)
      end
    end
  end
end
