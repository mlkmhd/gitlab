export { memberName, groupErrorsByMessage } from '~/invite_members/utils/member_utils';

export function baseBindingAttributes(hasInvalidMembers) {
  return { 'has-error-during-invite': hasInvalidMembers };
}
