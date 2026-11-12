import { __, s__ } from '~/locale';

export const MODAL_TITLE = s__('TagsPage|Delete tag?');

export const MODAL_TITLE_PROTECTED_TAG = s__('TagsPage|Delete protected tag?');

export const MODAL_MESSAGE = s__(
  "TagsPage|You're about to permanently delete the tag %{tagName}. This cannot be undone.",
);

export const MODAL_MESSAGE_PROTECTED_TAG = s__(
  "TagsPage|You're about to permanently delete the protected tag %{tagName}. This cannot be undone.",
);

export const CANCEL_BUTTON_TEXT = __('Cancel');

export const CONFIRMATION_TEXT_PROTECTED_TAG = __('Enter the following to confirm: %{phrase}');

export const DELETE_BUTTON_TEXT = s__('TagsPage|Delete tag');

export const DELETE_BUTTON_TEXT_PROTECTED_TAG = s__('TagsPage|Delete protected tag');

export const I18N_DELETE_TAG_MODAL = {
  modalTitle: MODAL_TITLE,
  modalTitleProtectedTag: MODAL_TITLE_PROTECTED_TAG,
  modalMessage: MODAL_MESSAGE,
  modalMessageProtectedTag: MODAL_MESSAGE_PROTECTED_TAG,
  cancelButtonText: CANCEL_BUTTON_TEXT,
  confirmationTextProtectedTag: CONFIRMATION_TEXT_PROTECTED_TAG,
  deleteButtonText: DELETE_BUTTON_TEXT,
  deleteButtonTextProtectedTag: DELETE_BUTTON_TEXT_PROTECTED_TAG,
};

export const SORT_DIRECTION_ASC = 'asc';
export const SORT_DIRECTION_DESC = 'desc';
export const SORT_OPTION_NAME = 'name';
export const SORT_OPTION_UPDATED = 'updated';
export const SORT_OPTION_VERSION = 'version';
