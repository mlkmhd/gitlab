# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::JsRoutes, feature_category: :tooling do
  describe '.generate!' do
    let_it_be(:expected_base_path) do
      Rails.root.join('ee/app/assets/javascripts/lib/utils/path_helpers')
    end

    describe 'outputted files' do
      before_all do
        described_class.generate!
      end

      describe 'path helpers are split into multiple files by namespace' do
        # Project routes are not cloned under /o/, so the shorthand keeps its
        # projectFullPath signature but never resolves an organization scope.
        it 'generates project path helpers without organization scoping' do
          file_path = File.join(expected_base_path, 'project.js')
          expect(File).to exist(file_path)

          file_contents = File.read(file_path)
          expect(file_contents).to include("import { __jsr } from '~/lib/utils/path_helpers/core';")
          expect(file_contents).to include(
            "import { splitProjectFullPath } from '~/lib/utils/path_helpers/utils';"
          )
          expect(file_contents).not_to include('resolveOrganizationScope')
          expect(file_contents).not_to include('_organizationNamespaceProject')
          expect(file_contents).to include(
            "export const importCsvProjectRequirementsManagementRequirementsPath = /*#__PURE__*/ " \
              "(projectFullPath, ...args) => {"
          )
          expect(file_contents).to include(
            "const _importCsvNamespaceProjectRequirementsManagementRequirementsPath = /*#__PURE__*/ __jsr.r("
          )
          expect(file_contents).to include(
            <<-JS
  const { namespacePath, projectPath } = splitProjectFullPath(projectFullPath);

  return _importCsvNamespaceProjectRequirementsManagementRequirementsPath(namespacePath, projectPath, ...args);
            JS
          )
        end

        it 'generates group path helpers as unscoped' do
          file_path = File.join(expected_base_path, 'group.js')
          expect(File).to exist(file_path)

          file_contents = File.read(file_path)
          expect(file_contents).to include("import { __jsr } from '~/lib/utils/path_helpers/core';")
          expect(file_contents).not_to include('resolveOrganizationScope')
          expect(file_contents).to include("export const groupSettingsReportingPath = /*#__PURE__*/ __jsr.r(")
        end

        it 'generates organization scoped path helpers for pages that stay cloned' do
          file_path = File.join(expected_base_path, 'dashboard.js')
          expect(File).to exist(file_path)

          file_contents = File.read(file_path)
          expect(file_contents).to include(
            "import { resolveOrganizationScope } from '~/lib/utils/path_helpers/utils';"
          )
          expect(file_contents).to include(
            "export const removedDashboardProjectsPath = /*#__PURE__*/ (...args) => {"
          )
          expect(file_contents).to include(
            "const _removedOrganizationDashboardProjectsPath = /*#__PURE__*/ __jsr.r("
          )
          expect(file_contents).to include(
            "const _removedDashboardProjectsPath = /*#__PURE__*/ __jsr.r("
          )
          expect(file_contents).to include(
            <<-JS
  const { organizationPath, routeArgs } = resolveOrganizationScope(args);

  if (organizationPath) {
    return _removedOrganizationDashboardProjectsPath(organizationPath, ...routeArgs);
  }

  return _removedDashboardProjectsPath(...routeArgs);
            JS
          )
        end
      end
    end
  end
end
