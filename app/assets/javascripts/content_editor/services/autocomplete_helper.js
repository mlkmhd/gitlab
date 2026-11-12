import { debounce, identity, isEqual, memoize, isEmpty, sortBy } from 'lodash-es';
import fuzzaldrinPlus from 'fuzzaldrin-plus';
import { initEmojiMap, getAllEmoji, getEmojiInfo, searchEmoji } from '~/emoji';
import { withPreferredTone } from '~/emoji/skin_tone';
import { newDate } from '~/lib/utils/datetime_utility';
import axios from '~/lib/utils/axios_utils';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import {
  currentAssignees,
  appliedLabels,
  linkedItems,
  availableStatuses,
  supportedConversionTypes,
} from '~/graphql_shared/issuable_client_state';
import { REFERENCE_TYPES } from '~/content_editor/constants/reference_types';
import { getDuoCodeReviewDepths } from 'ee_else_ce/content_editor/services/duo_code_review_depths';
import { demoteCurrentUser, prioritizeMentionedMembers } from '~/lib/utils/autocomplete_mentions';
import { isCurrentViewWorkItem } from '~/work_items/utils';
import { flowTriggerEventForCommand, isRemovalCommand, userIsDisabled } from '~/ai/agents_utils';
import { FLOW_TRIGGER_EVENTS } from '~/vue_shared/constants';
import { COMMANDS, COMMANDS_WITH_LOCAL_DATA, MEMBER_COMMANDS } from '../constants';

// A plain emoji with skin tones is suggested and inserted in the user's default tone, as in the plain text editor.
const withDefaultSkinTone = (item) => {
  const name = withPreferredTone(item.emoji.name);

  return name === item.emoji.name
    ? item
    : { ...item, emoji: getEmojiInfo(name, false) || item.emoji };
};

const MAX_BACKEND_RESULTS = 50;

export function defaultSorter(searchFields) {
  return (items, query) => {
    if (!query) return items;

    const sortOrdersMap = new WeakMap();

    items.forEach((item) => {
      const sortOrders = searchFields.map((searchField) => {
        const haystack = String(item[searchField]).toLocaleLowerCase();
        const needle = query.toLocaleLowerCase();

        const i = haystack.indexOf(needle);
        if (i < 0) return i;
        return Number.MAX_SAFE_INTEGER - i;
      });

      sortOrdersMap.set(item, Math.max(...sortOrders));
    });

    return items.sort((a, b) => sortOrdersMap.get(b) - sortOrdersMap.get(a));
  };
}

export function commandSorter(searchFields) {
  const fallback = defaultSorter(searchFields);

  return (items, query) => {
    if (!query) return items;

    const lowerQuery = query.toLocaleLowerCase();

    const hasNamePrefix = (item) => (item.name || '').toLocaleLowerCase().startsWith(lowerQuery);
    const hasAliasPrefix = (item) =>
      (item.aliases || []).some((alias) => alias.toLocaleLowerCase().startsWith(lowerQuery));

    // Use default sorting when no alias is available for this command
    if (!items.some(hasAliasPrefix)) return fallback(items, query);

    // Map score based on command name and alias
    const scores = new Map(
      items.map((item) => {
        let score = 1;
        if (hasNamePrefix(item)) score = 3;
        else if (hasAliasPrefix(item)) score = 2;
        return [item, score];
      }),
    );

    return [...items].sort((a, b) => scores.get(b) - scores.get(a));
  };
}

// Like the plain text editor and `User#gfm_autocomplete_search`, match the name
// with its spaces removed. Rich text queries can contain spaces, so strip those too.
// Only this client match strips them: the backend keeps them in `search`.
const withoutSpaces = (text) => String(text).replace(/ /g, '').toLocaleLowerCase();
const userSearchTerms = (user) => [user.name, user.username].map(withoutSpaces);

export function userMatcher(user, query) {
  const needle = withoutSpaces(query);
  return userSearchTerms(user).some((term) => term.includes(needle));
}

