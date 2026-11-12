import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import { __, s__ } from '~/locale';

export const initPgAshIntervalConfirm = () => {
  const input = document.querySelector('.js-pg-ash-sample-interval');
  const form = input?.form;

  if (!form) return;

  form.addEventListener('submit', async (event) => {
    if (parseInt(input.value, 10) === parseInt(input.defaultValue, 10)) return;

    event.preventDefault();

    const confirmed = await confirmAction(
      [
        s__(
          'AdminSettings|Changing the sample interval deletes all collected active session history.',
        ),
        __('This action cannot be undone.'),
      ].join(' '),
      {
        title: s__('AdminSettings|Change the sample interval?'),
        primaryBtnText: s__('AdminSettings|Change interval'),
        primaryBtnVariant: 'danger',
      },
    );

    // HTMLFormElement#submit fires no submit event, so this does not ask again.
    if (confirmed) form.submit();
  });
};
