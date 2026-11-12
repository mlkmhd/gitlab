import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import AccessorUtilities from '~/lib/utils/accessor';

describe('AccessorUtilities', () => {
  useLocalStorageSpy();

  const testError = new Error('test error');

  describe('canUseLocalStorage', () => {
    it('should return `true` if access is safe', () => {
      expect(AccessorUtilities.canUseLocalStorage()).toBe(true);
    });

    it('should return `false` if access to .setItem isnt safe', () => {
      window.localStorage.setItem.mockImplementation(() => {
        throw testError;
      });

      expect(AccessorUtilities.canUseLocalStorage()).toBe(false);
    });

    it('should set a test item if access is safe', () => {
      AccessorUtilities.canUseLocalStorage();

      expect(window.localStorage.setItem).toHaveBeenCalledWith('canUseLocalStorage', 'true');
    });

    it('should remove the test item if access is safe', () => {
      AccessorUtilities.canUseLocalStorage();

      expect(window.localStorage.removeItem).toHaveBeenCalledWith('canUseLocalStorage');
    });
  });

  describe('canUseSessionStorage', () => {
    it('returns `true` if access is safe', () => {
      expect(AccessorUtilities.canUseSessionStorage()).toBe(true);
    });

    it('returns `false` if accessing window.sessionStorage throws', () => {
      jest.spyOn(window, 'sessionStorage', 'get').mockImplementation(() => {
        throw new DOMException('Access is denied for this document.', 'SecurityError');
      });

      expect(AccessorUtilities.canUseSessionStorage()).toBe(false);
    });

    it('returns `false` if sessionStorage.setItem throws', () => {
      jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
        throw testError;
      });

      expect(AccessorUtilities.canUseSessionStorage()).toBe(false);
    });

    it('does not leave the test item behind', () => {
      AccessorUtilities.canUseSessionStorage();

      expect(window.sessionStorage.getItem('canUseSessionStorage')).toBeNull();
    });
  });
});
