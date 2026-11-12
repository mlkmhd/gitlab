import { chunk, debounce } from 'lodash-es';
import { n__, __ } from '~/locale';
import { searchInItemsProperties } from '~/lib/utils/search_utils';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';

export const PROJECT_DROPDOWN_I18N = {
  projectDropdownHeader: __('Select projects'),
};

/**
 * Number of ids to hydrate per request. 100 satisfies both limits a hydration request can hit:
 * the `ids` argument cap in `SecurityPolicyEligibleProjectsResolver::MAX_FILTER_IDS`, and the
 * page size a batch has to fit into, bounded by the schema-wide `default_max_page_size`.
 */
export const MAX_HYDRATION_IDS = 100;

/**
 * Creates a debounced search function for project dropdowns.
 * @param {Function} setSearchTermFn - The function to call with the search term
 * @returns {Function} Debounced search function
 */
export const createDebouncedSearch = (setSearchTermFn) =>
  debounce(setSearchTermFn, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);

/**
 * Normalizes a search term by trimming whitespace.
 * @param {string} searchTerm - The search term to normalize
 * @returns {string} Normalized search term
 */
export const normalizeSearchTerm = (searchTerm = '') => searchTerm.trim();

/**
 * Transforms projects array into listbox items format.
 * @param {Array} projects - Array of project objects with id, name, fullPath
 * @param {string} searchTerm - Optional search term to filter results
 * @returns {Array} Array of listbox items with text, value, fullPath
 */
export const projectsToListboxItems = (projects, searchTerm = '') => {
  const items = projects.map(({ id, fullPath, name }) => ({
    text: name,
    value: id,
    fullPath,
  }));

  return searchInItemsProperties({
    items,
    properties: ['text', 'fullPath'],
    searchQuery: searchTerm,
  });
};

/**
 * Returns the category prop value for dropdown based on validation state.
 * @param {boolean} state - Validation state (true = valid, false = invalid)
 * @returns {string} Category value ('primary' or 'secondary')
 */
export const getDropdownCategory = (state) => (state ? 'primary' : 'secondary');

/**
 * Returns the variant prop value for dropdown based on validation state.
 * @param {boolean} state - Validation state (true = valid, false = invalid)
 * @returns {string} Variant value ('default' or 'danger')
 */
export const getDropdownVariant = (state) => (state ? 'default' : 'danger');

/**
 * Gets the projects text (pluralized) for footer display.
 * @param {number} count - Number of projects
 * @returns {string} Pluralized text ('project' or 'projects')
 */
export const getProjectsText = (count) => n__('project', 'projects', count);

/**
 * Filters selected IDs to only include those that exist in the projects list.
 * @param {Array} selectedIds - Array of selected project IDs
 * @param {Array} projectIds - Array of available project IDs
 * @returns {Array} Filtered array of selected IDs that exist in projects
 */
export const filterExistingSelectedIds = (selectedIds, projectIds) =>
  selectedIds.filter((id) => projectIds.includes(id));

/**
 * Builds the payload for a multi-select dropdown, keeping selections the listbox never offered.
 * Without them a policy scope silently loses projects the dropdown could not show.
 * A retained id that is loaded but hidden by a group filter keeps its full project.
 * @param {Array} selectedItems - Selected projects the listbox offered
 * @param {Array} retainedIds - Selected ids absent from the listbox
 * @param {Array} loadedProjects - Every loaded project, filtered or not
 * @returns {Array} Selected projects followed by an entry per retained id
 */
export const withUnresolvedSelections = (selectedItems, retainedIds, loadedProjects = []) => {
  const loadedById = new Map(loadedProjects.map((project) => [project.id, project]));

  return [...selectedItems, ...retainedIds.map((id) => loadedById.get(id) || { id })];
};

/**
 * Fetches projects by id in batches of MAX_HYDRATION_IDS.
 * A failed batch does not discard the projects the other batches returned.
 * @param {Array} ids - Project ids to fetch
 * @param {Function} fetchBatch - Receives one batch of ids and resolves to its projects
 * @returns {Promise<{projects: Array, failed: boolean}>} Fetched projects and whether any batch failed
 */
export const hydrateInBatches = async (ids, fetchBatch) => {
  const responses = await Promise.allSettled(
    chunk(ids, MAX_HYDRATION_IDS).map((batch) => fetchBatch(batch)),
  );

  return {
    projects: responses
      .filter(({ status }) => status === 'fulfilled')
      .flatMap(({ value }) => value),
    failed: responses.some(({ status }) => status === 'rejected'),
  };
};

/**
 * Shared props definition for project dropdown components.
 */
export const SHARED_DROPDOWN_PROPS = {
  disabled: {
    type: Boolean,
    required: false,
    default: false,
  },
  placement: {
    type: String,
    required: false,
    default: 'bottom-start',
  },
  selected: {
    type: [Array, String],
    required: false,
    default: () => [],
  },
  state: {
    type: Boolean,
    required: false,
    default: false,
  },
  withProjectCount: {
    type: Boolean,
    required: false,
    default: false,
  },
};
