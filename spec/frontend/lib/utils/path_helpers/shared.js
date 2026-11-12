const withOrganizationPathOption = (args, organizationPath) => {
  const options = args.at(-1);

  return typeof options === 'object' && options !== null
    ? [...args.slice(0, -1), { ...options, organizationPath }]
    : [...args, { organizationPath }];
};

const setup = async () => {
  await import('~/behaviors/configure_path_helpers');
};

const basePathHelperTests = ({ pathHelpersFilePath, testCases }) => {
  describe('with no special configuration', () => {
    beforeEach(async () => {
      await setup();
    });

    it.each(testCases)(
      '$pathHelperName returns $baseExpected',
      async ({ pathHelperName, args, baseExpected }) => {
        const pathHelpers = await import(pathHelpersFilePath);

        expect(pathHelpers[pathHelperName](...args)).toBe(baseExpected);
      },
    );
  });

  describe('when relative_url_root is set', () => {
    beforeEach(async () => {
      window.gon = {
        relative_url_root: '/gitlab',
      };
      await setup();
    });

    it.each(testCases)(
      '$pathHelperName returns /gitlab$baseExpected',
      async ({ pathHelperName, args, baseExpected }) => {
        const pathHelpers = await import(pathHelpersFilePath);

        expect(pathHelpers[pathHelperName](...args)).toBe(`/gitlab${baseExpected}`);
      },
    );
  });
};

// Groups, projects and users are not cloned under /o/:organization_path: a
// record in a non-default organization carries `o/<org>/` in its own path.
const unscopedPathHelperTests = ({ pathHelpersFilePath, testCases }) => {
  describe('when the current page URL and the data context are organization scoped', () => {
    beforeEach(async () => {
      window.gon = {
        organization_path: 'acme',
        data_context_organization_path: 'acme',
      };
      await setup();
    });

    it.each(testCases)(
      '$pathHelperName is not affected by organization scoping',
      async ({ pathHelperName, args, baseExpected }) => {
        const pathHelpers = await import(pathHelpersFilePath);

        expect(pathHelpers[pathHelperName](...args)).toBe(baseExpected);
      },
    );
  });
};

const scopedPathHelperTests = ({ pathHelpersFilePath, testCases }) => {
  describe('when the current page URL is organization scoped', () => {
    beforeEach(async () => {
      window.gon = {
        organization_path: 'acme',
      };
      await setup();
    });

    it.each(testCases)(
      '$pathHelperName returns /o/acme$baseExpected',
      async ({ pathHelperName, args, baseExpected }) => {
        const pathHelpers = await import(pathHelpersFilePath);

        expect(pathHelpers[pathHelperName](...args)).toBe(`/o/acme${baseExpected}`);
      },
    );

    describe('when organizationPath is passed', () => {
      it.each(testCases)(
        '$pathHelperName returns /o/foo$baseExpected',
        async ({ pathHelperName, args, baseExpected }) => {
          const pathHelpers = await import(pathHelpersFilePath);

          expect(pathHelpers[pathHelperName](...withOrganizationPathOption(args, 'foo'))).toBe(
            `/o/foo${baseExpected}`,
          );
        },
      );
    });

    describe('when organizationPath is passed as null', () => {
      it.each(testCases)(
        '$pathHelperName returns $baseExpected',
        async ({ pathHelperName, args, baseExpected }) => {
          const pathHelpers = await import(pathHelpersFilePath);

          expect(pathHelpers[pathHelperName](...withOrganizationPathOption(args, null))).toBe(
            baseExpected,
          );
        },
      );
    });
  });

  describe('when relative_url_root is set and the current page URL is organization scoped', () => {
    beforeEach(async () => {
      window.gon = {
        relative_url_root: '/gitlab',
        organization_path: 'acme',
      };
      await setup();
    });

    it.each(testCases)(
      '$pathHelperName returns /gitlab/o/acme$baseExpected',
      async ({ pathHelperName, args, baseExpected }) => {
        const pathHelpers = await import(pathHelpersFilePath);

        expect(pathHelpers[pathHelperName](...args)).toBe(`/gitlab/o/acme${baseExpected}`);
      },
    );
  });

  describe('when the data context organization path is set', () => {
    beforeEach(async () => {
      window.gon = {
        data_context_organization_path: 'acme',
      };
      await setup();
    });

    it.each(testCases)(
      '$pathHelperName returns /o/acme$baseExpected',
      async ({ pathHelperName, args, baseExpected }) => {
        const pathHelpers = await import(pathHelpersFilePath);

        expect(pathHelpers[pathHelperName](...args)).toBe(`/o/acme${baseExpected}`);
      },
    );

    describe('and organizationPath is passed', () => {
      it.each(testCases)(
        'ignores organizationPath argument, $pathHelperName returns /o/acme$baseExpected',
        async ({ pathHelperName, args, baseExpected }) => {
          const pathHelpers = await import(pathHelpersFilePath);

          expect(pathHelpers[pathHelperName](...withOrganizationPathOption(args, 'foo'))).toBe(
            `/o/acme${baseExpected}`,
          );
        },
      );
    });

    describe('and organizationPath is passed as null', () => {
      it.each(testCases)(
        'ignores organizationPath argument, $pathHelperName returns /o/acme$baseExpected',
        async ({ pathHelperName, args, baseExpected }) => {
          const pathHelpers = await import(pathHelpersFilePath);

          expect(pathHelpers[pathHelperName](...withOrganizationPathOption(args, null))).toBe(
            `/o/acme${baseExpected}`,
          );
        },
      );
    });

    describe('and the current page URL is scoped to a different organization', () => {
      beforeEach(async () => {
        window.gon = {
          data_context_organization_path: 'acme',
          organization_path: 'foo',
        };
        await setup();
      });

      it.each(testCases)(
        'uses data context, $pathHelperName returns /o/acme$baseExpected',
        async ({ pathHelperName, args, baseExpected }) => {
          const pathHelpers = await import(pathHelpersFilePath);

          expect(pathHelpers[pathHelperName](...args)).toBe(`/o/acme${baseExpected}`);
        },
      );
    });
  });
};

// eslint-disable-next-line jest/no-export
export const sharedPathHelperTests = ({
  pathHelpersFilePath,
  testCases,
  organizationScoped = true,
}) => {
  describe(pathHelpersFilePath, () => {
    beforeEach(() => {
      jest.resetModules();
    });

    afterEach(() => {
      window.gon = {};
    });

    basePathHelperTests({ pathHelpersFilePath, testCases });

    if (organizationScoped) {
      scopedPathHelperTests({ pathHelpersFilePath, testCases });
    } else {
      unscopedPathHelperTests({ pathHelpersFilePath, testCases });
    }
  });
};
