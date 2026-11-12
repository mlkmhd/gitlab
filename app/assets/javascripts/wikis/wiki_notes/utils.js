import { COMMENT_FORM } from '~/notes/i18n';
import { parseGid, isGid } from '~/graphql_shared/utils';

export const createNoteErrorMessages = (err) => {
  // TODO: make error message more specific
  if (err?.graphQLErrors?.length || err?.clientErrors) {
    return [COMMENT_FORM.GENERIC_UNSUBMITTABLE];
  }

  return [COMMENT_FORM.GENERIC_UNSUBMITTABLE_NETWORK];
};

export const getIdFromGid = (val) => (isGid(val) ? parseGid(val).id : val);

export const getAutosaveKey = (noteableType, noteId) => `Note/${noteableType}/${noteId}`;
