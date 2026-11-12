# frozen_string_literal: true

module DependencyFilterSbomHelpers
  # Every transitive component depends on the first direct one. Without a graph, the types stay unknown.
  def create_sbom_build(pipeline, direct: [], transitive: [], input_file: 'requirements.txt', graph: true)
    build = create(:ci_build, :success, pipeline: pipeline, project: pipeline.project)
    create(:ee_ci_job_artifact, file_type: :cyclonedx, file_format: :gzip, job: build, project: pipeline.project,
      file: sbom_upload(direct, transitive, input_file, graph))
    build
  end

  private

  def sbom_upload(direct, transitive, input_file, graph)
    file = Tempfile.new(%w[sbom .cdx.json.gz])
    document = sbom_document(direct, transitive, input_file, graph)
    Zlib::GzipWriter.open(file.path) { |gz| gz.write(Gitlab::Json.dump(document)) }

    Rack::Test::UploadedFile.new(file.path, 'application/x-gzip')
  end

  def sbom_document(direct, transitive, input_file, graph)
    components = (direct + transitive).map { |name, version| sbom_component_data(name, version) }

    {
      bomFormat: 'CycloneDX', specVersion: '1.4', version: 1,
      metadata: {
        component: { name: 'root', type: 'application', 'bom-ref': 'root' },
        properties: [
          { name: 'gitlab:meta:schema_version', value: '1' },
          ({ name: 'gitlab:dependency_scanning:input_file:path', value: input_file } if input_file),
          { name: 'gitlab:dependency_scanning:package_manager:name', value: 'pip' },
          { name: 'gitlab:dependency_scanning:language:name', value: 'Python' }
        ].compact
      },
      components: components,
      dependencies: graph ? sbom_dependencies(direct, transitive) : []
    }
  end

  def sbom_dependencies(direct, transitive)
    refs = ->(components) { components.map { |name, version| sbom_ref(name, version) } }

    [
      { ref: 'root', dependsOn: refs.call(direct) },
      ({ ref: sbom_ref(*direct.first), dependsOn: refs.call(transitive) } if direct.any?)
    ].compact
  end

  def sbom_component_data(name, version)
    { name: name, version: version, type: 'library', purl: "pkg:pypi/#{name}@#{version}",
      'bom-ref': sbom_ref(name, version) }
  end

  def sbom_ref(name, version)
    "pkg:pypi/#{name}@#{version}"
  end
end