export function userSorter(items, query) {
  if (!query) return items;

  const needle = withoutSpaces(query);
  return sortBy(items, (user) =>
    userSearchTerms(user).some((term) => term.startsWith(needle)) ? 0 : 1,
  );
}

// Plain mentions list the signed-in user last; member quick actions often target yourself.
export function mentionSorter(items, query) {
  const needle = query ? withoutSpaces(query) : '';
  const tierOf = (user) => (userSearchTerms(user).some((term) => term.startsWith(needle)) ? 0 : 1);
  return demoteCurrentUser(userSorter(items, query), tierOf);
}

export function customSorter(sorter) {
  return (items) => items.sort(sorter);
}

const milestonesMap = new WeakMap();

function parseMilestone(milestone) {
  if (!milestone.title) {
    return milestone;
  }

  const dueDate = milestone.due_date ? newDate(milestone.due_date) : null;
  const expired = dueDate ? Date.now() > dueDate.getTime() : false;

  return {
    id: milestone.iid,
    title: milestone.title,
    expired,
    dueDate,
  };
}

function mapMilestone(milestone) {
  if (!milestonesMap.has(milestone)) {
    milestonesMap.set(milestone, parseMilestone(milestone));
  }

  return milestonesMap.get(milestone);
}

function mapCommand(command) {
  return {
    ...command,
    search: [command.name, ...(command.aliases || [])].join(' '),
  };
}

function sortMilestones(milestoneA, milestoneB) {
  const mappedA = mapMilestone(milestoneA);
  const mappedB = mapMilestone(milestoneB);

  // Move all expired milestones to the bottom.
  if (milestoneA.expired) return 1;
  if (milestoneB.expired) return -1;

  // Move milestones without due dates just above expired milestones.
  if (!milestoneA.dueDate) return 1;
  if (!milestoneB.dueDate) return -1;

  return mappedA.dueDate - mappedB.dueDate;
}

