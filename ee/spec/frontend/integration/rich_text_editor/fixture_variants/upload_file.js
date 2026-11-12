import uploadSamplePdf from 'test_fixtures/rich_text_editor/integration/upload_sample_pdf.json';
import uploadBigImage from 'test_fixtures/rich_text_editor/integration/upload_big_image.json';
import uploadVideoSample from 'test_fixtures/rich_text_editor/integration/upload_video_sample.json';
import { defineRestFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineRestFixtureVariants({
  query: 'uploadFile',
  variants: {
    BASE: uploadSamplePdf,
    BIG_IMAGE: uploadBigImage,
    VIDEO_SAMPLE: uploadVideoSample,
  },
});
