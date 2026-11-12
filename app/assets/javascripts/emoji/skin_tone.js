import { uniq } from 'lodash-es';
import skinTones from 'emojis/skin_tones.json';
import { observable } from '~/lib/utils/observable';

export const DEFAULT_SKIN_TONE = 'default';

// Same order as UserPreference#emoji_skin_tone and as the fixture's variant lists.
const TONES = ['light', 'medium_light', 'medium', 'medium_dark', 'dark'];

export const SKIN_TONES = [DEFAULT_SKIN_TONE, ...TONES];

// `gon` is a plain object, so a computed property that derives emoji names from the tone would
// keep its first result after the tone changes on an open page. Every change bumps this shared
// counter, and reading it inside a computed property or watcher makes it depend on the tone.
const toneChanges = observable('emoji_skin_tone', { count: 0 });

const dependOnTone = () => toneChanges.count;

// Both lookups are built once at load. They are constants, not lazily filled caches, because
// this module imports the observable and so is built once per Vue version on a migrated page,
// and the Vue 3 infection scanner treats module-scope state that a function writes as duplicated.
const baseByVariant = new Map(
  Object.entries(skinTones.variants).flatMap(([base, variants]) =>
    variants.map((variant) => [variant, base]),
  ),
);

// Two-tone pairs and the unmapped names have no plain base to collapse into.
const hiddenInGrid = new Set([...skinTones.mixed, ...skinTones.unmapped]);

/**
 * The user's default skin tone, or `null` when the preference is unavailable:
 * the feature flag is off or the viewer is signed out.
 */
export const userSkinTone = () => {
  dependOnTone();

  return window.gon?.emoji_skin_tone ?? null;
};

/**
 * Sets the user's default skin tone on this page. `gon` keeps the value, and every computed
 * property or watcher that read it through the helpers in this module re-evaluates.
 */
export const setUserSkinTone = (tone) => {
  window.gon.emoji_skin_tone = tone;
  toneChanges.count += 1;
};

export const isSkinTonePreferenceEnabled = () => userSkinTone() !== null;

/**
 * The plain emoji a toned name belongs to. Names without a tone group,
 * including two-tone and unmapped names, return themselves.
 */
export const baseName = (name) => baseByVariant.get(name) ?? name;

export const variantsFor = (base) => skinTones.variants[base] ?? [];

/** The variant of `base` in the given tone; the base itself for the default tone or an emoji without tones. */
export const variantForTone = (base, tone) => variantsFor(base)[TONES.indexOf(tone)] ?? base;

/** The variant of `name`'s emoji in the user's default skin tone. */
export const preferredVariant = (name) => variantForTone(baseName(name), userSkinTone());

/** `name` in the user's default tone when it is a plain emoji with tones; toned and other names stay as given. */
export const withPreferredTone = (name) =>
  variantsFor(name).length ? preferredVariant(name) : name;

/**
 * One tile per emoji for the picker grid, in the user's default tone. Toned variants
 * collapse into their base; two-tone and unmapped names are left to search.
 * Without the preference the names are returned as they are.
 */
export const pickerGridNames = (names) => {
  if (!isSkinTonePreferenceEnabled()) return names;

  return names
    .filter((name) => baseName(name) === name && !hiddenInGrid.has(name))
    .map((name) => preferredVariant(name));
};

/**
 * Every tone of an emoji folded into the user's default tone, keeping the first
 * position of each emoji. Without the preference the names are returned as they are.
 */
export const collapseToPreferredTone = (names) =>
  isSkinTonePreferenceEnabled() ? uniq(names.map((name) => preferredVariant(name))) : names;

/**
 * Whether adding `name` makes the server drop an existing award called `other`:
 * the same emoji in another tone, while the preference is on.
 */
export const isOtherToneOfSameEmoji = (name, other) =>
  isSkinTonePreferenceEnabled() && name !== other && baseName(name) === baseName(other);
