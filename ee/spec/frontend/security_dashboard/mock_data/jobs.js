export const mockPipelineJobs = [
  {
    name: 'my_fuzz_target',
    artifacts: {
      nodes: [
        {
          downloadPath: '/debug-cov-fuzz-project/-/jobs/1133/artifacts/download?file_type=trace',
          fileType: 'TRACE',
          id: 'gid://gitlab/Ci::JobArtifact/9005',
          __typename: 'CiJobArtifact',
        },
        {
          downloadPath:
            'debug-cov-fuzz-project/-/jobs/1133/artifacts/download?file_type=coverage_fuzzing',
          fileType: 'COVERAGE_FUZZING',
          id: 'gid://gitlab/Ci::JobArtifact/9004',
          __typename: 'CiJobArtifact',
        },
        {
          downloadPath: '/debug-cov-fuzz-project/-/jobs/1133/artifacts/download?file_type=metadata',
          fileType: 'METADATA',
          id: 'gid://gitlab/Ci::JobArtifact/9003',
          __typename: 'CiJobArtifact',
        },
        {
          downloadPath: '/debug-cov-fuzz-project/-/jobs/1133/artifacts/download?file_type=archive',
          fileType: 'ARCHIVE',
          id: 'gid://gitlab/Ci::JobArtifact/9002',
          __typename: 'CiJobArtifact',
        },
      ],
      __typename: 'CiJobArtifactConnection',
    },
    __typename: 'CiJob',
  },
  {
    name: 'gosec-sast',
    artifacts: {
      nodes: [
        {
          downloadPath: '/debug-cov-fuzz-project/-/jobs/1131/artifacts/download?file_type=trace',
          fileType: 'TRACE',
          id: 'gid://gitlab/Ci::JobArtifact/9001',
          __typename: 'CiJobArtifact',
        },
        {
          downloadPath: '/debug-cov-fuzz-project/-/jobs/1131/artifacts/download?file_type=sast',
          fileType: 'SAST',
          id: 'gid://gitlab/Ci::JobArtifact/9000',
          __typename: 'CiJobArtifact',
        },
      ],
      __typename: 'CiJobArtifactConnection',
    },
    __typename: 'CiJob',
  },
];
