import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { disableItemConsumer } from 'ee/ai/catalog/disable_item_utils';
import deleteAiCatalogItemConsumer from 'ee/ai/catalog/graphql/mutations/delete_ai_catalog_item_consumer.mutation.graphql';
import {
  mockAiCatalogItemConsumerDeleteResponse,
  mockAiCatalogItemConsumerDeleteErrorResponse,
} from './mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('disableItemConsumer', () => {
  const refetchQuery = 'aiCatalogConfiguredItems';
  const agentItem = {
    itemType: 'AGENT',
    itemConsumer: { id: 'gid://gitlab/Ai::Catalog::ItemConsumer/1' },
  };
  const flowItem = {
    itemType: 'FLOW',
    itemConsumer: { id: 'gid://gitlab/Ai::Catalog::ItemConsumer/2' },
  };

  let apollo;

  const callDisable = (item = agentItem, namespaceType = 'group') =>
    disableItemConsumer({ apollo, item, refetchQuery, namespaceType });

  beforeEach(() => {
    apollo = { mutate: jest.fn().mockResolvedValue(mockAiCatalogItemConsumerDeleteResponse) };
  });

  it('calls the delete item consumer mutation with the item consumer id', async () => {
    await callDisable();

    expect(apollo.mutate).toHaveBeenCalledWith({
      mutation: deleteAiCatalogItemConsumer,
      variables: { id: 'gid://gitlab/Ai::Catalog::ItemConsumer/1' },
      refetchQueries: [refetchQuery],
    });
  });

  describe('when the mutation succeeds', () => {
    it.each`
      item         | namespaceType | successMessage
      ${agentItem} | ${'group'}    | ${'Agent disabled in this group.'}
      ${agentItem} | ${'project'}  | ${'Agent disabled in this project.'}
      ${flowItem}  | ${'group'}    | ${'Flow disabled in this group.'}
      ${flowItem}  | ${'project'}  | ${'Flow disabled in this project.'}
    `(
      'returns "$successMessage" for $item.itemType in a $namespaceType',
      async ({ item, namespaceType, successMessage }) => {
        expect(await callDisable(item, namespaceType)).toEqual({ successMessage });
      },
    );
  });

  describe('when the mutation returns errors', () => {
    beforeEach(() => {
      apollo.mutate.mockResolvedValue(mockAiCatalogItemConsumerDeleteErrorResponse);
    });

    it('returns the error title and errors', async () => {
      expect(await callDisable()).toEqual({
        error: {
          title: 'Failed to disable agent',
          errors: ['You do not have permission to disable this item.'],
        },
      });
    });

    it('does not report to Sentry', async () => {
      await callDisable();

      expect(Sentry.captureException).not.toHaveBeenCalled();
    });
  });

  describe('when the mutation fails', () => {
    const error = new Error('Network error');

    beforeEach(() => {
      apollo.mutate.mockRejectedValue(error);
    });

    it('returns the error title and error message', async () => {
      expect(await callDisable(flowItem)).toEqual({
        error: { title: 'Failed to disable flow', errors: ['Network error'] },
      });
    });

    it('reports the error to Sentry', async () => {
      await callDisable();

      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });
  });
});
