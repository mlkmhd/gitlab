import {
  buildTemplate,
  findDefaultFlowId,
  findNextActiveStage,
  findUnusedStatus,
  parseFactoryConfiguration,
  skipStage,
  startsOnStatus,
  unskipStage,
  updateReview,
  updateStage,
} from 'ee/ai/duo_agents_platform/pages/software_factory/factory_configuration_yaml';
import { exampleConfiguration } from './mock_data';

const changedLines = (before, after) => {
  const beforeLines = before.split('\n');

  return after
    .split('\n')
    .map((line, index) => ({ before: beforeLines[index], after: line }))
    .filter((pair) => pair.before !== pair.after);
};

describe('factory_configuration_yaml', () => {
  describe('parseFactoryConfiguration', () => {
    describe('with a valid file', () => {
      let result;

      beforeEach(() => {
        result = parseFactoryConfiguration(exampleConfiguration);
      });

      it('has no error', () => {
        expect(result.error).toBe(null);
      });

      it('reads the factory name', () => {
        expect(result.factory).toBe('Project XYZ');
      });

      it('reads all six stages in order', () => {
        expect(result.stages.map(({ name }) => name)).toEqual([
          'triage',
          'plan',
          'build',
          'verify',
          'review',
          'ship',
        ]);
      });

      it('reads a configured stage', () => {
        expect(result.stages[2]).toEqual({
          name: 'build',
          skipped: false,
          status: 'In dev',
          start: 'automated',
          exit: 'automated',
          flow: 414,
          markMergeRequestsReady: true,
        });
      });

      it('reads a stage without settings as manual', () => {
        expect(result.stages[5]).toEqual({
          name: 'ship',
          skipped: false,
          status: 'Done',
          start: 'manual',
          exit: 'manual',
          flow: null,
          markMergeRequestsReady: false,
        });
      });

      it('reads a stage missing from the status block as skipped', () => {
        expect(result.stages[3]).toEqual({ name: 'verify', skipped: true });
      });

      it('reads the review block', () => {
        expect(result.review).toEqual({
          reviewer: '',
          maxFixRuns: 3,
          label: 'software-factory',
        });
      });
    });

    it('reads a stage listed without a status name as enabled, with no status', () => {
      const { stages } = parseFactoryConfiguration('status:\n  plan:\n');

      expect(stages[1]).toMatchObject({ name: 'plan', skipped: false, status: '' });
      expect(stages[0]).toEqual({ name: 'triage', skipped: true });
    });

    it.each([
      ['no status or stages block', 'factory: x\n'],
      ['an empty status block', 'status:\n'],
      ['nothing but comments', '# nothing here yet\n'],
      ['no content at all', null],
    ])('reads a file with %s as all stages skipped', (_, content) => {
      const { error, stages } = parseFactoryConfiguration(content);

      expect(error).toBe(null);
      expect(stages.every(({ skipped }) => skipped)).toBe(true);
    });

    it.each([
      ['invalid YAML', 'stages: [', /Flow sequence/],
      ['a scalar document', 'just text', /must be a mapping/],
      ['a status block that is not a mapping', 'status: Start\n', /`status` key .* mapping/],
      ['a stages block that is not a mapping', 'stages: skipped\n', /`stages` key .* mapping/],
      ['a review block that is not a mapping', 'review: yes\n', /`review` key .* mapping/],
      [
        'a stage holding something other than settings',
        'stages:\n  build: a note\n',
        /`stages.build` key .* mapping/,
      ],
      [
        'a status that is not a name',
        'status:\n  build: 2026\n',
        /`status.build` key .* name of a status/,
      ],
      [
        'a stage that is an alias',
        'defaults: &d\n  start: automated\nstages:\n  build: *d\n',
        /`stages` key .* anchor or alias/,
      ],
      [
        'a stage that an alias points at',
        'stages:\n  build: &d\n    start: automated\n  verify: *d\n',
        /`stages` key .* anchor or alias/,
      ],
      ['an alias whose anchor is missing', 'stages: *missing\n', /Unresolved alias/],
      ['an alias used before its anchor', 'a: *later\nb: &later x\n', /Unresolved alias/],
    ])('returns an error for %s', (_, content, error) => {
      expect(parseFactoryConfiguration(content).error).toMatch(error);
    });

    // Reading the file is how the editor finds out it cannot be read, so a file built to exhaust
    // the parser has to come back as a message rather than as a throw.
    it('returns an error for a file that expands without end', () => {
      const anchors = [
        ['b', 'a'],
        ['c', 'b'],
        ['d', 'c'],
        ['e', 'd'],
        ['f', 'e'],
        ['g', 'f'],
        ['h', 'g'],
      ];
      const content = anchors.reduce(
        (yaml, [name, prev]) =>
          `${yaml}${name}: &${name} [${`*${prev},`.repeat(9).slice(0, -1)}]\n`,
        'a: &a [x,x,x,x,x,x,x,x,x]\n',
      );

      expect(parseFactoryConfiguration(`${content}status:\n  build: *h\n`).error).toMatch(
        /Excessive alias count/,
      );
    });

    it('reads a file whose anchors are all outside the blocks the editor writes', () => {
      const content = 'custom: &d\n  a: 1\nalso: *d\nstatus:\n  build: In dev\n';

      expect(parseFactoryConfiguration(content).error).toBe(null);
    });
  });

  describe('round trip', () => {
    it('keeps the file unchanged when nothing is edited', () => {
      expect(updateStage(exampleConfiguration, 'triage', {})).toBe(exampleConfiguration);
    });

    it('changes only the edited line', () => {
      const result = updateStage(exampleConfiguration, 'plan', { status: 'Breakdown' });

      expect(changedLines(exampleConfiguration, result)).toEqual([
        { before: '  plan: Planning breakdown', after: '  plan: Breakdown' },
      ]);
    });

    it('keeps comments, key order and unknown keys', () => {
      const content = `${exampleConfiguration}custom:\n  key: value # keep me\n`;
      const result = updateStage(content, 'triage', { flow: 999 });

      expect(result).toContain('# Read by the flows of the factory, and by Sync.');
      expect(result).toContain('# Read by the fix loop.');
      expect(result).toContain('custom:\n  key: value # keep me');
      expect(result).toContain('    flow: 999');
      expect(changedLines(content, result)).toEqual([
        { before: '    flow: 412', after: '    flow: 999' },
      ]);
    });

    it.each([
      ['a comment on its own line', '# top\nstatus:\n  # why build is here\n  build: In dev\n'],
      ['an inline comment', 'status:\n  build: In dev # note\n  ship: Done # other\n'],
    ])('keeps %s', (_, content) => {
      expect(updateStage(content, 'triage', {})).toBe(content);
    });

    it('leaves the indentation of the file alone', () => {
      const content = 'status:\n    build: In dev\n    ship: Done\n';

      expect(updateStage(content, 'build', { status: 'Dev' })).toBe(
        'status:\n    build: Dev\n    ship: Done\n',
      );
    });

    it.each([
      ['a block scalar body', 'note: |\n        eight spaces\n'],
      ['an indented comment', 'status:\n      # a note\n'],
    ])('takes the indent from the blocks, not from %s', (_, prefix) => {
      const content = `${prefix}stages:\n  build:\n    start: automated\n`;

      expect(updateStage(content, 'build', { exit: 'manual' })).toContain(
        'stages:\n  build:\n    start: automated\n    exit: manual\n',
      );
    });

    it('keeps the comment on an empty block it fills', () => {
      const content = 'stages: # filled in by the UI\nstatus:\n  build: In dev\n';

      expect(updateStage(content, 'build', { start: 'automated' })).toBe(
        'stages:\n  # filled in by the UI\n  build:\n    start: automated\nstatus:\n  build: In dev\n',
      );
    });

    it('leaves the line endings of the file alone', () => {
      const content = 'status:\r\n  build: In dev\r\n';

      expect(updateStage(content, 'build', { status: 'Dev' })).toBe('status:\r\n  build: Dev\r\n');
    });

    it('does not wrap a long line it did not edit', () => {
      const name = 'A factory name that runs past the eighty characters YAML wraps at by default';
      const content = `factory: ${name}\nstatus:\n  build: In dev\n`;

      expect(updateStage(content, 'build', { status: 'Dev' })).toBe(
        `factory: ${name}\nstatus:\n  build: Dev\n`,
      );
    });

    // Whitespace the parser does not record, so no edit can put it back. All of it reaches lines
    // the edit did not touch, which is why it is pinned rather than left to be discovered.
    // Nothing structural moves: no content, comment text, key or ordering is lost.
    describe('whitespace it cannot keep', () => {
      it('collapses a run of blank lines to one', () => {
        const content = 'factory: x\n\n\nstatus:\n  build: In dev\n\n\nreview:\n  label: l\n';

        expect(updateStage(content, 'build', { status: 'Dev' })).toBe(
          'factory: x\n\nstatus:\n  build: Dev\n\nreview:\n  label: l\n',
        );
      });

      it('collapses the padding that aligns an inline comment', () => {
        const content = 'status:\n  triage: Start      # aligned\n  build: In dev      # aligned\n';

        expect(updateStage(content, 'build', { status: 'Dev' })).toBe(
          'status:\n  triage: Start # aligned\n  build: Dev # aligned\n',
        );
      });

      it('pads a flow collection, keeping it inline', () => {
        const content = 'status: {build: In dev, ship: Done}\nkeep: [a, b]\n';

        expect(updateStage(content, 'build', { status: 'Dev' })).toBe(
          'status: { build: Dev, ship: Done }\nkeep: [ a, b ]\n',
        );
      });

      // The width the file is stringified at stops long lines wrapping, and for the same reason
      // joins one the author wrapped. A plain scalar folds its line break to a space either way.
      it('joins a plain scalar wrapped by hand', () => {
        const content = 'note: a plain scalar\n  wrapped by hand\nstatus:\n  build: In dev\n';

        expect(updateStage(content, 'build', { status: 'Done' })).toBe(
          'note: a plain scalar wrapped by hand\nstatus:\n  build: Done\n',
        );
      });

      it('indents a sequence written in its parent column', () => {
        const content = 'keep:\n- a\n- b\nstatus:\n  build: In dev\n';

        expect(updateStage(content, 'build', { status: 'Done' })).toBe(
          'keep:\n  - a\n  - b\nstatus:\n  build: Done\n',
        );
      });

      // Every block scalar body is written at the indent of the file, so one indented differently
      // moves. Reading the indent from the blocks keeps this to the body itself.
      it('re-indents the body of a block scalar', () => {
        const content = 'note: |\n    four spaces\nstatus:\n  build: In dev\n';

        expect(updateStage(content, 'build', { status: 'Done' })).toBe(
          'note: |\n  four spaces\nstatus:\n  build: Done\n',
        );
      });
    });

    it('writes into an empty status block without reflowing it', () => {
      expect(unskipStage('# keep me\nstatus:\n', 'plan', { status: 'Planning' })).toBe(
        '# keep me\nstatus:\n  plan: Planning\n',
      );
    });

    it('writes into a status block emptied by skipping every stage', () => {
      const emptied = skipStage('status:\n  plan: Planning\n', 'plan');

      expect(unskipStage(emptied, 'build', { status: 'In dev' })).toBe(
        'status:\n  build: In dev\n',
      );
    });
  });

  describe('updateStage', () => {
    it('removes keys set to null', () => {
      const result = updateStage(exampleConfiguration, 'build', {
        exit: 'manual',
        mark_merge_requests_ready: null,
      });

      expect(parseFactoryConfiguration(result).stages[2]).toMatchObject({
        exit: 'manual',
        markMergeRequestsReady: false,
      });
      expect(result).not.toContain('mark_merge_requests_ready');
    });

    it('writes settings for a stage that had none', () => {
      const result = updateStage(exampleConfiguration, 'ship', { start: 'automated' });

      expect(result).toContain('  ship:\n    start: automated\n');
      expect(parseFactoryConfiguration(result).stages[5].start).toBe('automated');
    });

    it('removes the settings of a stage when none are left', () => {
      const result = updateStage(exampleConfiguration, 'review', { start: null, exit: null });

      expect(result).not.toContain('  review:\n    start');
      expect(result).toContain('  review: In review');
    });

    it('keeps the stage in the status block when its status is cleared', () => {
      const result = updateStage(exampleConfiguration, 'ship', { status: '' });

      expect(parseFactoryConfiguration(result).stages[5]).toMatchObject({
        skipped: false,
        status: '',
      });
    });

    it('clears a setting the stage never had', () => {
      expect(updateStage('status:\n  ship: Done\n', 'ship', { flow: null })).toBe(
        'status:\n  ship: Done\n',
      );
    });

    it('throws for content it cannot read', () => {
      expect(() => updateStage('stages: [', 'triage', { status: 'x' })).toThrow();
    });
  });

  describe('skipStage', () => {
    it('removes the status and the settings of the stage', () => {
      const result = skipStage(exampleConfiguration, 'plan');

      expect(result).not.toContain('Planning breakdown');
      expect(result).not.toContain('flow: 413');
      expect(parseFactoryConfiguration(result).stages[1]).toEqual({ name: 'plan', skipped: true });
    });

    it('removes the stages block when the last stage with settings is skipped', () => {
      const result = skipStage('status:\n  plan: P\nstages:\n  plan:\n    flow: 1\n', 'plan');

      expect(result).toBe('status: {}\n');
    });

    it('skips a stage in a file with no stages block', () => {
      expect(skipStage('status:\n  plan: P\n  ship: Done\n', 'plan')).toBe(
        'status:\n  ship: Done\n',
      );
    });
  });

  describe('unskipStage', () => {
    it('adds the stage to the status block, as a manual stage', () => {
      const result = unskipStage(exampleConfiguration, 'verify', { status: 'In test' });

      expect(result).toContain('  verify: In test\n');
      expect(parseFactoryConfiguration(result).stages[3]).toMatchObject({
        skipped: false,
        status: 'In test',
        start: 'manual',
        exit: 'manual',
      });
    });

    it('lists the stage without a status name by default', () => {
      const result = unskipStage(exampleConfiguration, 'verify');

      expect(parseFactoryConfiguration(result).stages[3]).toMatchObject({
        skipped: false,
        status: '',
      });
    });

    it('adds the status block when the file has none', () => {
      expect(unskipStage('factory: x\n', 'triage', { status: 'Start' })).toBe(
        'factory: x\nstatus:\n  triage: Start\n',
      );
    });

    it('writes the settings of the stage, and leaves out blank ones', () => {
      const result = unskipStage(exampleConfiguration, 'verify', {
        status: 'In test',
        settings: { start: 'automated', exit: 'automated', flow: null },
      });

      expect(result).toContain('  verify:\n    start: automated\n    exit: automated\n');
      expect(parseFactoryConfiguration(result).stages[3]).toMatchObject({
        start: 'automated',
        exit: 'automated',
        flow: null,
      });
    });
  });

  describe('updateReview', () => {
    it('sets review values', () => {
      const result = updateReview(exampleConfiguration, {
        max_fix_runs: 5,
        label: 'ai-review',
        reviewer: 'a-reviewer',
      });

      expect(parseFactoryConfiguration(result).review).toEqual({
        reviewer: 'a-reviewer',
        maxFixRuns: 5,
        label: 'ai-review',
      });
    });

    it('removes blank values', () => {
      expect(updateReview(exampleConfiguration, { label: '' })).not.toContain('label:');
    });
  });

  describe('buildTemplate', () => {
    it('has every stage skipped, so a new file starts with nothing to fix', () => {
      const { error, factory, review, stages } = parseFactoryConfiguration(
        buildTemplate('group/project'),
      );

      expect(error).toBe(null);
      expect(factory).toBe('group/project');
      expect(review.maxFixRuns).toBe(3);
      expect(stages).toHaveLength(6);
      expect(stages.every(({ skipped }) => skipped)).toBe(true);
    });

    it('takes a stage without reflowing the file', () => {
      expect(unskipStage(buildTemplate('group/project'), 'triage', { status: 'Start' })).toBe(
        'factory: group/project\nreview:\n  max_fix_runs: 3\nstatus:\n  triage: Start\n',
      );
    });

    // Written through the same stringify as every edit, so a name past the width YAML wraps at
    // is not folded here and then unfolded by the first edit.
    it('does not wrap a long factory name', () => {
      const name =
        'The Software Factory for the Payments Platform and all of its consumer services';
      const template = buildTemplate(name);

      expect(template).toBe(`factory: ${name}\nreview:\n  max_fix_runs: 3\n`);
      expect(unskipStage(template, 'triage', { status: 'Start' })).toContain(`factory: ${name}\n`);
    });
  });

  describe('findDefaultFlowId', () => {
    const flows = [
      { id: 1, name: 'Custom', foundationalFlowReference: null },
      { id: 2, name: 'Developer', foundationalFlowReference: 'developer/v1' },
      { id: 3, name: 'Generate Workplan', foundationalFlowReference: 'workplan/v1' },
    ];

    it.each`
      stage       | expected
      ${'plan'}   | ${3}
      ${'build'}  | ${2}
      ${'review'} | ${2}
      ${'triage'} | ${null}
      ${'ship'}   | ${null}
    `('returns $expected for $stage', ({ stage, expected }) => {
      expect(findDefaultFlowId(flows, stage)).toBe(expected);
    });

    it('returns null when the project has not enabled the default flow', () => {
      expect(findDefaultFlowId([flows[0]], 'build')).toBe(null);
    });
  });

  describe('findNextActiveStage', () => {
    const { stages } = parseFactoryConfiguration(exampleConfiguration);

    it('skips skipped stages', () => {
      expect(findNextActiveStage(stages, 'build').name).toBe('review');
    });

    it('returns null for the last stage', () => {
      expect(findNextActiveStage(stages, 'ship')).toBe(null);
    });

    it('returns null for a stage that is not in the list', () => {
      expect(findNextActiveStage(stages, 'nope')).toBe(null);
    });
  });

  describe('startsOnStatus', () => {
    it.each`
      name        | skipped  | start          | expected
      ${'build'}  | ${false} | ${'automated'} | ${true}
      ${'build'}  | ${false} | ${'manual'}    | ${false}
      ${'build'}  | ${true}  | ${undefined}   | ${false}
      ${'review'} | ${false} | ${'automated'} | ${false}
    `('is $expected for $name, skipped $skipped, start $start', ({ expected, ...stage }) => {
      expect(startsOnStatus(stage)).toBe(expected);
    });
  });

  describe('findUnusedStatus', () => {
    const stages = [
      { name: 'triage', skipped: false, status: 'Start' },
      { name: 'plan', skipped: true },
      { name: 'build', skipped: false, status: 'in dev' },
    ];

    it('returns the first status no other enabled stage uses, ignoring case', () => {
      expect(findUnusedStatus(stages, ['Start', 'In dev', 'Done'], 'plan')).toBe('Done');
    });

    it('counts the stage being enabled as free to reuse its own status', () => {
      expect(findUnusedStatus(stages, ['Start', 'Done'], 'triage')).toBe('Start');
    });

    it('returns an empty string when every status is used', () => {
      expect(findUnusedStatus(stages, ['Start', 'In dev'], 'plan')).toBe('');
    });
  });
});
