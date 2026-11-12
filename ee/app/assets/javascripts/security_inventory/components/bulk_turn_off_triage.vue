<script>
import { GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import { s__, sprintf } from '~/locale';
import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { selectionLabel } from 'ee/security_configuration/components/scan_profiles/utils';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import detachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_detach.mutation.graphql';

export default normalizeRender({
  name: 'BulkTurnOffTriage',
  mixins: [GlToastMixin],
  inject: ['groupFullPath'],
  props: {
    itemIds: {
      type: Array,
      required: true,
    },
  },
  emits: ['turned-off', 'refetch'],
  data() {
    return { isTurningOff: false };
  },
  computed: {
    groupIds() {
      return this.itemIds.filter((id) => id.includes('Group'));
    },
    projectIds() {
      return this.itemIds.filter((id) => id.includes('Project'));
    },
    selection() {
      return selectionLabel(this.projectIds.length, this.groupIds.length);
    },
  },
  methods: {
    confirm() {
      return confirmAction(
        s__(
          "SecurityInventory|New vulnerabilities aren't triaged or fixed. Merge requests it already opened stay open.",
        ),
        {
          title: sprintf(
            s__('SecurityInventory|Turn off Automated Triage and Remediation for %{selection}?'),
            { selection: this.selection },
          ),
          primaryBtnText: s__('SecurityInventory|Turn off'),
          primaryBtnVariant: 'danger',
          size: 'md',
        },
      );
    },
    async loadPresets() {
      const { data } = await this.$apollo.query({
        query: groupAvailableSecurityScanProfilesQuery,
        variables: { fullPath: this.groupFullPath, gitlabRecommended: true },
      });

      return (data?.group?.availableSecurityScanProfiles ?? []).filter(
        ({ scanType }) => scanType === SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
      );
    },
    // One call at a time: the profile services take a lease per project.
    detachAll(presets) {
      const errors = [];

      return presets
        .reduce(
          (chain, { id }) =>
            chain.then(async () => {
              const { data } = await this.$apollo.mutate({
                mutation: detachMutation,
                variables: {
                  input: {
                    securityScanProfileId: id,
                    groupIds: this.groupIds,
                    projectIds: this.projectIds,
                  },
                },
              });

              errors.push(...(data?.securityScanProfileDetach?.errors ?? []));
            }),
          Promise.resolve(),
        )
        .then(() => errors);
    },
    async turnOff() {
      if (this.isTurningOff) return;

      this.isTurningOff = true;
      try {
        if (!(await this.confirm())) return;

        const presets = await this.loadPresets();
        const errors = await this.detachAll(presets);

        if (errors.length) {
          createAlert({ message: errors.join(', ') });
          this.$emit('refetch');
          return;
        }

        this.$toast.show(
          sprintf(
            s__('SecurityInventory|Automated Triage and Remediation turned off for %{selection}'),
            { selection: this.selection },
          ),
        );
        this.$emit('turned-off');
      } catch (error) {
        createAlert({
          message: s__('SecurityInventory|Failed to turn off Automated Triage and Remediation.'),
        });
        Sentry.captureException(error);
        this.$emit('refetch');
      } finally {
        this.isTurningOff = false;
      }
    },
  },
  render() {
    return null;
  },
});
</script>
