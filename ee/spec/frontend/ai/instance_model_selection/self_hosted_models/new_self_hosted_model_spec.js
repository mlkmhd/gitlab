import { nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';
import SelfHostedModelForm from 'ee/ai/instance_model_selection/self_hosted_models/components/self_hosted_model_form.vue';
import createSelfHostedModelMutation from 'ee/ai/instance_model_selection/self_hosted_models/graphql/mutations/create_self_hosted_model.mutation.graphql';
import NewSelfHostedModel from 'ee/ai/instance_model_selection/self_hosted_models/components/new_self_hosted_model.vue';
import { SELF_HOSTED_MODEL_MUTATIONS } from 'ee/ai/instance_model_selection/self_hosted_models/constants';
import { INSTANCE_MODEL_SELECTION_ROUTE_NAMES } from 'ee/ai/instance_model_selection/constants';

describe('NewSelfHostedModel', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMount(NewSelfHostedModel, {});
  };

  beforeEach(() => {
    createComponent();
  });

  const findSelfHostedModelForm = () => wrapper.findComponent(SelfHostedModelForm);

  const enterFrom = async (name) => {
    NewSelfHostedModel.beforeRouteEnter({}, { name }, (callback) => callback(wrapper.vm));
    await nextTick();
  };

  it('has a title', () => {
    expect(wrapper.text()).toMatch('Add self-hosted model');
  });

  it('has a description', () => {
    expect(wrapper.text()).toMatch(
      'Add a new AI model that can be used for GitLab Duo self-hosted features.',
    );
  });

  it('renders the self-hosted model form and passes the correct props', () => {
    const selfHostedModelForm = findSelfHostedModelForm();

    expect(selfHostedModelForm.exists()).toBe(true);
    expect(selfHostedModelForm.props('mutationData')).toEqual({
      name: SELF_HOSTED_MODEL_MUTATIONS.CREATE,
      mutation: createSelfHostedModelMutation,
    });
  });

  describe('when opened from the self-hosted models tab', () => {
    beforeEach(async () => {
      await enterFrom(INSTANCE_MODEL_SELECTION_ROUTE_NAMES.MODELS);
    });

    it('sends Cancel back to the self-hosted models tab', () => {
      expect(findSelfHostedModelForm().props('cancelRouteName')).toBe(
        INSTANCE_MODEL_SELECTION_ROUTE_NAMES.MODELS,
      );
    });
  });

  describe.each([
    INSTANCE_MODEL_SELECTION_ROUTE_NAMES.INDEX,
    INSTANCE_MODEL_SELECTION_ROUTE_NAMES.FEATURES,
    undefined,
  ])('when opened from %s', (name) => {
    beforeEach(async () => {
      await enterFrom(name);
    });

    it('keeps the default Cancel route', () => {
      expect(findSelfHostedModelForm().props('cancelRouteName')).toBe(null);
    });
  });
});
