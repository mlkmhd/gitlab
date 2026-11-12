/* Setup for unit test environment */
import 'helpers/shared_test_setup';
import { forgetConsoleCalls, getConsoleCalls, throwErrorFromCalls } from 'helpers/console_watcher';

process.env.PDF_JS_WORKER_PUBLIC_PATH = 'mock/path/v4/pdf.worker.js';
process.env.PDF_JS_CMAPS_PUBLIC_PATH = '/assets/webpack/pdfjs/v4/cmaps/';

afterEach(() => {
  jest.clearAllTimers();
});

afterEach(() => {
  const consoleCalls = getConsoleCalls();
  forgetConsoleCalls();

  if (consoleCalls.length) {
    throwErrorFromCalls(consoleCalls);
  }
});
