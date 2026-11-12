// One entry per generated REST list fixture beyond the base. The suffix is both the file name
// and, upper-cased, the variant key.
const FILTER_SUFFIXES = [
  'with_label',
  'without_specific_label',
  'with_no_label',
  'with_any_label',
  'with_any_of_labels',

  'with_my_reaction',
  'without_my_reaction',
  'with_no_reaction',
  'with_any_reaction',

  'confidential',
  'not_confidential',

  'matching_title',
  'matching_description',

  'with_assignee',
  'without_specific_assignee',
  'with_no_assignee',
  'with_any_assignee',
  'with_any_of_assignees',

  'with_author',
  'without_author',
  'with_any_of_authors',

  'with_milestone',
  'without_specific_milestone',
  'with_no_milestone',
  'with_any_milestone',
  'with_upcoming_milestone',
  'with_started_milestone',

  'with_release',
  'without_specific_release',
  'with_no_release',
  'with_any_release',
  'group',
  'group_epics',
  'with_crm_organization',
  'with_second_crm_organization',
  'with_crm_contact',
  'with_second_crm_contact',
  'group_with_crm_organization',
  'group_with_crm_contact',
];

/**
 * Builds the REST list variants from the captures the fixture generator records for each suffix.
 *
 * `require` rather than static imports keeps one suffix list instead of an import per fixture.
 * Jest's moduleNameMapper resolves the `test_fixtures` alias from a template literal.
 */
export function listFilterVariants() {
  return Object.fromEntries(
    FILTER_SUFFIXES.map((suffix) => [
      suffix.toUpperCase(),
      // eslint-disable-next-line global-require
      require(`test_fixtures/graphql/work_items/integration/rest_work_items_list_${suffix}.json`),
    ]),
  );
}
