import projectLabelsWithGroupAndMarkup from 'test_fixtures/graphql/work_items/integration/project_labels_with_group_and_markup.query.graphql.json';
import createLabelResponse from 'test_fixtures/graphql/work_items/integration/create_label.mutation.graphql.json';
import createLabelDuplicateTitleResponse from 'test_fixtures/graphql/work_items/integration/create_label_duplicate_title.mutation.graphql.json';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { projectLabels as projectLabelsVariants } from 'ee_jest/integration/work_items/fixture_variants';
import { resetCreatedLabels } from 'ee_jest/integration/work_items/handlers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

const labelTitles = projectLabelsWithGroupAndMarkup.data.namespace.labels.nodes.map(
  ({ title }) => title,
);
const MARKUP_TITLE = labelTitles.find((title) => title.startsWith('<'));
const createdLabel = createLabelResponse.data.labelCreate.label;
const [duplicateTitleError] = createLabelDuplicateTitleResponse.data.labelCreate.errors;

// Adding a label is covered by describeDrawerInteractions in drawer_shared_test_helpers.js.
describe('Work item labels widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const { findLabelsWidget } = workItemsHelpers;
  const findOptionNames = () =>
    testHelpers
      .within(findLabelsWidget())
      .queryAllByRole('option')
      .map((option) => testHelpers.getText(option));
  const findOption = (title) => () => {
    const widget = findLabelsWidget();
    return widget ? testHelpers.within(widget).queryByRole('option', { name: title }) : null;
  };
  // Each applied label carries its title as its test id. Compared as data rather than through
  // a selector, because one of the titles is markup.
  const findSelectedLabel = (title) => () =>
    [...(findLabelsWidget()?.querySelectorAll('[data-testid]') ?? [])].find(
      (element) => element.dataset.testid === title,
    ) ?? null;
  const findCreateLabelButton = () =>
    findLabelsWidget()?.querySelector('[data-testid="create-label"]') ?? null;
  const findLabelNameInput = () => findLabelsWidget()?.querySelector('#label-title-input') ?? null;
  const findCustomColorInput = () =>
    findLabelsWidget()?.querySelector('input[placeholder="Use custom color #FF0000"]') ?? null;
  const findCreateButton = () =>
    findLabelsWidget()?.querySelector('[data-testid="create-button"]') ?? null;
  const findCreateError = () => findLabelsWidget()?.querySelector('.gl-alert') ?? null;

  const startEditing = () => workItemsHelpers.startEditing(findLabelsWidget);
  const applyLabels = () => workItemsHelpers.closeListbox(findLabelsWidget);

  const fillCreateForm = async (title) => {
    await testHelpers.waitAndClick(findCreateLabelButton);
    await testHelpers.waitAndSetValue(findLabelNameInput, title);
    await testHelpers.waitAndSetValue(findCustomColorInput, createdLabel.color);
    await testHelpers.waitAndClick(findCreateButton);
  };

  beforeEach(async () => {
    // Every page sets the suggested colours, and the create form renders them.
    window.gon.suggested_label_colors = { [createdLabel.color]: 'Magenta-pink' };
    resetCreatedLabels();
    setQueryVariant(projectLabelsVariants).withGroupAndMarkup();

    mountWorkItemsListApp({ router });

    await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(findLabelsWidget);
  });

  // The fixture carries a group label and a title that is markup next to the project's own.
  it('lists every label, rendering markup in a title as text', async () => {
    await startEditing();

    await testHelpers.waitForAssertion(() => {
      expect(findOptionNames()).toEqual(labelTitles);
    });
    expect(findLabelsWidget().querySelector('script')).toBe(null);
  });

  it('adds a label and clears it again', async () => {
    const [title] = labelTitles.filter((candidate) => candidate !== MARKUP_TITLE);

    await startEditing();
    await testHelpers.waitAndClick(findOption(title));
    applyLabels();
    await testHelpers.waitForElement(findSelectedLabel(title));

    await startEditing();
    await testHelpers.waitAndClick(workItemsHelpers.findClearButton(findLabelsWidget));

    await testHelpers.waitForAssertion(() => {
      expect(findSelectedLabel(title)()).toBe(null);
      expect(testHelpers.getText(findLabelsWidget())).toContain('None');
    });
  });

  it('creates a project label, selects it and applies it', async () => {
    await startEditing();
    await fillCreateForm(createdLabel.title);

    // The form closes onto the list with the new label already picked.
    await testHelpers.waitForAssertion(() => {
      expect(findOption(createdLabel.title)()?.getAttribute('aria-selected')).toBe('true');
    });

    applyLabels();

    await testHelpers.waitForElement(findSelectedLabel(createdLabel.title));
  });

  it('shows the server error when the title is already taken', async () => {
    const [takenTitle] = labelTitles;

    await startEditing();
    await fillCreateForm(takenTitle);

    await testHelpers.waitForAssertion(() => {
      expect(testHelpers.getText(findCreateError())).toContain(duplicateTitleError);
    });
  });
});
