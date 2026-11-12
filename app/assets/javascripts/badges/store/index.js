import { defineStore } from 'pinia';
import { normalizeHeaders } from '@gitlab/frontend-utils';
import axios from '~/lib/utils/axios_utils';
import { convertObjectPropsToCamelCase, parseIntPagination } from '~/lib/utils/common_utils';
import { isValidURL } from '~/lib/utils/url_utility';
import { PAGE_SIZE, PROJECT_BADGE } from '../constants';
import createEmptyBadge from '../empty_badge';

export const transformBackendBadge = (badge) => ({
  ...convertObjectPropsToCamelCase(badge, true),
  isDeleting: false,
});

const reorderBadges = (badges) =>
  badges.sort((a, b) => {
    if (a.kind !== b.kind) {
      return a.kind === PROJECT_BADGE ? 1 : -1;
    }

    return a.id - b.id;
  });

const createEmptyPagination = () => ({
  perPage: null,
  page: null,
  total: null,
  totalPages: null,
  nextPage: null,
  previousPage: null,
});

export const useBadgeSettings = defineStore('badgeSettings', {
  state() {
    return {
      kind: null,
      apiEndpointUrl: null,
      badgeInAddForm: createEmptyBadge(),
      badgeInEditForm: createEmptyBadge(),
      badgeInModal: null,
      badges: [],
      pagination: createEmptyPagination(),
      renderedBadge: null,
      isEditing: false,
      isLoading: false,
      isRendering: false,
      isSaving: false,
    };
  },
  actions: {
    setInitialState({ kind, apiEndpointUrl }) {
      this.kind = kind;
      this.apiEndpointUrl = apiEndpointUrl;
    },

    async addBadge() {
      const newBadge = this.badgeInAddForm;
      this.isSaving = true;
      try {
        await axios.post(this.apiEndpointUrl, {
          name: newBadge.name,
          image_url: newBadge.imageUrl,
          link_url: newBadge.linkUrl,
        });
      } finally {
        this.isSaving = false;
      }

      this.badgeInAddForm = createEmptyBadge();
      this.renderedBadge = null;
      this.loadBadges({ page: this.pagination.page });
    },

    async deleteBadge(badge) {
      const badgeId = badge.id;
      this.setBadgeIsDeleting(badgeId, true);
      try {
        await axios.delete(`${this.apiEndpointUrl}/${badgeId}`);
      } catch (error) {
        this.setBadgeIsDeleting(badgeId, false);
        throw error;
      }

      this.loadBadges({ page: this.pagination.page });
    },

    setBadgeIsDeleting(badgeId, isDeleting) {
      const badge = this.badges.find(({ id }) => id === badgeId);
      if (badge) {
        badge.isDeleting = isDeleting;
      }
    },

    editBadge(badge) {
      this.badgeInEditForm = { ...badge };
      this.isEditing = true;
      this.renderedBadge = { ...badge };
    },

    async loadBadges({ page }) {
      this.isLoading = true;
      try {
        const { data, headers } = await axios.get(this.apiEndpointUrl, {
          params: {
            page,
            per_page: PAGE_SIZE,
          },
        });
        this.badges = reorderBadges(data.map((badge) => transformBackendBadge(badge)));
        this.pagination = parseIntPagination(normalizeHeaders(headers));
      } finally {
        this.isLoading = false;
      }
    },

    requestRenderedBadge() {
      this.isRendering = true;
    },
    receiveRenderedBadge(renderedBadge) {
      this.isRendering = false;
      this.renderedBadge = renderedBadge;
    },
    receiveRenderedBadgeError() {
      this.isRendering = false;
    },

    async renderBadge() {
      const badge = this.isEditing ? this.badgeInEditForm : this.badgeInAddForm;
      const { linkUrl, imageUrl } = badge;
      if (
        !linkUrl ||
        linkUrl.trim() === '' ||
        !isValidURL(linkUrl) ||
        !imageUrl ||
        imageUrl.trim() === '' ||
        !isValidURL(imageUrl)
      ) {
        return;
      }

      this.requestRenderedBadge();

      const parameters = [
        `link_url=${encodeURIComponent(linkUrl)}`,
        `image_url=${encodeURIComponent(imageUrl)}`,
      ].join('&');
      // eslint-disable-next-line @gitlab/no-hardcoded-urls -- appending /render suffix to a server-provided endpoint URL. Not ideal but acceptable.
      const renderEndpoint = `${this.apiEndpointUrl}/render?${parameters}`;
      try {
        const { data } = await axios.get(renderEndpoint);
        this.receiveRenderedBadge(transformBackendBadge(data));
      } catch (error) {
        this.receiveRenderedBadgeError();
        throw error;
      }
    },

    requestUpdatedBadge() {
      this.isSaving = true;
    },
    receiveUpdatedBadge(updatedBadge) {
      const index = this.badges.findIndex(({ id }) => id === updatedBadge.id);
      if (index !== -1) {
        this.badges.splice(index, 1, updatedBadge);
      }
      this.badgeInEditForm = createEmptyBadge();
      this.isEditing = false;
      this.isSaving = false;
      this.renderedBadge = null;
    },
    receiveUpdatedBadgeError() {
      this.isSaving = false;
    },

    async saveBadge() {
      const badge = this.badgeInEditForm;
      this.requestUpdatedBadge();
      try {
        const { data } = await axios.put(`${this.apiEndpointUrl}/${badge.id}`, {
          name: badge.name,
          image_url: badge.imageUrl,
          link_url: badge.linkUrl,
        });
        this.receiveUpdatedBadge(transformBackendBadge(data));
      } catch (error) {
        this.receiveUpdatedBadgeError();
        throw error;
      }
    },

    stopEditing() {
      this.badgeInEditForm = createEmptyBadge();
      this.isEditing = false;
      this.renderedBadge = null;
    },

    updateBadgeInForm(badge) {
      if (this.isEditing) {
        this.badgeInEditForm = badge;
      } else {
        this.badgeInAddForm = badge;
      }
    },

    resetBadgeInForm() {
      this.updateBadgeInForm(createEmptyBadge());
    },

    updateBadgeInModal(badge) {
      this.badgeInModal = badge;
    },
  },
});
