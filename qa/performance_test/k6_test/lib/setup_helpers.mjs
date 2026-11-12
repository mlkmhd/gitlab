// .mjs, not .js: CPT runs every *.js under k6_test as a test
import http from 'k6/http';
import exec from 'k6/execution';

export const API_VERSION = 'v4';

export function setupContext() {
  const baseUrl = __ENV.GITLAB_URL || `http://gitlab.${__ENV.AI_GATEWAY_IP}.nip.io`;
  const token = __ENV.CAPRONI_ADMIN_ACCESS_TOKEN || '';

  if (!token) {
    exec.test.abort('CAPRONI_ADMIN_ACCESS_TOKEN is empty');
  }

  const params = {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  };

  return { baseUrl, params };
}

function findByName(ctx, kind, name) {
  const label = kind.charAt(0).toUpperCase() + kind.slice(1);
  const searchUrl = `${ctx.baseUrl}/api/${API_VERSION}/${kind}s?search=${encodeURIComponent(name)}`;
  const res = http.get(searchUrl, ctx.params);

  if (res.status !== 200) {
    exec.test.abort(`Failed to search for ${kind}s: ${res.status}`);
  }
  const target = JSON.parse(res.body).find((item) => item.name === name);
  if (!target) {
    exec.test.abort(`${label} '${name}' not found in search results`);
  }
  console.log(`Found ${kind} '${name}' with ID: ${target.id}`);
  return target.id;
}

export function findProject(ctx, name = 'Test Seed Project') {
  return findByName(ctx, 'project', name);
}

export function findGroup(ctx, name = 'Test Seed Group') {
  return findByName(ctx, 'group', name);
}

export function findMrIid(ctx, projectId) {
  const mrListRes = http.get(
    `${ctx.baseUrl}/api/${API_VERSION}/projects/${projectId}/merge_requests`,
    ctx.params,
  );
  if (mrListRes.status !== 200) {
    exec.test.abort(`Failed to list merge requests: ${mrListRes.status}`);
  }
  const mergeRequests = JSON.parse(mrListRes.body);
  if (mergeRequests.length === 0) {
    exec.test.abort(`No merge requests found in project ${projectId}`);
  }
  const mrIid = mergeRequests[0].iid;
  console.log(`Found merge request with IID: ${mrIid}`);
  return mrIid;
}