export function createDataSource({
  referenceType,
  source,
  searchFields,
  filter,
  mapper = identity,
  sorter = defaultSorter(searchFields),
  matcher = (item, query) =>
    searchFields.some((field) =>
      String(item[field]).toLocaleLowerCase().includes(query.toLocaleLowerCase()),
    ),
  cache = true,
  limit = 15,
  filterOnBackend = false,
  isWorkItemsView,
}) {
  const request = async ({ query, mentioned = [] }) => {
    const params = {};
    if (filterOnBackend) params.search = query;
    // Ask the backend to include already-mentioned members even when they
    // fall outside the search-limited default set, so they can be surfaced.
    if (mentioned.length) params.mentioned = mentioned;

    const queryOptions = Object.keys(params).length ? { params } : {};
    return source ? (await axios.get(source, queryOptions)).data : [];
  };
  const fetchData = (args) => request(args).catch(() => []);

  const cacheTimeoutFn = () => (cache ? 0 : Math.floor(Date.now() / 1e4));
  const memoizedFetchData = memoize(fetchData, cacheTimeoutFn);

  // Mentioned users change the response, so they are part of the key. After each
  // mention is inserted, the next search misses the cache and waits.
  const backendSearchKey = ({ query, mentioned }) =>
    JSON.stringify([cacheTimeoutFn(), mentioned, query]);
  const backendResults = new Map();
  const pendingBackendSearches = new Map();

  // Keep only the most recently used searches, so a long-lived page does not grow.
  const rememberResults = (key, data) => {
    backendResults.delete(key);
    backendResults.set(key, data);
    if (backendResults.size > MAX_BACKEND_RESULTS) {
      backendResults.delete(backendResults.keys().next().value);
    }
  };

  // Failed searches are not kept, so typing the query again retries it.
  const backendSearch = (args) => {
    const key = backendSearchKey(args);
    if (backendResults.has(key)) {
      const data = backendResults.get(key);
      rememberResults(key, data);
      return Promise.resolve(data);
    }

    if (!pendingBackendSearches.has(key)) {
      const pending = request(args)
        .then((data) => {
          rememberResults(key, data);
          return data;
        })
        .catch(() => [])
        .finally(() => pendingBackendSearches.delete(key));
      pendingBackendSearches.set(key, pending);
    }

    return pendingBackendSearches.get(key);
  };

  // Prefer a prefix whose results arrived, so narrowing does not wait on a request.
  const searchedPrefix = (query, mentioned) => {
    const prefixes = Array.from({ length: query.length + 1 }, (_, i) =>
      query.slice(0, query.length - i),
    );
    const key = (prefix) => backendSearchKey({ query: prefix, mentioned });

    return (
      prefixes.find((prefix) => backendResults.has(key(prefix))) ??
      prefixes.find((prefix) => pendingBackendSearches.has(key(prefix))) ??
      null
    );
  };

  const filterAndSort = (data, query, { prioritizeUsernames, threadParticipants }) => {
    let results = data.map(mapper);
    if (filter) results = filter(results, query);

    if (query) {
      // We want fuzzy search only on labels but it can
      // be expanded to other commands if needed
      if (referenceType === REFERENCE_TYPES.LABEL) {
        results = fuzzaldrinPlus.filter(results, query, { key: searchFields });
      } else {
        results = results.filter((item) => !searchFields.length || matcher(item, query));
      }
    }

    // Thread participants go first within each match tier, and users already
    // mentioned go above all for member quick actions, before the limit applies.
    const boosted = prioritizeMentionedMembers(results, threadParticipants);
    const sorted = prioritizeMentionedMembers(sorter(boosted, query), prioritizeUsernames);
    return sorted.slice(0, limit);
  };

  const refine = debounce(async ({ query, mentioned, boosts, shown, onRefine }) => {
    const data = await backendSearch({ query, mentioned });
    if (!backendResults.has(backendSearchKey({ query, mentioned }))) return;

    const refined = filterAndSort(data, query, boosts);
    if (!isEqual(refined, shown)) onRefine(refined);
  }, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);

  return {
    search: async (
      prefixCommand = '',
      query,
      { mentioned = [], prioritizeUsernames = [], threadParticipants = [], onRefine } = {},
    ) => {
      const boosts = { prioritizeUsernames, threadParticipants };
      let results = [];
      let narrowed = false;

      // We only want to fetch autocomplete data over the network
      // if it is not available locally in Apollo Cache for Work Items.
      // eg; `/unassign` shows list of currently assigned users (available locally)
      //     Same is the case with `/unlabel` and `/unlink`.
      if (!isWorkItemsView || !COMMANDS_WITH_LOCAL_DATA.includes(prefixCommand)) {
        if (filterOnBackend) {
          // Like the plain text editor, narrow down what a shorter query returned
          // right away, and refine it once the backend answers the full query.
          const prefix = searchedPrefix(query, mentioned) ?? query;
          narrowed = prefix !== query;
          results = await backendSearch({ query: prefix, mentioned });
        } else {
          results = await memoizedFetchData({ query });
        }
      }

      const shown = filterAndSort(results, query, boosts);

      if (onRefine) {
        // Drop a refine still waiting for an older query, which may have been deleted.
        refine.cancel();
      }
      if (narrowed && onRefine) {
        refine({ query, mentioned, boosts, shown, onRefine });
      }

      return shown;
    },
  };
}

export default class AutocompleteHelper {
  tiptapEditor;

  constructor({ dataSourceUrls, sidebarMediator, threadParticipants = [] }) {
    this.isWorkItemsView = isCurrentViewWorkItem();
    this.threadParticipants = threadParticipants;

    this.updateDataSources(dataSourceUrls);

    this.sidebarMediator = sidebarMediator;

    initEmojiMap();
  }

