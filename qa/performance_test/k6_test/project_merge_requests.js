import http from 'k6/http';
import { check, sleep } from 'k6';
import { API_VERSION, findProject, setupContext } from './lib/setup_helpers.mjs';

export const TTFB_THRESHOLD = 25;
export const RPS_THRESHOLD = 2;
export const TEST_NAME = 'project_merge_requests';
export const LOAD_TEST_VUS = 2;
export const LOAD_TEST_DURATION = '50s';
export const WARMUP_TEST_VUS = 1;
export const WARMUP_TEST_DURATION = '10s';

let API_URL;

export function setup() {
  const ctx = setupContext();
  const projectId = findProject(ctx);
  const apiUrl = `${API_VERSION}/projects/${projectId}/merge_requests`;
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

export default function projectMergeRequestsTest(data) {
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

  const parsedResponse = JSON.parse(res.body);
  check(res, {
    'status is 200': () => res.status === 200,
    'response is array': () => {
      try {
        return Array.isArray(parsedResponse);
      } catch (e) {
        return false;
      }
    },
    'response has merge requests': () => {
      try {
        return Array.isArray(parsedResponse) && parsedResponse.length > 0;
      } catch (e) {
        return false;
      }
    },
  });

  try {
    if (parsedResponse.length > 0) {
      const mr = parsedResponse[0];
      console.log(
        `Request ${__ITER}: ${res.request.method} ${res.request.url} - MR !${mr.iid}: "${mr.title} - Status ${res.status} - Duration ${res.timings.duration}ms "`,
      );
    } else {
      console.log(
        `Request ${__ITER}: ${res.request.method} ${res.request.url} - Status ${res.status} - Duration ${res.timings.duration}ms - No MRs found`,
      );
    }
  } catch (e) {
    console.log(
      `Request ${__ITER}: ${res.request.method} ${res.request.url} - Status ${res.status} - Duration ${res.timings.duration}ms - Parse Error`,
    );
  }

  sleep(1);
}
