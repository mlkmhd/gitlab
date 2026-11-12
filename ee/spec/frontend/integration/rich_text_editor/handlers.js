import { join } from 'node:path';
import { http, HttpResponse } from 'msw';
import { isEqual } from 'lodash-es';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import {
  captureMissingOperation,
  captureRequest,
} from 'ee_jest/integration/core/operation_helpers';
import { server } from '../server';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/rich_text_editor/integration/');

const { previewMarkdown, previewMarkdownPlainText } = loadFixturesMap(FIXTURES_PATH);
const previewFixtures = [previewMarkdown, previewMarkdownPlainText];

export const installRichTextEditorHandlers = () => {
  server.use(
    http.post(/\/-\/preview_markdown(\?|$)/, async ({ request }) => {
      const { text } = await request.json();
      const params = Object.fromEntries(new URL(request.url).searchParams);

      const fixture = previewFixtures.find((candidate) => isEqual(params, candidate.params));

      if (!fixture || !Object.hasOwn(fixture.previews, text)) {
        captureMissingOperation(`previewMarkdown ${JSON.stringify({ params, text })}`);
        return new HttpResponse(null, { status: 400 });
      }

      captureRequest('previewMarkdown', request, { text });
      return HttpResponse.json(fixture.previews[text]);
    }),
  );
};
