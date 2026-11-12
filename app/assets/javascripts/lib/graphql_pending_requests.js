// Counts in-flight Apollo requests behind `window.pendingApolloRequests`, which
// `wait_for_requests` polls in feature specs and QA. This module imports nothing,
// so the Vue 3 build never duplicates it and every Vue lane shares one counter.

const apolloClients = [];
let nonDedupedOperations = 0;

export const registerApolloClient = (client) => {
  apolloClients.push(client);
};

export const startNonDedupedOperation = () => {
  nonDedupedOperations += 1;
};

export const finishNonDedupedOperation = () => {
  nonDedupedOperations -= 1;
};

// Mutations and queries that opted out of deduplication.
export const pendingNonDedupedOperations = () => nonDedupedOperations;

const isSubscription = (document) =>
  document.definitions.some(
    (definition) =>
      definition.kind === 'OperationDefinition' && definition.operation === 'subscription',
  );

// Deduplicated queries never reach the link chain, so they are counted from each
// client's `inFlightLinkObservables`. A subscription stays in that map until its
// first message arrives, so it is not counted: it is not a request awaiting a
// response. Operations that opt out of deduplication (`forceFetch` in their
// context) do not use the map, so a link counts them instead.
// https://www.apollographql.com/docs/react/v2/networking/network-layer/#query-deduplication
const countInFlightQueries = (client) => {
  let count = 0;

  client?.queryManager?.inFlightLinkObservables?.forEach((observables, document) => {
    if (!isSubscription(document)) {
      count += 1;
    }
  });

  return count;
};

Object.defineProperty(window, 'pendingApolloRequests', {
  get() {
    return apolloClients.reduce((sum, ac) => sum + countInFlightQueries(ac), nonDedupedOperations);
  },
});
