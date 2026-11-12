import { HttpResponse } from 'msw';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import groupSettingsVariants from './fixture_variants/get_orbit_group_settings';
import orbitUpdateVariants from './fixture_variants/orbit_update';

// orbitUpdate flips this so the refetch after it sees the group on, like the backend.
let groupEnabled = false;

export const resetOrbitState = () => {
  groupEnabled = false;
};

const OPERATION_HANDLERS = {
  getOrbitGroupSettings: () =>
    getActiveVariant('getOrbitGroupSettings') ??
    (groupEnabled ? groupSettingsVariants.INDEXING : groupSettingsVariants.BASE),
  orbitUpdate: ({ variables }) => {
    const variant = getActiveVariant('orbitUpdate');
    if (!variant) groupEnabled = variables.input.enabled;
    return variant ?? orbitUpdateVariants.BASE;
  },
};

export function handleOrbitOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  return handler ? HttpResponse.json(handler({ variables })) : null;
}

export const orbitRestEndpoints = [];
