import { createAlert, VARIANT_INFO } from '~/alert';
import { showQuickActionMessages } from '~/rapid_diffs/app/discussions/quick_actions';

jest.mock('~/alert');

describe('showQuickActionMessages', () => {
  it.each([undefined, {}, { messages: [] }])('does not show an alert for %p', (status) => {
    showQuickActionMessages(status);

    expect(createAlert).not.toHaveBeenCalled();
  });

  it('shows a single message as an info alert', () => {
    showQuickActionMessages({ messages: ['Tagged this commit to v1.0.'] });

    expect(createAlert).toHaveBeenCalledWith({
      message: 'Tagged this commit to v1.0.',
      variant: VARIANT_INFO,
    });
  });

  it('joins several messages into one alert', () => {
    showQuickActionMessages({ messages: ['Tagged this commit to v1.0.', 'Added label.'] });

    expect(createAlert).toHaveBeenCalledWith({
      message: 'Tagged this commit to v1.0. Added label.',
      variant: VARIANT_INFO,
    });
  });
});
