import { s__ } from '~/locale';
import { OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import BaseToken from '~/vue_shared/components/filtered_search_bar/tokens/base_token.vue';
import { CAPABILITIES_KEY, CAPABILITIES_FILTER_LABELS } from '../constants';

const options = Object.entries(CAPABILITIES_FILTER_LABELS).map(([value, title]) => ({
  value,
  title,
}));

export const capabilitiesTokens = [
  {
    type: CAPABILITIES_KEY,
    title: s__('SecurityInventory|Capabilities'),
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
];
