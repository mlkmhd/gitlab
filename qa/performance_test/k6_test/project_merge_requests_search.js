import http from 'k6/http';
import { check, sleep } from 'k6';
import { API_VERSION, findProject, setupContext } from './lib/setup_helpers.mjs';

export const TTFB_THRESHOLD = 25;
export const RPS_THRESHOLD = 2;
export const TEST_NAME = 'project_merge_requests_search';
export const LOAD_TEST_VUS = 2;
export const LOAD_TEST_DURATION = '50s';
export const WARMUP_TEST_VUS = 1;
export const WARMUP_TEST_DURATION = '10s';

const SEARCH_TERM = 'test seed';

let API_URL;

export function setup() {
  const ctx = setupContext();
  const projectId = findProject(ctx);
  const apiUrl = `${API_VERSION}/projects/${projectId}/merge_requests?search=${encodeURIComponent(SEARCH_TERM)}`;
  return { apiUrl };
}

export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-vus',
      vus: WARMUP_TEST_VUS,
      duration: WARMUP_TEST_DURATION,
      gracefulStop: '0s',
      tags: { scenario: 'warmup' }, // Tag these requests to filter them out
    },
    load_test: {
      executor: 'constant-vus',
      vus: LOAD_TEST_VUS,
      duration: LOAD_TEST_DURATION,
      startTime: '10s', // Start after warmup completes
      tags: { scenario: 'load_test' },
    },
  },
  thresholds: {
    // Real thresholds that won't fail the test
    'http_req_waiting{scenario:load_test}': [
      { threshold: `p(90)<${TTFB_THRESHOLD}`, abortOnFail: false },
    ],
    'http_reqs{scenario:load_test}': [{ threshold: `rate>=${RPS_THRESHOLD}`, abortOnFail: false }],
  },
};

export default function projectMergeRequestsSearchTest(data) {
  const baseUrl = __ENV.GITLAB_URL || `http://gitlab.${__ENV.AI_GATEWAY_IP}.nip.io`;
  const token = __ENV.CAPRONI_ADMIN_ACCESS_TOKEN || '';

  API_URL = data.apiUrl;

  const url = `${baseUrl}/api/${API_URL}`;

  const params = {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  };

  const res = http.get(url, params);

  let parsedResponse = null;
  try {
    parsedResponse = JSON.parse(res.body);
  } catch (e) {
    parsedResponse = null;
  }

  check(res, {
    'status is 200': () => res.status === 200,
    'response is array': () => Array.isArray(parsedResponse),
  });

  try {
    console.log(
      `Request ${__ITER}: ${res.request.method} ${res.request.url} - Status ${res.status} - Duration ${res.timings.duration}ms - Results ${
        Array.isArray(parsedResponse) ? parsedResponse.length : 'n/a'
      }`,
    );
  } catch (e) {
    console.log(
      `Request ${__ITER}: ${res.request.method} ${res.request.url} - Status ${res.status} - Duration ${res.timings.duration}ms - Parse Error`,
    );
  }

  sleep(1);
}
