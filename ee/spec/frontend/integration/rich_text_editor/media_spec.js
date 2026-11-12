import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  findButtonByLabel,
  getText,
  screen,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import uploadFileVariants from 'ee_jest/integration/rich_text_editor/fixture_variants/upload_file';
import {
  attachFile,
  findContentEditor,
  switchToRichText,
  useWorkItemCreateHost,
  waitForFocus,
} from 'ee_jest/integration/rich_text_editor/test_setup';

Vue.use(VueApollo);

describe('Rich text editor - media', () => {
  useWorkItemCreateHost();

  const findMediaBubbleMenu = () => screen.queryByTestId('media-bubble-menu');

  beforeEach(async () => {
    await switchToRichText();
    await waitForFocus(findContentEditor);
  });

  describe.each`
    media         | editLabel                   | useVariant                                                 | file
    ${'an image'} | ${'Edit image description'} | ${() => setQueryVariant(uploadFileVariants).bigImage()}    | ${new File([''], 'big-image.png', { type: 'image/png' })}
    ${'a video'}  | ${'Edit video description'} | ${() => setQueryVariant(uploadFileVariants).videoSample()} | ${new File([''], 'video_sample.mp4', { type: 'video/mp4' })}
  `('when $media is uploaded', ({ editLabel, useVariant, file }) => {
    beforeEach(() => {
      useVariant();
      attachFile(file);
    });

    it('shows the media bubble menu for the uploaded file', async () => {
      await waitForAssertion(() => {
        expect(getText(findMediaBubbleMenu())).toContain(
          `/uploads/0123456789abcdef0123456789abcdef/${file.name}`,
        );
      });

      expect(findButtonByLabel(editLabel, findMediaBubbleMenu())).not.toBeNull();
    });
  });
});
