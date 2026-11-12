export const exampleConfiguration = `factory: "Project XYZ"

# Read by the flows of the factory, and by Sync.
status:
  triage: Start
  plan: Planning breakdown
  build: In dev
  review: In review
  ship: Done

stages:
  triage:
    start: automated
    flow: 412
    exit: automated
  plan:
    start: automated
    flow: 413
    exit: automated
  build:
    start: automated
    flow: 414
    exit: automated
    mark_merge_requests_ready: true
  review:
    start: automated
    exit: manual

# Read by the fix loop.
review:
  label: software-factory
  max_fix_runs: 3
`;
