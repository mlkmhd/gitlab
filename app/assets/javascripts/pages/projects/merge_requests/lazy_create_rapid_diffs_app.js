export async function lazyCreateRapidDiffsApp() {
  const { createMergeRequestRapidDiffsApp } =
    await import('ee_else_ce/rapid_diffs/merge_request_app');
  return createMergeRequestRapidDiffsApp();
}
