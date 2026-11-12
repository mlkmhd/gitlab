# frozen_string_literal: true

require 'fast_spec_helper'
require 'global_id'

RSpec.describe ComplianceManagement::Frameworks::TemplateRegistry, feature_category: :compliance_management do
  after do
    described_class.reset!
  end

  describe '.all' do
    it 'returns all templates' do
      templates = described_class.all

      expect(templates).to be_an(Array)
      expect(templates.size).to be >= 2
    end

    it 'returns templates with expected attributes' do
      template = described_class.all.find { |t| t.id == 'soc2' }

      expect(template).to be_present
      expect(template.id).to eq('soc2')
      expect(template.template_version).to eq(1)
      expect(template.name).to eq('SOC 2')
      expect(template.description).to be_present
      expect(template.color).to be_present
      expect(template.requirements).to be_an(Array)
      expect(template.requirements).not_to be_empty
      expect(template.json).to be_a(String)
      expect(::Gitlab::Json.safe_parse(template.json)).to be_a(Hash)
    end

    it 'derives id from filename' do
      template_ids = described_class.all.map(&:id)

      expect(template_ids).to include('soc2', 'tisax', 'eu_ai_act')
    end

    it 'caches the result' do
      expect(described_class.all).to equal(described_class.all)
    end
  end

  describe 'eu_ai_act template' do
    let(:template) { described_class.find('eu_ai_act') }

    it 'is available as an out-of-the-box template' do
      expect(template).to be_present
      expect(template.name).to eq('EU AI Act')
      expect(template.template_version).to eq(1)
    end

    it 'maps each implemented AI control to an article' do
      controls_by_requirement = template.requirements.to_h do |requirement|
        [requirement['name'], requirement['controls'].map { |control| control['name'] }]
      end

      expect(controls_by_requirement).to eq(
        'Article 10 Data and data governance' => %w[model_experiments_access_level_configured],
        'Article 12 Record-keeping' => %w[duo_agentic_flow_audit_events_streaming],
        'Article 14 Human oversight' => %w[duo_agentic_flow_governance_oversight_configured],
        'Article 15 Accuracy, robustness and cybersecurity' => %w[model_registry_access_level_configured]
      )
    end

    it 'only references controls defined in compliance_controls.yml' do
      defined_controls = YAML.safe_load_file(
        Rails.root.join('ee/config/compliance_management/compliance_controls.yml')
      ).fetch('controls').keys

      referenced = template.requirements.flat_map do |requirement|
        requirement['controls'].map { |control| control['expression']['field'] }
      end

      expect(defined_controls).to include(*referenced)
    end
  end

  describe '.find' do
    it 'returns the template matching the given id' do
      template = described_class.find('soc2')

      expect(template).to be_present
      expect(template.id).to eq('soc2')
    end

    it 'returns nil when no template matches' do
      expect(described_class.find('nonexistent')).to be_nil
    end
  end

  describe '.reset!' do
    it 'clears the cached templates' do
      first_call = described_class.all
      described_class.reset!
      second_call = described_class.all

      expect(first_call).not_to equal(second_call)
    end
  end
end
