<script>
import {
  GlButton,
  GlEmptyState,
  GlIcon,
  GlLoadingIcon,
  GlTableLite,
  GlTruncate,
  GlTooltipDirective,
} from '@gitlab/ui';
import { createAlert } from '~/alert';
import { __, s__, sprintf } from '~/locale';
import { scrollToElement } from '~/lib/utils/scroll_utils';
import HelpIcon from '~/vue_shared/components/help_icon/help_icon.vue';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import Markdown from '~/vue_shared/components/markdown/non_gfm_markdown.vue';
import PageNavigationMenu from '~/vue_shared/components/page_navigation_menu.vue';
import getCiCatalogResourceComponents from '../../graphql/queries/get_ci_catalog_resource_components.query.graphql';

export default {
  name: 'CiResourceComponents',
  components: {
    GlButton,
    GlEmptyState,
    GlIcon,
    GlLoadingIcon,
    GlTableLite,
    GlTruncate,
    HelpIcon,
    HelpPageLink,
    Markdown,
    PageNavigationMenu,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    resourcePath: {
      type: String,
      required: true,
    },
    version: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      components: [],
    };
  },
  apollo: {
    components: {
      query: getCiCatalogResourceComponents,
      variables() {
        return {
          fullPath: this.resourcePath,
          version: this.version,
        };
      },
      update(data) {
        return data?.ciCatalogResource?.versions?.nodes[0]?.components?.nodes || [];
      },
      error() {
        createAlert({
          message: s__("CiCatalogComponent|There was an error fetching this resource's components"),
        });
      },
      result() {
        this.$nextTick(() => {
          if (window.location.hash) {
            const componentName = decodeURIComponent(window.location.hash.substring(1));
            this.scrollToComponent(componentName);
          }
        });
      },
    },
  },
  computed: {
    isMetadataMissing() {
      return !this.components || this.components?.length === 0;
    },
    isLoading() {
      return this.$apollo.queries.components.loading;
    },
    navigationItems() {
      return this.components.map((component) => ({
        id: encodeURIComponent(component.name),
        label: component.name,
      }));
    },
  },
  methods: {
    generateSnippet(componentPath) {
      // This is not to be translated because it is our CI yaml syntax.
      // eslint-disable-next-line @gitlab/require-i18n-strings
      return `include:
  - component: ${componentPath}`;
    },
    getItemValue(item) {
      return String(item.default);
    },
    shouldShowCodeBlock(item) {
      return item.default && item.type === 'ARRAY';
    },
    getCodeBlock(item) {
      try {
        return JSON.stringify(item.default, null, 2);
      } catch (e) {
        return String(item.default);
      }
    },
    hasRuleOptions(item) {
      return Boolean(item.rules?.some((rule) => rule.options?.length));
    },
    getRequirementLabel(item) {
      return item.required
        ? s__('CiCatalogComponent|required')
        : s__('CiCatalogComponent|optional');
    },
    getComponentLabel(componentName) {
      return sprintf(s__('CiCatalogComponent|Link to %{componentName}'), { componentName });
    },
    scrollToComponent(componentName) {
      const hash = `#${encodeURIComponent(componentName)}`;
      window.history.pushState(null, '', hash);
      const element = document.getElementById(encodeURIComponent(componentName));
      if (element) {
        scrollToElement(element, { behavior: 'smooth' });
      }
    },
  },
  fields: [
    {
      key: 'name',
      label: s__('CiCatalogComponent|Name'),
    },
    {
      key: 'description',
      label: s__('CiCatalogComponent|Description'),
    },
    {
      key: 'options',
      label: s__('CiCatalogComponent|Options'),
    },
    {
      key: 'default',
      label: s__('CiCatalogComponent|Default'),
    },
  ],
  i18n: {
    learnMore: __('Learn more'),
  },
};
</script>

