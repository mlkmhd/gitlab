# frozen_string_literal: true

# Expects `ci_cd_settings`, the restored record. Covers every exported attribute, so a new setting only needs
# a value in the fixture, preferably not the default.
RSpec.shared_examples 'restores all exported CI/CD settings' do
  let(:fixture_settings) do
    Gitlab::Json::SafeParser.parse(
      File.read('spec/fixtures/lib/gitlab/import_export/complex/tree/project/ci_cd_settings.ndjson')
    )
  end

  let(:exported_attributes) do
    Gitlab::ImportExport::Config.new.to_h.dig(:included_attributes, :ci_cd_settings).map(&:to_s)
  end

  it 'restores every exported CI/CD setting', :aggregate_failures do
    expect(fixture_settings.keys).to include(*exported_attributes)

    # Casting through the model compares enums the same way in CE and EE.
    expected = ProjectCiCdSetting.new(fixture_settings.slice(*exported_attributes)).attributes
    expect(ci_cd_settings.attributes.slice(*exported_attributes)).to eq(expected.slice(*exported_attributes))
  end
end
