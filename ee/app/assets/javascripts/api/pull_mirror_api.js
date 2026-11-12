import axios from '~/lib/utils/axios_utils';
import { buildApiUrl } from '~/api/api_utils';

const PULL_MIRROR_PATH = '/api/:version/projects/:id/mirror/pull';
const buildPullMirrorUrl = (projectId) =>
  buildApiUrl(PULL_MIRROR_PATH).replace(':id', encodeURIComponent(projectId));

export const syncPullMirror = (projectId, params) =>
  axios.post(buildPullMirrorUrl(projectId), params);
export const deletePullMirror = (projectId) =>
  axios.put(buildPullMirrorUrl(projectId), { enabled: false });
