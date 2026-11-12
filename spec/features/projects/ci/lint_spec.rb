# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CI Lint', :js, feature_category: :pipeline_composition do
  include Features::SourceEditorSpecHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:content_selector) { '.content .view-lines' }
  let(:correct_yaml) { File.read(Rails.root.join('spec/support/gitlab_stubs/gitlab_ci.yml')) }
  let(:incorrect_yaml) do
    <<~YAML.strip
      invalid: yaml content
      that: has
      multiple: lines
      value: cannot have :
      more: content
    YAML
  end

  before do
    sign_in(user)

    visit project_ci_lint_path(project)
  end

  def validate(yaml_content)
    editor_set_value(yaml_content)
    click_on 'Validate'
    scroll_to(find_by_testid('ci-lint-status'))
  end

  shared_examples 'validates and clears the YAML' do
    it 'shows the jobs of correct YAML, the error of incorrect YAML, and clears the YAML', :aggregate_failures do
      validate(correct_yaml)

      expect(page).to have_content('Status: Syntax is correct')

      within "table" do
        expect(page).to have_content('Job - rspec')
        expect(page).to have_content('Job - spinach')
        expect(page).to have_content('Deploy Job - staging')
        expect(page).to have_content('Deploy Job - production')
      end

      validate(incorrect_yaml)

      expect(page).to have_content('Status: Syntax is incorrect')
      expect(page).to have_selector(content_selector)
      expect(find(content_selector).text.strip).to eq(incorrect_yaml.strip)

      click_on 'Clear'

      expect(page).to have_field(class: 'inputarea', with: '', visible: :visible, type: 'textarea')
    end
  end

  it_behaves_like 'validates and clears the YAML'

  context 'when Dry Run is checked' do
    before do
      check 'Simulate a pipeline created for the default branch'
    end

    it_behaves_like 'validates and clears the YAML'
  end
end
