import { createAlert, VARIANT_INFO } from '~/alert';

export function showQuickActionMessages(status) {
  if (!status?.messages?.length) return;

  createAlert({ message: status.messages.join(' '), variant: VARIANT_INFO });
}
