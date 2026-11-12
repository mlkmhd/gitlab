function cloneResponse(response) {
  return JSON.parse(JSON.stringify(response));
}

export function buildUpdateResponse({
  baseResponse,
  milestoneFixture,
  labelNodes = [],
  userNodes = [],
  iterationNodes = [],
  statusNodes = [],
  input,
  featuresFixture,
}) {
  const { labelsWidget, assigneesWidget, title } = input;

  /**
   * The mutation selects the whole WorkItemFeatures fragment, so a partial `features`
   * would replace the cached object with incomplete data and trigger a refetch that undoes
   * the update. The detail fixture is built from that same fragment, so it supplies the
   * full shape to override.
   */
  const baseFeaturesResponse = () => {
    const response = cloneResponse(baseResponse);
    const { workItem } = response.data.workItemUpdate;
    delete workItem.widgets;
    workItem.features = cloneResponse(featuresFixture).data.namespace.workItem.features;
    return response;
  };

  const updateFeature = (featureKey, fields) => {
    const response = baseFeaturesResponse();
    Object.assign(response.data.workItemUpdate.workItem.features[featureKey], fields);
    return response;
  };

  // The seeded work item has no labels, so the result is whatever the request adds less
  // whatever it removes, echoed back from the label nodes the dropdown offered.
  if (labelsWidget) {
    const { addLabelIds = [], removeLabelIds = [] } = labelsWidget;
    const nodes = labelNodes.filter(
      ({ id }) => addLabelIds.includes(id) && !removeLabelIds.includes(id),
    );
    return updateFeature('labels', {
      labels: { nodes, __typename: 'LabelConnection' },
    });
  }

  // The widget sends the full assignee list, so this echoes back the users it names.
  if (assigneesWidget) {
    const nodes = assigneesWidget.assigneeIds
      .map((assigneeId) => userNodes.find(({ id }) => id === assigneeId))
      .filter(Boolean);
    return updateFeature('assignees', {
      assignees: { nodes, __typename: 'UserCoreConnection' },
    });
  }

  if (title) {
    const response = baseFeaturesResponse();
    response.data.workItemUpdate.workItem.title = title;
    response.data.workItemUpdate.workItem.titleHtml = title;
    return response;
  }

  if (input.confidential !== undefined) {
    const response = baseFeaturesResponse();
    response.data.workItemUpdate.workItem.confidential = input.confidential;
    return response;
  }

  // Closing and reopening only move the state, but the mutation selects the whole work
  // item, so this echoes the fixture's own widget values back. A test that changes a
  // widget and then closes the item sees that widget snap back to its seeded value.
  if (input.stateEvent) {
    const response = baseFeaturesResponse();
    response.data.workItemUpdate.workItem.state = input.stateEvent === 'CLOSE' ? 'CLOSED' : 'OPEN';
    return response;
  }

  if (input.milestoneWidget) {
    if (!input.milestoneWidget.milestoneId) {
      return updateFeature('milestone', { milestone: null });
    }
    return cloneResponse(milestoneFixture);
  }

  if (input.startAndDueDateWidget) {
    const response = baseFeaturesResponse();
    const { startAndDueDate } = response.data.workItemUpdate.workItem.features;
    Object.assign(startAndDueDate, {
      startDate: input.startAndDueDateWidget.startDate || null,
      dueDate: input.startAndDueDateWidget.dueDate || null,
      isFixed: input.startAndDueDateWidget.isFixed ?? startAndDueDate.isFixed,
    });
    return response;
  }

  if (input.weightWidget) {
    return updateFeature('weight', { weight: input.weightWidget.weight });
  }

  // Clearing sends `{ healthStatus: null }`, so the widget key is present either way.
  if (input.healthStatusWidget) {
    return updateFeature('healthStatus', {
      healthStatus: input.healthStatusWidget.healthStatus,
    });
  }

  // Clearing sends `{ iterationId: null }`, so the widget key is present either way.
  if (input.iterationWidget) {
    const { iterationId } = input.iterationWidget;
    // Echoes back the node the dropdown offered, which is what the server would return.
    const iteration = iterationNodes.find(({ id }) => id === iterationId) ?? null;

    return updateFeature('iteration', { iteration });
  }

  // The dropdown sends the id of a status the namespace allows, so this echoes back the node
  // it offered, which is what the server would return.
  if (input.statusWidget) {
    const status = statusNodes.find(({ id }) => id === input.statusWidget.status) ?? null;

    return updateFeature('status', { status });
  }

  return baseFeaturesResponse();
}

export const AGENT_CREATED_SESSION = {
  __typename: 'DuoWorkflow',
  id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1',
};
