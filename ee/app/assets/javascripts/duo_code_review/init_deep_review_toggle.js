export const initDeepReviewToggle = () => {
  const allowedCheckbox = document.querySelector('.js-duo-code-review-deep-allowed');
  const standardOption = document.querySelector('.js-duo-code-review-standard-depth');
  const deepOption = document.querySelector('.js-duo-code-review-deep-depth');

  if (!allowedCheckbox || !standardOption || !deepOption) {
    return;
  }

  // Disabled radios are not submitted, so saving keeps the stored depth instead of
  // overwriting it. The server resets Deep to Standard when deep reviews are turned off.
  const update = () => {
    const disabled = !allowedCheckbox.checked;

    standardOption.disabled = disabled;
    deepOption.disabled = disabled;
  };

  update();
  allowedCheckbox.addEventListener('change', update);
};
