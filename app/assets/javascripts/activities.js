/* eslint-disable class-methods-use-this */

import $ from 'jquery';
import { getCookie, setCookie } from '~/lib/utils/common_utils';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import { InfiniteScroller } from '~/infinite_scroller';
import axios from '~/lib/utils/axios_utils';
import { removeParams } from '~/lib/utils/url_utility';
import { localTimeAgo } from './lib/utils/datetime_utility';

export default class Activities {
  constructor(containerSelector = '') {
    this.containerSelector = containerSelector;
    this.containerEl = this.containerSelector
      ? document.querySelector(this.containerSelector)
      : undefined;
    this.$contentList = $('.content_list');

    this.loadActivities();

    $('.event-filter-link').on('click', this.toggleFilter.bind(this));
  }

  loadActivities() {
    const limit = 20;
    const root = (this.containerEl || document).querySelector('.js-infinite-scrolling-root');
    this.scroller = new InfiniteScroller({
      root,
      fetchNextPage: async (offset, signal) => {
        return axios
          .get(this.$contentList.data('href') || removeParams(['limit', 'offset']), {
            params: { limit, offset },
            signal,
          })
          .then(({ data: { count, html } }) => {
            if (signal.aborted) return null;
            this.loadErrorAlert?.dismiss();
            this.loadErrorAlert = null;
            return { count, html };
          })
          .catch((error) => {
            if (signal.aborted || axios.isCancel(error)) return null;
            if (!this.loadErrorAlert) {
              this.loadErrorAlert = createAlert({
                message: s__('Activity|Failed to load more activity.'),
                parent: root,
                containerSelector: '.js-infinite-scrolling-error',
                dismissible: false,
                primaryButton: {
                  text: s__('Activity|Retry'),
                  loading: false,
                  clickHandler: () => this.retryActivities(),
                },
              });
            }
            throw error;
          });
      },
      limit,
    });
    this.scroller.initialize();
    this.scroller.eventTarget.addEventListener(
      InfiniteScroller.events.htmlInserted,
      this.updateTooltips,
    );
  }

  updateTooltips() {
    localTimeAgo(document.querySelectorAll('.content_list .js-timeago'));
  }

  async retryActivities() {
    const alert = this.loadErrorAlert;
    alert?.setPrimaryButtonLoading(true);
    await this.scroller.retry();
    alert?.setPrimaryButtonLoading(false);
  }

  reloadActivities() {
    this.$contentList.html('');
    this.loadErrorAlert?.dismiss();
    this.loadErrorAlert = null;
    this.scroller.eventTarget.removeEventListener(
      InfiniteScroller.events.htmlInserted,
      this.updateTooltips,
    );
    this.scroller.destroy();
    this.loadActivities();
  }

  toggleFilter(event) {
    event.preventDefault();
    const $sender = $(event.currentTarget);
    const filter = $sender.attr('id').split('_')[0];
    if (getCookie('event_filter') === filter) return;
    setCookie('event_filter', filter);
    $('.event-filter .active').removeClass('active');
    $sender.closest('li').toggleClass('active');
    this.reloadActivities(filter);
  }
}
