import { print } from 'graphql';
import { gql } from '@apollo/client/core';
import cable from '~/actioncable_consumer';
import ActionCableLink from '~/actioncable_link';

// Mock uuids module for determinism
jest.mock('~/lib/utils/uuids', () => ({
  uuids: () => ['testuuid'],
}));

const TEST_OPERATION = {
  query: gql`
    query foo {
      project {
        id
      }
    }
  `,
  operationName: 'foo',
  variables: [],
};

/**
 * Create an observer that passes calls to the given spy.
 *
 * This helps us assert which calls were made in what order.
 */
const createSpyObserver = (spy) => ({
  next: (...args) => spy('next', ...args),
  error: (...args) => spy('error', ...args),
  complete: (...args) => spy('complete', ...args),
});

const notify = (...notifications) => {
  notifications.forEach((data) => cable.subscriptions.notifyAll('received', data));
};

const getSubscriptionCount = () => cable.subscriptions.subscriptions.length;

describe('~/actioncable_link', () => {
  let cableLink;

  beforeEach(() => {
    jest.spyOn(cable.subscriptions, 'create');

    cableLink = new ActionCableLink();
  });

  describe('request', () => {
    let subscription;
    let spy;
    let onSubscriptionConfirmed;

    beforeEach(() => {
      spy = jest.fn();
      onSubscriptionConfirmed = jest.fn();
      subscription = cableLink
        .request({ ...TEST_OPERATION, getContext: () => ({ onSubscriptionConfirmed }) })
        .subscribe(createSpyObserver(spy));
    });

    afterEach(() => {
      subscription.unsubscribe();
    });

    it('creates a subscription', () => {
      expect(getSubscriptionCount()).toBe(1);
      expect(cable.subscriptions.create).toHaveBeenCalledWith(
        {
          channel: 'GraphqlChannel',
          nonce: 'testuuid',
          ...TEST_OPERATION,
          query: print(TEST_OPERATION.query),
        },
        { received: expect.any(Function), connected: expect.any(Function) },
      );
    });

    it('when "unsubscribe", unsubscribes underlying cable subscription', () => {
      subscription.unsubscribe();

      expect(getSubscriptionCount()).toBe(0);
    });

    it('when receives data, triggers observer until no ".more"', () => {
      notify(
        { result: 'test result', more: true },
        { result: 'test result 2', more: true },
        { result: 'test result 3' },
        { result: 'test result 4' },
      );

      expect(spy.mock.calls).toEqual([
        ['next', 'test result'],
        ['next', 'test result 2'],
        ['next', 'test result 3'],
        ['complete'],
      ]);
    });

    it('when receives errors, triggers observer', () => {
      notify(
        { result: 'test result', more: true },
        { result: 'test result 2', errors: ['boom!'], more: true },
        { result: 'test result 3' },
      );

      expect(spy.mock.calls).toEqual([
        ['next', 'test result'],
        ['error', ['boom!']],
      ]);
    });

    it('emits "actioncable:reconnected" event on reconnected', () => {
      const eventSpy = jest.spyOn(document, 'dispatchEvent');

      cable.subscriptions.subscriptions[0].connected({ reconnected: true });

      expect(eventSpy).toHaveBeenCalledWith(new CustomEvent('actioncable:reconnected'));
    });

    it('does not emit "actioncable:reconnected" event on initial connection', () => {
      const eventSpy = jest.spyOn(document, 'dispatchEvent');

      cable.subscriptions.subscriptions[0].connected({ reconnected: false });

      expect(eventSpy).not.toHaveBeenCalled();
    });

    it.each([false, true])(
      'calls onSubscriptionConfirmed from the context when confirmed (reconnected: %s)',
      (reconnected) => {
        expect(onSubscriptionConfirmed).not.toHaveBeenCalled();

        cable.subscriptions.subscriptions[0].connected({ reconnected });

        expect(onSubscriptionConfirmed).toHaveBeenCalledTimes(1);
      },
    );
  });
});
