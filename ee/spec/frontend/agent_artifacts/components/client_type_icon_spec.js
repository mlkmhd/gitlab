import { GlAvatar, GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ClientTypeIcon from 'ee/agent_artifacts/components/client_type_icon.vue';

describe('ClientTypeIcon', () => {
  let wrapper;

  const createComponent = (clientType, logo, logoClass) => {
    wrapper = shallowMountExtended(ClientTypeIcon, {
      propsData: { clientType, logo, logoClass },
    });
  };

  describe('when the client type has a sprite icon', () => {
    beforeEach(() => {
      createComponent({ name: 'GitLab Duo', icon: 'tanuki-ai' });
    });

    it('renders the sprite icon', () => {
      const icon = wrapper.findComponent(GlIcon);

      expect(icon.exists()).toBe(true);
      expect(icon.props('name')).toBe('tanuki-ai');
    });

    it('does not render an avatar', () => {
      expect(wrapper.findComponent(GlAvatar).exists()).toBe(false);
    });
  });

  describe('when the client type has no sprite icon', () => {
    beforeEach(() => {
      createComponent({ name: 'Claude Code' });
    });

    it('renders an initial avatar for the agent name', () => {
      const avatar = wrapper.findComponent(GlAvatar);

      expect(avatar.exists()).toBe(true);
      expect(avatar.props('entityName')).toBe('Claude Code');
    });

    it('does not render an icon', () => {
      expect(wrapper.findComponent(GlIcon).exists()).toBe(false);
    });
  });

  describe('when a logo is given', () => {
    beforeEach(() => {
      createComponent({ name: 'Cursor', icon: 'connected' }, 'file-mock-cursor.svg');
    });

    it('renders the logo as a decorative 16px image', () => {
      const img = wrapper.findByTestId('client-type-logo');

      expect(img.element.src).toBe('file-mock-cursor.svg');
      expect(img.attributes()).toMatchObject({ alt: '', width: '16', height: '16' });
    });

    it('does not render an icon or an avatar', () => {
      expect(wrapper.findComponent(GlIcon).exists()).toBe(false);
      expect(wrapper.findComponent(GlAvatar).exists()).toBe(false);
    });
  });

  it('applies the logo class to the logo', () => {
    createComponent({ name: 'Codex' }, 'file-mock-codex.svg', 'gl-scale-150');

    expect(wrapper.findByTestId('client-type-logo').classes()).toContain('gl-scale-150');
  });
});
