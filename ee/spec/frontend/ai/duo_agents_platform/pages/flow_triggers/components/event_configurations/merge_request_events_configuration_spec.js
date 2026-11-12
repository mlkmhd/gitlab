import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { MERGE_REQUEST_ACTIONS } from 'ee/ai/duo_agents_platform/constants';
import MergeRequestEventsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/merge_request_events_configuration.vue';
import EventActionsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/event_actions_configuration.vue';

const actionRule = (actions) => ({ field: 'action', operator: 'in', value: actions });
const createdByFlowRule = (values) => ({ field: 'created_by_flow', operator: 'in', value: values });
const draftRule = (values) => ({ field: 'draft', operator: 'in', value: values });
const buildFilter = (...rules) => ({ merge_request: { rules } });

describe('MergeRequestEventsConfiguration', () => {
  let wrapper;

  const createComponent = ({ value = {}, invalidFeedback = null, softwareFactory = true } = {}) => {
    wrapper = shallowMountExtended(MergeRequestEventsConfiguration, {
      provide: { glFeatures: { dapSoftwareFactory: softwareFactory } },
      propsData: { value, invalidFeedback },
    });
  };

  const findActionsConfiguration = () => wrapper.findComponent(EventActionsConfiguration);
  const findCreatedByFlowFormGroup = () => wrapper.findByTestId('created-by-flow-form-group');
  const findCreatedByFlowListbox = () =>
    findCreatedByFlowFormGroup().findComponent(GlCollapsibleListbox);
  const findDraftFormGroup = () => wrapper.findByTestId('draft-form-group');
  const findDraftListbox = () => findDraftFormGroup().findComponent(GlCollapsibleListbox);
  const lastEmittedFilter = () => wrapper.emitted('input').at(-1)[0];

  describe('action picker', () => {
    const filter = buildFilter(actionRule(['approved']), draftRule([false]));

    beforeEach(() => {
      createComponent({ value: filter, invalidFeedback: 'Select an action.' });
    });

    it('passes the merge request actions and the filter to the actions picker', () => {
      expect(findActionsConfiguration().props()).toMatchObject({
        scope: 'merge_request',
        field: 'action',
        actions: MERGE_REQUEST_ACTIONS,
        listboxHeaderText: 'Select merge request actions',
        value: filter,
        invalidFeedback: 'Select an action.',
      });
    });

    it('emits the filter of the actions picker, with the field rules it keeps', () => {
      const nextFilter = buildFilter(actionRule(['approved', 'merged']), draftRule([false]));

      findActionsConfiguration().vm.$emit('input', nextFilter);

      expect(lastEmittedFilter()).toEqual(nextFilter);
    });
  });

  describe('when dap_software_factory is off', () => {
    beforeEach(() => {
      createComponent({
        value: buildFilter(actionRule(['approved']), createdByFlowRule([true])),
        softwareFactory: false,
      });
    });

    it('does not render the created by and draft listboxes', () => {
      expect(findCreatedByFlowFormGroup().exists()).toBe(false);
      expect(findDraftFormGroup().exists()).toBe(false);
    });

    it('keeps a stored rule when the actions change', () => {
      const nextFilter = buildFilter(actionRule(['merged']), createdByFlowRule([true]));

      findActionsConfiguration().vm.$emit('input', nextFilter);

      expect(lastEmittedFilter()).toEqual(nextFilter);
    });
  });

  describe('created by listbox', () => {
    describe('without a created_by_flow rule', () => {
      beforeEach(() => {
        createComponent({ value: buildFilter(actionRule(['approved'])) });
      });

      it('renders the label, the description, and the empty text', () => {
        const toggleId = findCreatedByFlowListbox().props('toggleId');

        expect(toggleId).toEqual(expect.any(String));
        expect(findCreatedByFlowFormGroup().attributes()).toMatchObject({
          label: 'Created by',
          'label-for': toggleId,
          description:
            'Run only for merge requests that a flow created, or only for other merge requests. Leave empty to run for any merge request.',
        });
        expect(findCreatedByFlowListbox().props()).toMatchObject({
          selected: null,
          toggleText: 'Anyone',
          headerText: 'Select creator',
          resetButtonLabel: 'Clear',
          items: [
            { value: 'yes', text: 'A flow', disabled: false },
            { value: 'no', text: 'Someone else', disabled: false },
          ],
        });
      });

      it.each`
        option   | values
        ${'yes'} | ${[true]}
        ${'no'}  | ${[false]}
      `('adds a created_by_flow in $values rule for "$option"', ({ option, values }) => {
        findCreatedByFlowListbox().vm.$emit('select', option);

        expect(lastEmittedFilter()).toEqual(
          buildFilter(actionRule(['approved']), createdByFlowRule(values)),
        );
      });
    });

    describe('with a created_by_flow in [false] rule', () => {
      beforeEach(() => {
        createComponent({
          value: buildFilter(
            actionRule(['approved']),
            createdByFlowRule([false]),
            draftRule([false]),
          ),
        });
      });

      it('selects "Someone else"', () => {
        expect(findCreatedByFlowListbox().props()).toMatchObject({
          selected: 'no',
          toggleText: 'Someone else',
        });
      });

      it('replaces the rule and keeps the other rules', () => {
        findCreatedByFlowListbox().vm.$emit('select', 'yes');

        expect(lastEmittedFilter()).toEqual(
          buildFilter(actionRule(['approved']), draftRule([false]), createdByFlowRule([true])),
        );
      });

      it('removes the rule on reset', () => {
        findCreatedByFlowListbox().vm.$emit('reset');

        expect(lastEmittedFilter()).toEqual(
          buildFilter(actionRule(['approved']), draftRule([false])),
        );
      });
    });

    it('shows no selection for a rule with both values', () => {
      createComponent({ value: buildFilter(createdByFlowRule([true, false])) });

      expect(findCreatedByFlowListbox().props('selected')).toBeNull();
    });

    it('removes the scope when the reset leaves no rule', () => {
      createComponent({ value: { mention: {}, ...buildFilter(createdByFlowRule([true])) } });

      findCreatedByFlowListbox().vm.$emit('reset');

      expect(lastEmittedFilter()).toEqual({ mention: {} });
    });
  });

  describe('draft listbox', () => {
    describe('without Marked ready', () => {
      beforeEach(() => {
        createComponent({ value: buildFilter(actionRule(['approved'])) });
      });

      it('renders the label, the description, and the enabled options', () => {
        expect(findDraftFormGroup().attributes()).toMatchObject({
          label: 'Draft',
          'label-for': findDraftListbox().props('toggleId'),
          description:
            'Run only for draft merge requests, or only for merge requests that are not drafts. Leave empty to run for both.',
        });
        expect(findDraftListbox().props()).toMatchObject({
          selected: null,
          toggleText: 'Draft or ready',
          headerText: 'Select draft status',
          resetButtonLabel: 'Clear',
          items: [
            { value: 'yes', text: 'Yes', disabled: false },
            { value: 'no', text: 'No', disabled: false },
          ],
        });
      });

      it('uses a toggle ID of its own', () => {
        expect(findDraftListbox().props('toggleId')).not.toBe(
          findCreatedByFlowListbox().props('toggleId'),
        );
      });

      it.each`
        option   | values
        ${'yes'} | ${[true]}
        ${'no'}  | ${[false]}
      `('adds a draft in $values rule for "$option"', ({ option, values }) => {
        findDraftListbox().vm.$emit('select', option);

        expect(lastEmittedFilter()).toEqual(
          buildFilter(actionRule(['approved']), draftRule(values)),
        );
      });
    });

    it('disables "Yes" when Marked ready is selected without a draft rule', () => {
      createComponent({ value: buildFilter(actionRule(['ready'])) });

      expect(findDraftListbox().props()).toMatchObject({
        selected: null,
        toggleText: 'Draft or ready',
        items: [
          { value: 'yes', text: 'Yes', disabled: true },
          { value: 'no', text: 'No', disabled: false },
        ],
      });
    });

    describe('with Marked ready and a draft in [true] rule', () => {
      beforeEach(() => {
        createComponent({
          value: buildFilter(actionRule(['approved', 'ready']), draftRule([true])),
        });
      });

      it('disables "Yes" and keeps it selected, so the user can clear it', () => {
        expect(findDraftListbox().props()).toMatchObject({
          selected: 'yes',
          toggleText: 'Yes',
          items: [
            { value: 'yes', text: 'Yes', disabled: true },
            { value: 'no', text: 'No', disabled: false },
          ],
        });
      });

      it('says why "Yes" is not available', () => {
        expect(findDraftFormGroup().attributes('description')).toBe(
          'Draft merge requests are not available with Marked ready.',
        );
      });

      it('does not disable a created by option', () => {
        expect(
          findCreatedByFlowListbox()
            .props('items')
            .some(({ disabled }) => disabled),
        ).toBe(false);
      });

      it('removes the rule on reset', () => {
        findDraftListbox().vm.$emit('reset');

        expect(lastEmittedFilter()).toEqual(buildFilter(actionRule(['approved', 'ready'])));
      });
    });
  });

  it('renders the listboxes in their own form groups', () => {
    createComponent();

    expect(wrapper.findAllComponents(GlFormGroup)).toHaveLength(2);
  });
});
