import { ApolloLink, Observable } from '@apollo/client/core';
import { SESSION_EXPIRES_AT_HEADER } from './constants';
import { broadcastSessionExpiry } from './session_expiry';

const broadcastFromContext = (operation) => {
  const { headers } = operation.getContext().response || {};

  broadcastSessionExpiry(headers?.get(SESSION_EXPIRES_AT_HEADER));
};

/**
 * GraphQL needs its own link because the Apollo client sends requests through `fetch`
 * rather than axios, so a page driven entirely by GraphQL never reaches the axios
 * interceptor that otherwise keeps the session countdown up to date.
 *
 * Kept apart from the axios interceptor so that bundles pulling in axios do not also
 * pull in the Apollo client.
 *
 * Taps both the success and error paths: Apollo surfaces non-2xx responses as link
 * errors rather than `next()` emissions, so a `.map()` alone would miss the deadline on
 * an errored-but-still-authenticated response, and a failed request is still activity.
 */
export const apolloSessionExpiryLink = new ApolloLink(
  (operation, forward) =>
    new Observable((observer) => {
      const subscription = forward(operation).subscribe({
        next: (response) => {
          broadcastFromContext(operation);
          observer.next(response);
        },
        error: (error) => {
          broadcastFromContext(operation);
          observer.error(error);
        },
        complete: observer.complete.bind(observer),
      });

      return () => subscription.unsubscribe();
    }),
);
