import { s__, sprintf } from '~/locale';
import { FIELD_TYPES } from '../../../constants';
import { baseFieldKeyOf } from '../../../utils/chart_data';

// Sources where a run can happen outside any project, so a null project is a real bucket.
// Everywhere else (Pipelines, for one) a null project means it was deleted or is unreadable.
const PROJECTLESS_SOURCES = ['DuoWorkflows', 'AgentPlatformSessions'];

// The engines return NULL for a hierarchy dimension when the flow sits outside the requested
// level, so the row is a real bucket that needs a name. A deleted namespace's ID no longer
// resolves either, which the panel description covers. The engines default `depth` to 1.
const DIMENSION_NULL_LABELS = {
  group: (field) => {
    // Parameters arrive from the compiler as strings.
    const depth = Number(field.parameters?.depth ?? 1);

    // At depth 2 the NULL bucket holds the top-level group's own projects and flows, plus
    // anything whose group the viewer cannot see.
    if (depth === 2) {
      return {
        text: s__('Glql|Not in a subgroup'),
        hint: s__('Glql|May include subgroups you cannot see'),
      };
    }

    return {
      text: s__('Glql|No group'),
      hint: sprintf(s__('Glql|No group at depth %{depth}'), { depth }),
    };
  },
  project: (field, source) => ({
    text: s__('Glql|No project'),
    hint: PROJECTLESS_SOURCES.includes(source)
      ? s__('Glql|Not tied to a project, or a project you cannot see')
      : null,
  }),
};

/**
 * The label for a null group or project dimension, which is a real bucket rather than a
 * missing value, or null for any other value.
 */
export const dimensionNullLabelOf = (field, item, source) => {
  const label = DIMENSION_NULL_LABELS[baseFieldKeyOf(field)];
  if (label && field.type === FIELD_TYPES.DIMENSION && item[field.key] == null) {
    return label(field, source);
  }

  return null;
};
