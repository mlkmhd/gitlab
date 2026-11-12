import { sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import deleteAiCatalogItemConsumer from './graphql/mutations/delete_ai_catalog_item_consumer.mutation.graphql';
import { getRegistryItem } from './item_type_registry';

/**
 * Disables an item by deleting its consumer.
 *
 * @returns {Promise<{ error?: { title: string, errors: string[] }, successMessage?: string }>}
 */
export async function disableItemConsumer({ apollo, item, refetchQuery, namespaceType }) {
  const { disable } = getRegistryItem(item.itemType);

  try {
    const { data } = await apollo.mutate({
      mutation: deleteAiCatalogItemConsumer,
      variables: {
        id: item.itemConsumer.id,
      },
      refetchQueries: [refetchQuery],
    });

    if (!data.aiCatalogItemConsumerDelete.success) {
      return {
        error: { title: disable.error, errors: data.aiCatalogItemConsumerDelete.errors },
      };
    }

    return { successMessage: sprintf(disable.success, { namespaceType }) };
  } catch (error) {
    Sentry.captureException(error);
    return { error: { title: disable.error, errors: [error.message] } };
  }
}
