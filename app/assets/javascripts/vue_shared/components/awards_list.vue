<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { groupBy } from 'lodash-es';
import SafeHtml from '~/vue_shared/directives/safe_html';
import EmojiPicker from '~/emoji/components/picker.vue';
import { __, sprintf } from '~/locale';
import { glEmojiTag } from '~/emoji';
import { EMOJI_THUMBS_UP, EMOJI_THUMBS_DOWN } from '~/emoji/constants';
import {
  baseName,
  isSkinTonePreferenceEnabled,
  preferredVariant,
  variantsFor,
} from '~/emoji/skin_tone';

// Internal constant, specific to this component, used when no `currentUserId` is given
const NO_USER_ID = -1;
const TOOLTIP_NAME_COUNT = 10;

// Make sure the right capizalization is used depending on where you appear in the list
const insertYou = (index) => (index === 0 ? __('You') : __('you'));

export default {
  name: 'AwardsList',
  components: {
    GlButton,
    EmojiPicker,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
    SafeHtml,
  },
  props: {
    customEmojiPath: {
      type: String,
      required: false,
      default: '',
    },
    awards: {
      type: Array,
      required: true,
    },
    canAwardEmoji: {
      type: Boolean,
      required: true,
    },
    currentUserId: {
      type: [Number, String],
      required: false,
      default: NO_USER_ID,
    },
    defaultAwards: {
      type: Array,
      required: false,
      default: () => [],
    },
    selectedClass: {
      type: String,
      required: false,
      default: 'selected',
    },
  },
  emits: ['award'],
  data() {
    return {
      isMenuOpen: false,
    };
  },
  computed: {
    groupedDefaultAwards() {
      return this.defaultAwards.reduce(
        (obj, key) => Object.assign(obj, { [this.groupName(key)]: [] }),
        {},
      );
    },
    groupedAwards() {
      const { thumbsup, thumbsdown, ...rest } = {
        ...this.groupedDefaultAwards,
        ...groupBy(this.awards, (x) => this.groupName(x.name)),
      };

      return [
        ...(thumbsup ? [this.createAwardList(EMOJI_THUMBS_UP, thumbsup)] : []),
        ...(thumbsdown ? [this.createAwardList(EMOJI_THUMBS_DOWN, thumbsdown)] : []),
        ...Object.entries(rest).map(([name, list]) => this.createAwardList(name, list)),
      ];
    },
  },
  mounted() {
    this.virtualScrollerItem = this.$el.closest('.vue-recycle-scroller__item-view');
  },
  methods: {
    getAwardClassBindings(awardList) {
      return {
        [this.selectedClass]: this.hasReactionByCurrentUser(awardList),
        disabled: this.currentUserId === NO_USER_ID,
      };
    },
    hasReactionByCurrentUser(awardList) {
      return Boolean(this.currentUserAward(awardList));
    },
    currentUserAward(awardList) {
      if (this.currentUserId === NO_USER_ID) {
        return undefined;
      }

      return awardList.find((award) => award.user.id === this.currentUserId);
    },
    // With the skin tone preference, every tone of an emoji shares one group named after the plain emoji.
    groupName(name) {
      return isSkinTonePreferenceEnabled() ? baseName(name) : name;
    },
    createAwardList(name, list) {
      const ownAward = this.currentUserAward(list);
      const awardsByName = this.awardsByName(list, name);
      const names = awardsByName.length
        ? awardsByName.map(([awardName]) => awardName)
        : [this.defaultAwardName(name)];

      return {
        name,
        list,
        // One tooltip line per emoji name, so a grouped pill reads like Slack's reaction tooltip.
        title: awardsByName
          .map(([awardName, awards]) => this.getReactionTitle(awards, awardName))
          .join('\n\n'),
        classes: this.getAwardClassBindings(list),
        html: names.map((awardName) => glEmojiTag(awardName)).join(''),
        toggleName: ownAward?.name ?? this.toggleNameFor(name),
      };
    },
    toggleNameFor(name) {
      return isSkinTonePreferenceEnabled() ? preferredVariant(name) : name;
    },
    // A pill without reactions shows the default award as the mount site gave it, which may be toned.
    defaultAwardName(name) {
      return this.defaultAwards.find((award) => this.groupName(award) === name) ?? name;
    },
    // The group's awards per emoji name, the plain emoji first and then the skin tones light to dark.
    awardsByName(awardsList, name) {
      const toneOrder = [name, ...variantsFor(name)];

      return Object.entries(groupBy(awardsList, (award) => award.name)).sort(
        ([a], [b]) => toneOrder.indexOf(a) - toneOrder.indexOf(b),
      );
    },
    getReactionTitle(awardsList, name) {
      const awardList = awardsList;

      // Make sure current user shows in the list if there are too many reactions to list all users
      if (awardList.length > TOOLTIP_NAME_COUNT && this.hasReactionByCurrentUser(awardList)) {
        const currentUserIndex = awardList.findIndex(
          (award) => award.user.id === this.currentUserId,
        );
        if (currentUserIndex > TOOLTIP_NAME_COUNT - 1) {
          const currentUser = awardList[currentUserIndex];
          awardList.splice(currentUserIndex, 1);
          awardList.splice(TOOLTIP_NAME_COUNT - 1, 0, currentUser);
        }
      }

      // Get only TOOLTIP_NAME_COUNT usernames to show in tooltip text.
      const namesToShow = awardList
        .map(({ user }, index) => (user.id === this.currentUserId ? insertYou(index) : user.name)) // Replace your own username with "You" or "you"
        .slice(0, TOOLTIP_NAME_COUNT); // Only take the first TOOLTIP_NAME_COUNT items

      // Get the remaining list to use in `and x more` text.
      const remainingAwardList = awardList.slice(TOOLTIP_NAME_COUNT, awardList.length);

      let title = '';

      // We have 10+ awarded user, join them with comma and add `and x more`.
      if (remainingAwardList.length) {
        title = sprintf(
          __(`%{listToShow}, and %{awardsListLength} more`),
          {
            listToShow: namesToShow.join(', '),
            awardsListLength: remainingAwardList.length,
          },
          false,
        );
      } else if (namesToShow.length > 1) {
        // Join all names with comma but not the last one, it will be added with and text.
        title = namesToShow.slice(0, namesToShow.length - 1).join(', ');
        // If we have more than 2 users we need an extra comma before and text.
        title += namesToShow.length > 2 ? ',' : '';
        title += sprintf(__(` and %{sliced}`), { sliced: namesToShow.slice(-1) }, false); // Append and text
      } else {
        // We have only 2 users so join them with and.
        title = namesToShow.join(__(' and '));
      }

      return title + sprintf(__(' reacted with :%{name}:'), { name });
    },
    // Resolved on click: on Vue 3 the button keeps its first click listener until another
    // attribute changes, so a listener closing over `toggleName` would send a stale tone.
    toggleAward(groupName) {
      const awardList = this.groupedAwards.find(({ name }) => name === groupName);

      this.handleAward(awardList ? awardList.toggleName : this.toggleNameFor(groupName));
    },
    handleAward(awardName) {
      if (!this.canAwardEmoji) {
        return;
      }

      this.$emit('award', awardName);

      if (document.activeElement) document.activeElement.blur();
    },
    setIsMenuOpen(menuOpen) {
      this.isMenuOpen = menuOpen;

      if (this.virtualScrollerItem) {
        this.virtualScrollerItem.style.zIndex = this.isMenuOpen ? 1 : null;
      }
    },
  },
  safeHtmlConfig: { ADD_TAGS: ['gl-emoji'] },
};
</script>

<template>
  <div class="awards js-awards-block gl-items-center gl-gap-3">
    <gl-button
      v-for="awardList in groupedAwards"
      :key="awardList.name"
      v-gl-tooltip="{ customClass: 'gl-tooltip gl-whitespace-pre-line' }"
      :class="awardList.classes"
      :title="awardList.title"
      :data-emoji-name="awardList.name"
      data-testid="award-button"
      @click="toggleAward(awardList.name)"
    >
      <template #emoji>
        <span
          v-safe-html:[$options.safeHtmlConfig]="awardList.html"
          class="award-emoji-block"
          data-testid="award-html"
        ></span>
      </template>
      <span class="js-counter">{{ awardList.list.length }}</span>
    </gl-button>
    <div v-if="canAwardEmoji" class="award-menu-holder">
      <emoji-picker
        :right="false"
        :custom-emoji-path="customEmojiPath"
        data-testid="emoji-picker"
        @click="handleAward"
        @shown="setIsMenuOpen(true)"
        @hidden="setIsMenuOpen(false)"
      />
    </div>
  </div>
</template>