<template>
  <div>
    <gl-loading-icon v-if="isLoading" size="lg" />
    <gl-empty-state
      v-else-if="isMetadataMissing"
      :title="s__('CiCatalogComponent|Component details not available')"
      :description="
        s__(
          'CiCatalogComponent|This tab displays auto-collected information about the components in the repository, but no information was found.',
        )
      "
    />
    <div v-else class="gl-flex gl-gap-6">
      <div class="gl-flex-grow-1 gl-min-w-0">
        <div
          v-for="component in components"
          :id="encodeURIComponent(component.name)"
          :key="component.id"
          class="gl-mb-8 gl-scroll-mt-8"
          data-testid="component-section"
        >
          <h3 class="gl-group gl-mt-0 gl-text-size-h2" data-testid="component-name">
            {{ component.name }}
            <gl-button
              :href="`#${encodeURIComponent(component.name)}`"
              class="gl-invisible gl-ml-2 !gl-text-subtle group-hover:gl-visible"
              :aria-label="getComponentLabel(component.name)"
              icon="link"
              variant="link"
              @click.prevent="scrollToComponent(component.name)"
            />
            <span
              v-gl-tooltip.top
              data-testid="usage-count"
              :title="
                s__(
                  'CiCatalogComponent|Number of unique projects that used this version of the component in the last 30 days.',
                )
              "
              class="gl-ml-2 gl-text-sm gl-font-normal gl-text-subtle"
            >
              <gl-icon name="chart" />
              <span class="gl-ml-1">{{ component.last30DayUsageCount }}</span>
            </span>
          </h3>
          <p
            v-if="component.description"
            class="gl-mt-2 gl-text-subtle"
            data-testid="component-description"
          >
            {{ component.description }}
          </p>
          <pre
            data-testid="copy-to-clipboard"
            class="code highlight js-syntax-highlight language-yaml gl-mt-3"
          ><code>{{
            generateSnippet(component.includePath)
          }}</code></pre>
          <div class="gl-mt-5">
            <div class="gl-mb-4 gl-flex gl-gap-2">
              <b> {{ s__('CiCatalogComponent|Inputs') }}</b>
              <help-page-link
                href="ci/inputs/_index.md"
                anchor="define-input-parameters-with-specinputs"
                :title="$options.i18n.learnMore"
                data-testid="input-help-link"
                target="_blank"
              >
                <help-icon />
              </help-page-link>
            </div>
            <gl-table-lite :items="component.inputs" :fields="$options.fields" stacked="md" fixed>
              <template #cell(name)="{ item }">
                <code v-if="item.name" data-testid="input-name">{{ item.name }}</code>
                <div class="gl-mt-2 gl-text-sm gl-text-subtle">
                  <span data-testid="input-type">{{ item.type.toLowerCase() }}</span>
                  ·
                  <span :class="{ 'gl-font-bold': item.required }" data-testid="input-required">{{
                    getRequirementLabel(item)
                  }}</span>
                </div>
              </template>
              <template #cell(description)="{ item }">
                <div data-testid="input-description" class="gl-break-words">
                  <markdown v-if="item.description" :markdown="item.description" />
                </div>
              </template>
              <template #cell(options)="{ item }">
                <div v-if="Array.isArray(item.options)" class="gl-flex gl-flex-wrap gl-gap-2">
                  <code v-for="option in item.options" :key="option" data-testid="input-option">{{
                    option
                  }}</code>
                </div>
                <span
                  v-else-if="hasRuleOptions(item)"
                  class="gl-text-subtle"
                  data-testid="input-rules-note"
                >
                  {{ s__('CiCatalogComponent|Options depend on other input values') }}
                  <help-page-link
                    href="ci/inputs/_index.md"
                    anchor="define-conditional-input-options-with-specinputsrules"
                    :title="$options.i18n.learnMore"
                    data-testid="input-rules-help-link"
                    target="_blank"
                  >
                    <help-icon />
                  </help-page-link>
                </span>
              </template>
              <template #cell(default)="{ item }">
                <pre
                  v-if="shouldShowCodeBlock(item)"
                  class="gl-text-left gl-text-sm"
                  data-testid="input-code-block"
                  >{{ getCodeBlock(item) }}</pre>
                <code v-else-if="getItemValue(item)" data-testid="input-default">
                  <gl-truncate
                    :text="getItemValue(item)"
                    position="end"
                    class="gl-max-w-full"
                    with-tooltip
                  />
                </code>
              </template>
            </gl-table-lite>
          </div>
        </div>
      </div>
      <div class="gl-w-64 gl-hidden gl-flex-shrink-0 @lg/panel:gl-block">
        <page-navigation-menu :items="navigationItems" />
      </div>
    </div>
  </div>
</template>
