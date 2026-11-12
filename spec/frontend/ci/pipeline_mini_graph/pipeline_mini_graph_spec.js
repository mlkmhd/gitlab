import Vue from 'vue';
import VueApollo from 'vue-apollo';

import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';

import PipelineMiniGraph from '~/ci/pipeline_mini_graph/pipeline_mini_graph.vue';
import CiIcon from '~/vue_shared/components/ci_icon/ci_icon.vue';
import DownstreamPipelines from '~/ci/pipeline_mini_graph/downstream_pipelines.vue';
import PipelineStages from '~/ci/pipeline_mini_graph/pipeline_stages.vue';

import { pipelineStage, singlePipeline, mockDownstreamPipelinesGraphql } from './mock_data';

Vue.use(VueApollo);

describe('PipelineMiniGraph', () => {
  let wrapper;

  const defaultProps = {
    downstreamPipelines: mockDownstreamPipelinesGraphql.nodes,
    isMergeTrain: true,
    pipelinePath: '/path/to/pipeline',
    pipelineStages: [pipelineStage],
    upstreamPipeline: singlePipeline,
  };

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(PipelineMiniGraph, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
    });
  };

  const findUpstream = () => wrapper.findComponent(CiIcon);
  const findDownstream = () => wrapper.findComponent(DownstreamPipelines);
  const findStages = () => wrapper.findComponent(PipelineStages);
  const findDownstreamArrow = () => wrapper.findComponentByTestId('downstream-arrow-icon');
  const findUpstreamArrow = () => wrapper.findComponentByTestId('upstream-arrow-icon');

  describe('on render', () => {
    describe('stages', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders stages', () => {
        expect(findStages().exists()).toBe(true);
      });

      it('sends the necessary props', () => {
        expect(findStages().props()).toMatchObject({
          isMergeTrain: defaultProps.isMergeTrain,
          stages: defaultProps.pipelineStages,
        });
      });

      it('emits mini-graph-stage-click', () => {
        findStages().vm.$emit('mini-graph-stage-click');
        expect(wrapper.emitted('mini-graph-stage-click')).toHaveLength(1);
      });

      it('emits job-action-executed from stages', () => {
        findStages().vm.$emit('job-action-executed');
        expect(wrapper.emitted('job-action-executed')).toHaveLength(1);
      });
    });

    describe('upstream', () => {
      it('renders upstream if available', () => {
        createComponent();
        expect(findUpstream().exists()).toBe(true);
      });

      it('labels the upstream arrow with a tooltip', () => {
        createComponent();

        expect(findUpstreamArrow().attributes('title')).toBe('Upstream pipeline');
        expect(findUpstreamArrow().props('ariaLabel')).toBe('Upstream pipeline');
        expect(getBinding(findUpstreamArrow().element, 'gl-tooltip')).toBeDefined();
      });

      it('does not render upstream if not available', () => {
        createComponent({
          props: { upstreamPipeline: {} },
        });
        expect(findUpstream().exists()).toBe(false);
        expect(findUpstreamArrow().exists()).toBe(false);
      });
    });

    describe('downstream', () => {
      it('renders downstream if available', () => {
        createComponent();
        expect(findDownstream().exists()).toBe(true);
      });

      it('sends the necessary props', () => {
        createComponent();
        expect(findDownstream().props()).toMatchObject({
          pipelines: expect.any(Array),
          pipelinePath: expect.any(String),
        });
      });

      it('labels the downstream arrow with a tooltip', () => {
        createComponent();

        expect(findDownstreamArrow().attributes('title')).toBe('Downstream pipelines');
        expect(findDownstreamArrow().props('ariaLabel')).toBe('Downstream pipelines');
        expect(getBinding(findDownstreamArrow().element, 'gl-tooltip')).toBeDefined();
      });

      it('does not render downstream if not available', () => {
        createComponent({
          props: { downstreamPipelines: [] },
        });
        expect(findDownstream().exists()).toBe(false);
        expect(findDownstreamArrow().exists()).toBe(false);
      });

      it('emits job-action-executed from downstream pipelines', () => {
        createComponent();
        findDownstream().vm.$emit('job-action-executed');
        expect(wrapper.emitted('job-action-executed')).toHaveLength(1);
      });
    });
  });
});