  updateDataSources(dataSourceUrls) {
    this.dataSourceUrls = !isEmpty(dataSourceUrls)
      ? dataSourceUrls
      : gl.GfmAutoComplete?.dataSources || {};

    this.getDataSource = memoize(this.#getDataSource, (referenceType, { command } = {}) => {
      if (referenceType === 'command') return referenceType;
      return referenceType + (command ? `_${command}` : '');
    });
  }

  #getDataSource = (referenceType, { command, ...options } = {}) => {
    const sources = {
      user: this.dataSourceUrls.members,
      issue: this.dataSourceUrls.issues,
      [REFERENCE_TYPES.ISSUE_ALTERNATIVE]: this.dataSourceUrls.issues,
      [REFERENCE_TYPES.WORK_ITEM]: this.dataSourceUrls.issues,
      snippet: this.dataSourceUrls.snippets,
      label: this.dataSourceUrls.labels,
      epic: this.dataSourceUrls.epics,
      [REFERENCE_TYPES.EPIC_ALTERNATIVE]: this.dataSourceUrls.epics,
      iteration: this.dataSourceUrls.iterations,
      milestone: this.dataSourceUrls.milestones,
      merge_request: this.dataSourceUrls.mergeRequests,
      vulnerability: this.dataSourceUrls.vulnerabilities,
      command: this.dataSourceUrls.commands,
      wiki: this.dataSourceUrls.wikis,
    };

    const searchFields = {
      user: ['username', 'name'],
      issue: ['iid', 'title'],
      [REFERENCE_TYPES.WORK_ITEM]: ['iid', 'title'],
      [REFERENCE_TYPES.ISSUE_ALTERNATIVE]: ['iid', 'title'],
      snippet: ['id', 'title'],
      label: ['title'],
      epic: ['iid', 'title'],
      [REFERENCE_TYPES.EPIC_ALTERNATIVE]: ['iid', 'title'],
      iteration: ['id', 'title'],
      status: ['name'],
      type: ['name'],
      [REFERENCE_TYPES.DUO_CODE_REVIEW_DEPTH]: ['name'],
      vulnerability: ['id', 'title'],
      merge_request: ['iid', 'title'],
      milestone: ['title', 'iid'],
      command: ['name', 'search'],
      wiki: ['title'],
      emoji: [],
    };

    const filters = {
      label: (items) => {
        const { workItemId } =
          this.tiptapEditor?.view.dom.closest('.js-gfm-wrapper')?.dataset || {};

        if (this.isWorkItemsView && command === COMMANDS.UNLABEL && workItemId) {
          return appliedLabels()[workItemId] || [];
        }

        return items.filter((item) => {
          if (command === COMMANDS.UNLABEL) return item.set;
          if (command === COMMANDS.LABEL) return !item.set;

          return true;
        });
      },
      user: (allItems) => {
        const flowTriggerEvent = flowTriggerEventForCommand(command) ?? FLOW_TRIGGER_EVENTS.MENTION;
        const items = isRemovalCommand(command)
          ? allItems
          : allItems.filter((item) => !userIsDisabled(item, flowTriggerEvent));
        const { workItemId } =
          this.tiptapEditor?.view.dom.closest('.js-gfm-wrapper')?.dataset || {};

        // For work items, read from its cache to handle both /assign and /unassign
        if (this.isWorkItemsView && workItemId) {
          const cachedAssignees = currentAssignees()[workItemId] || [];

          // Return assigned users as present in work item cache
          if (command === COMMANDS.UNASSIGN) {
            return cachedAssignees;
          }

          // For /assign, filter out already-assigned users from network results
          if (command === COMMANDS.ASSIGN) {
            return items.filter(
              (item) => !cachedAssignees.some((assignee) => assignee.username === item.username),
            );
          }
        }

        // Non-work-items path (uses sidebarMediator)
        return items.filter((item) => {
          const assigned = this.sidebarMediator?.store?.assignees.some(
            (assignee) => assignee.username === item.username,
          );
          const assignedReviewer = this.sidebarMediator?.store?.reviewers.some(
            (reviewer) => reviewer.username === item.username,
          );

          if (command === COMMANDS.ASSIGN) return !assigned;
          if (command === COMMANDS.ASSIGN_REVIEWER) return !assignedReviewer;
          if (command === COMMANDS.UNASSIGN) return assigned;
          if (command === COMMANDS.UNASSIGN_REVIEWER || command === COMMANDS.REMOVE_REVIEWER)
            return assignedReviewer;

          return true;
        });
      },
      /**
       * We're overriding returned items instead of filtering out
       * irrelevant items because for `/unlink #`, it should show
       * all linked items at once without waiting for user to
       * manually search items.
       */
      issue: (items) => {
        let filteredItems = items;

        if (command === COMMANDS.UNLINK) {
          const { workItemFullPath, workItemIid } =
            this.tiptapEditor?.view.dom.closest('.js-gfm-wrapper')?.dataset || {};

          if (workItemFullPath && workItemIid) {
            const links = linkedItems()[`${workItemFullPath}:${workItemIid}`] || [];
            filteredItems = links.map((link) => ({
              id: Number(link.iid),
              iid: Number(link.iid),
              title: link.title,
              reference: link.reference,
              search: `${link.iid} ${link.title}`,
              icon_name: link.workItemType.iconName,
            }));
          }
        }

        return filteredItems;
      },
      status: () => {
        if (command === COMMANDS.STATUS) {
          const { workItemFullPath, workItemTypeId } =
            this.tiptapEditor?.view.dom.closest('.js-gfm-wrapper')?.dataset || {};

          if (workItemFullPath && workItemTypeId) {
            const statuses = availableStatuses()[workItemFullPath];
            return statuses?.[workItemTypeId] || [];
          }
        }
        return [];
      },
      type: () => {
        if (command === COMMANDS.TYPE) {
          const { workItemFullPath, workItemTypeId } =
            this.tiptapEditor?.view.dom.closest('.js-gfm-wrapper')?.dataset || {};

          if (workItemFullPath && workItemTypeId) {
            const types = supportedConversionTypes()[workItemFullPath];
            return types?.[workItemTypeId] || [];
          }
        }
        return [];
      },
      [REFERENCE_TYPES.DUO_CODE_REVIEW_DEPTH]: () => getDuoCodeReviewDepths(command),
      command: (items) => {
        // Forms opt out of quick actions they reject, e.g. /internal_note on diff comments.
        const { excludeCommands } =
          this.tiptapEditor?.view.dom.closest('[data-exclude-commands]')?.dataset || {};
        if (!excludeCommands) return items;

        const excluded = excludeCommands.split(',').map((name) => name.trim());
        return items.filter((item) => !excluded.includes(item.name));
      },
      emoji: (_, query) =>
        (query
          ? searchEmoji(query)
          : getAllEmoji().map((emoji) => ({ emoji, fieldValue: emoji.name }))
        ).map(withDefaultSkinTone),
    };

    const sorters = {
      milestone: customSorter(sortMilestones),
      user: MEMBER_COMMANDS.includes(command) ? userSorter : mentionSorter,
      command: commandSorter(searchFields[referenceType]),
      default: defaultSorter(searchFields[referenceType]),
      // do not sort emoji
      emoji: customSorter(() => 0),
    };

    const mappers = {
      milestone: mapMilestone,
      command: mapCommand,
      default: identity,
    };

    return createDataSource({
      referenceType,
      source: sources[referenceType],
      searchFields: searchFields[referenceType],
      mapper: mappers[referenceType] || mappers.default,
      sorter: sorters[referenceType] || sorters.default,
      matcher: referenceType === REFERENCE_TYPES.USER ? userMatcher : undefined,
      filter: filters[referenceType],
      isWorkItemsView: this.isWorkItemsView,
      command,

      ...options,
    });
  };
}
