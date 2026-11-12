import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { getBlobControls } from 'ee_jest/integration/repository/fixture_variants';
import {
  mountBlobHeaderArea,
  mountHeaderArea,
  findEditDropdownToggle,
  findEnabledEditDropdownToggle,
  findSingleFileEditorItem,
  findWebIdeEditItem,
  findBlobOverflowMenuToggle,
  findPermalinkItem,
  findReplaceItem,
  findDeleteItem,
  DEFAULT_BRANCH,
} from './test_setup';

describe('Blob controls in an archived project', () => {
  beforeEach(async () => {
    setQueryVariant(getBlobControls).archived();
    await mountBlobHeaderArea();
  });

  it('disables Edit and offers no Replace or Delete', async () => {
    // The toggle is also disabled while blob controls load, so first wait for
    // the overflow menu, which only renders once they have loaded. GlButton
    // disables via aria-disabled to stay focusable.
    await waitForElement(findBlobOverflowMenuToggle);
    await waitForAssertion(() => {
      expect(findEditDropdownToggle().getAttribute('aria-disabled')).toBe('true');
    });

    await waitAndClick(findBlobOverflowMenuToggle);

    // The permalink item proves the menu content rendered, so absence is meaningful.
    await waitForElement(findPermalinkItem);
    expect(findReplaceItem()).toBe(null);
    expect(findDeleteItem()).toBe(null);
  });
});

describe('Blob controls for a binary file', () => {
  beforeEach(async () => {
    await mountHeaderArea({ route: `/-/blob/${DEFAULT_BRANCH}/files/images/logo-black.png` });
  });

  it('offers the Web IDE but not the single file editor', async () => {
    await waitAndClick(findEnabledEditDropdownToggle);

    await waitForElement(findWebIdeEditItem);
    expect(findSingleFileEditorItem()).toBe(null);
  });
});
