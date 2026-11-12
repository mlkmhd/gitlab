import { ApolloLink, Observable } from '@apollo/client/core';
import { print } from 'graphql';
import cable from '~/actioncable_consumer';
import { uuids } from '~/lib/utils/uuids';

export default class ActionCableLink extends ApolloLink {
  // eslint-disable-next-line class-methods-use-this
  request(operation) {
    const { onSubscriptionConfirmed } = operation.getContext();

    return new Observable((observer) => {
      const subscription = cable.subscriptions.create(
        {
          channel: 'GraphqlChannel',
          query: operation.query ? print(operation.query) : null,
          variables: operation.variables,
          operationName: operation.operationName,
          nonce: uuids()[0],
        },
        {
          received(data) {
            if (data.errors) {
              observer.error(data.errors);
            } else if (data.result) {
              observer.next(data.result);
            }

            if (!data.more) {
              observer.complete();
            }
          },
          // we want to react to websocket reconnection events to update data on stale browser tabs
          connected({ reconnected }) {
            // ActionCable confirms only after the server streams the subscription topic, so
            // a trigger sent from this point on reaches the subscriber.
            onSubscriptionConfirmed?.();

            if (reconnected) {
              document.dispatchEvent(new CustomEvent('actioncable:reconnected'));
            }
          },
        },
      );

      return {
        unsubscribe() {
          subscription.unsubscribe();
        },
      };
    });
  }
}
