import Vue from 'vue';
import VueApollo from 'vue-apollo';
import IterationPopover from 'ee_component/issuable/popover/components/iteration_popover.vue';
import createDefaultClient from '~/lib/graphql';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { dispose as disposeTooltip } from '~/tooltips';
import CommitPopover from './components/commit_popover.vue';
import WorkItemPopover from './components/work_item_popover.vue';
import MRPopover from './components/mr_popover.vue';
import MilestonePopover from './components/milestone_popover.vue';
import CommentPopover from './components/comment_popover.vue';

export const componentsByReferenceTypeMap = {
  epic: WorkItemPopover,
  issue: WorkItemPopover,
  work_item: WorkItemPopover,
  merge_request: MRPopover,
  milestone: MilestonePopover,
  iteration: IterationPopover,
  commit: CommitPopover,
  comment: CommentPopover,
};

const popoverMountedAttr = 'data-popover-mounted';

function isCommentPopover(target) {
  if (!target.href) return false;

  const targetUrl = new URL(target.href);
  const noteId = targetUrl.hash;

  return noteId && noteId.startsWith('#note_');
}

function popoverProps(
  type,
  {
    target,
    commitSha,
    projectPath,
    namespacePath,
    iid,
    placement,
    milestone,
    iteration,
    title,
    titleHtml,
    innerText,
  },
) {
  if (type === 'comment') return { target };
  if (type === 'commit') return { target, commitSha, projectPath };

  return {
    target,
    namespacePath,
    iid,
    placement,
    milestoneId: milestone,
    iterationId: iteration,
    cachedTitle: title || innerText,
    cachedTitleHtml: titleHtml,
    show: true,
  };
}

/**
 * Adds a Popover component for issuables and work items to the body,
 * hands over as much data as the target element has in data attributes.
 * loads based on data-project-path and data-iid more data about an MR
 * from the API and sets it on the popover
 *
 * `onMount` receives the popover's app root. Tear it down with `unmountVueApp`:
 * on Vue 3 its legacy `$destroy()` is inert.
 */
export const handleIssuablePopoverMount = ({
  componentsByReferenceType = componentsByReferenceTypeMap,
  apolloProvider,
  referenceType,
  target,
  onMount,
  cancelOnMouseLeave = true,
  ...popoverData
}) => {
  // Per call, so leaving one target never cancels another target's pending mount.
  // Returned so a caller that arms on focus can cancel on blur; such a caller passes
  // `cancelOnMouseLeave: false` so a passing pointer does not cancel a focused target.
  let timer;
  const cancel = () => {
    clearTimeout(timer);
    target.removeEventListener('mouseleave', cancel);
  };
  if (cancelOnMouseLeave) target.addEventListener('mouseleave', cancel);

  timer = setTimeout(() => {
    const type = isCommentPopover(target) ? 'comment' : referenceType;

    // A detached element is enough: GlPopover portals its markup into `document.body`.
    // Do not go back to `Vue.extend(Component)` + `new`: under @vue/compat bootstrap-vue builds
    // its BVPopover helpers through that constructor and inherits the popover's options.
    const popover = initVueApp({
      el: document.createElement('div'),
      component: componentsByReferenceType[type],
      props: popoverProps(type, { target, ...popoverData }),
      apolloProvider,
    });

    target.setAttribute(popoverMountedAttr, true);
    onMount?.(popover);
  }, 200); // 200ms delay so not every mouseover triggers Popover + API Call

  return cancel;
};

export default (elements, issuablePopoverMount = handleIssuablePopoverMount) => {
  if (elements.length > 0) {
    Vue.use(VueApollo);

    const apolloProvider = new VueApollo({
      defaultClient: createDefaultClient(),
    });
    const listenerAddedAttr = 'data-popover-listener-added';

    elements.forEach((el) => {
      const { projectPath, groupPath, iid, referenceType, milestone, iteration, placement } =
        el.dataset;
      let { namespacePath } = el.dataset;
      const title = el.dataset.mrTitle || el.title;
      const { titleHtml } = el.dataset;
      const { innerText } = el;
      namespacePath = namespacePath || groupPath || projectPath;
      const isIssuable = Boolean(namespacePath && title && iid);
      const isMilestone = Boolean(milestone);
      const isIteration = Boolean(iteration);
      const isCommit = referenceType === 'commit' && Boolean(el.dataset.commit && projectPath);

      if (
        !el.getAttribute(listenerAddedAttr) &&
        referenceType &&
        (isIssuable || isMilestone || isIteration || isCommit)
      ) {
        el.addEventListener('mouseenter', ({ target }) => {
          if (!el.getAttribute(popoverMountedAttr)) {
            target.removeAttribute('title');
            target.classList.remove('has-tooltip');
            disposeTooltip(target);
            issuablePopoverMount({
              apolloProvider,
              namespacePath,
              title,
              titleHtml,
              iid,
              milestone,
              iteration,
              innerText,
              referenceType,
              target,
              placement,
              commitSha: el.dataset.commit,
              projectPath,
            });
          }
        });
        el.setAttribute(listenerAddedAttr, true);
      }
    });
  }
};
