# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Timebox::BurnchartBuilder, :aggregate_failures, feature_category: :team_planning do
  let(:start_date) { Date.new(2025, 1, 1) }
  let(:timebox) { build_stubbed(:milestone, start_date: start_date, due_date: start_date + 60.days) }
  let(:other_timebox_id) { timebox.id + 1 }

  let(:add) { ResourceTimeboxEvent.actions[:add] }
  let(:remove) { ResourceTimeboxEvent.actions[:remove] }
  let(:link_add) { WorkItems::ResourceLinkEvent.actions[:add] }
  let(:link_remove) { WorkItems::ResourceLinkEvent.actions[:remove] }
  let(:closed) { ResourceStateEvent.states[:closed] }

  describe '#build' do
    describe 'counting rules' do
      let(:other_timebox) { other_timebox_id }

      def point_for(items)
        events = items.flat_map do |item|
          rows = []
          rows << timebox_event(item[:id], item[:timebox], add, day: 0) if item[:timebox]
          rows << weight_event(item[:id], item[:weight], day: 0) if item[:weight]
          rows << state_event(item[:id], closed, day: 0) if item[:closed]
          rows << link_event(item[:parent], item[:id], link_add, day: 0) if item[:parent]
          rows
        end

        burnchart_points(resource_events(events)).last.except(:date)
      end

      it 'counts open issues in the timebox only' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 1 },
          { id: 2, timebox: timebox.id, weight: 2 },
          { id: 3, weight: 100 },
          { id: 4, timebox: other_timebox, weight: 200 },
          { id: 5, timebox: timebox.id, weight: 0 }
        ])).to eq(scope_count: 3, scope_weight: 3, completed_count: 0, completed_weight: 0)
      end

      it 'counts closed issues as completed' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 1, closed: true },
          { id: 2, timebox: timebox.id, weight: 2, closed: true },
          { id: 3, timebox: timebox.id, weight: 3, closed: true },
          { id: 4, weight: 100 },
          { id: 5, timebox: timebox.id, weight: 0, closed: true }
        ])).to eq(scope_count: 4, scope_weight: 6, completed_count: 4, completed_weight: 6)
      end

      it 'rolls up the weights of tasks in the same timebox and counts other tasks on their own' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 7 },
          { id: 2, timebox: timebox.id, weight: 1, parent: 1 },
          { id: 3, timebox: timebox.id, weight: 10, parent: 1 },
          { id: 4, weight: 100, parent: 1 },
          { id: 5, timebox: other_timebox, weight: 200, parent: 1 },
          { id: 6, timebox: timebox.id, weight: 1000, parent: 7 }
        ])).to eq(scope_count: 2, scope_weight: 1011, completed_count: 0, completed_weight: 0)
      end

      it 'uses the issue weight when its tasks are unweighted' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 1 },
          { id: 2, timebox: timebox.id, weight: 0, parent: 1 }
        ])).to eq(scope_count: 1, scope_weight: 1, completed_count: 0, completed_weight: 0)
      end

      it 'does not complete a closed issue until all its tasks in the timebox are closed' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 7, closed: true },
          { id: 2, timebox: timebox.id, weight: 1, parent: 1, closed: true },
          { id: 3, timebox: timebox.id, weight: 10, parent: 1 },
          { id: 4, timebox: timebox.id, weight: 100, parent: 1 }
        ])).to eq(scope_count: 1, scope_weight: 111, completed_count: 0, completed_weight: 1)
      end

      it 'completes an issue when it and all its tasks are closed' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 7, closed: true },
          { id: 2, timebox: timebox.id, weight: 1, parent: 1, closed: true },
          { id: 3, timebox: timebox.id, weight: 10, parent: 1, closed: true },
          { id: 4, timebox: timebox.id, weight: 100, parent: 1, closed: true }
        ])).to eq(scope_count: 1, scope_weight: 111, completed_count: 1, completed_weight: 111)
      end

      it 'completes a closed top-level task' do
        expect(point_for([
          { id: 1, timebox: timebox.id, weight: 7, closed: true },
          { id: 2, timebox: timebox.id, weight: 1, parent: 1, closed: true },
          { id: 3, timebox: timebox.id, weight: 10, parent: 4, closed: true }
        ])).to eq(scope_count: 2, scope_weight: 11, completed_count: 2, completed_weight: 11)
      end
    end

    it 'updates the parent issue when a task it rolls up changes' do
      events = resource_events([
        timebox_event(1, timebox.id, add, day: 0),
        timebox_event(2, timebox.id, add, day: 0),
        link_event(1, 2, link_add, day: 0),
        weight_event(2, 3, day: 0),
        state_event(2, closed, day: 2)
      ])

      expect(burnchart_points(events)).to eq([
        { date: start_date, scope_count: 1, scope_weight: 3, completed_count: 0, completed_weight: 0 },
        { date: start_date + 2.days, scope_count: 1, scope_weight: 3, completed_count: 0, completed_weight: 3 }
      ])
      expect(burnchart_points(events)).to eq(points_from_full_snapshots(events))
    end

    it 'counts a task on its own when its parent issue leaves the timebox' do
      events = resource_events([
        timebox_event(1, timebox.id, add, day: 0),
        timebox_event(2, timebox.id, add, day: 0),
        link_event(1, 2, link_add, day: 0),
        weight_event(1, 5, day: 0),
        weight_event(2, 2, day: 0),
        timebox_event(1, other_timebox_id, add, day: 3)
      ])

      expect(burnchart_points(events)).to eq([
        { date: start_date, scope_count: 1, scope_weight: 2, completed_count: 0, completed_weight: 0 },
        { date: start_date + 3.days, scope_count: 1, scope_weight: 2, completed_count: 0, completed_weight: 0 }
      ])
      expect(burnchart_points(events)).to eq(points_from_full_snapshots(events))
    end

    it 'stops counting a task on its own when its parent becomes an issue' do
      events = resource_events([
        timebox_event(1, timebox.id, add, day: 0),
        timebox_event(2, timebox.id, add, day: 0),
        timebox_event(3, timebox.id, add, day: 0),
        link_event(1, 2, link_add, day: 0),
        link_event(2, 3, link_add, day: 0),
        weight_event(3, 4, day: 0),
        state_event(3, closed, day: 0),
        link_event(1, 2, link_remove, day: 2)
      ])

      expect(burnchart_points(events)).to eq([
        { date: start_date, scope_count: 2, scope_weight: 4, completed_count: 1, completed_weight: 4 },
        { date: start_date + 2.days, scope_count: 2, scope_weight: 4, completed_count: 0, completed_weight: 4 }
      ])
      expect(burnchart_points(events)).to eq(points_from_full_snapshots(events))
    end

    it 'keeps rolling up a task under its previous parent when it moves without a remove event' do
      events = resource_events([
        timebox_event(1, timebox.id, add, day: 0),
        timebox_event(2, timebox.id, add, day: 0),
        timebox_event(3, timebox.id, add, day: 0),
        link_event(1, 3, link_add, day: 0),
        weight_event(3, 4, day: 1),
        link_event(2, 3, link_add, day: 2),
        state_event(3, closed, day: 3),
        link_event(1, 3, link_remove, day: 4)
      ])

      expect(burnchart_points(events)).to eq([
        { date: start_date, scope_count: 2, scope_weight: 0, completed_count: 0, completed_weight: 0 },
        { date: start_date + 1.day, scope_count: 2, scope_weight: 4, completed_count: 0, completed_weight: 0 },
        { date: start_date + 2.days, scope_count: 2, scope_weight: 8, completed_count: 0, completed_weight: 0 },
        { date: start_date + 3.days, scope_count: 2, scope_weight: 8, completed_count: 0, completed_weight: 8 },
        { date: start_date + 4.days, scope_count: 3, scope_weight: 8, completed_count: 1, completed_weight: 8 }
      ])
      expect(burnchart_points(events)).to eq(points_from_full_snapshots(events))
    end

    it 'matches the points from full snapshots for random event streams' do
      random = Random.new(636_269)

      200.times do
        events = resource_events(random_rows(random))

        expect(burnchart_points(events)).to eq(points_from_full_snapshots(events))
      end
    end

    it 'recomputes all items on the first date and then only the changed task and its parent' do
      events = resource_events(
        (1..50).map { |id| timebox_event(id, timebox.id, add, day: 0) } +
          [link_event(1, 2, link_add, day: 0)] +
          (1..5).map { |day| state_event(2, day.odd? ? closed : ResourceStateEvent.states[:reopened], day: day) }
      )
      builder = described_class.new(timebox, events)

      expect(builder).to receive(:item_contribution).exactly(50 + (5 * 2)).times.and_call_original

      builder.build
    end

    it 'returns no data points when there are no events' do
      expect(burnchart_points(resource_events([]))).to eq([])
    end

    it 'handles every event type in Timebox::EventAggregationService::EVENT_TYPE' do
      events = resource_events(Timebox::EventAggregationService::EVENT_TYPE.values.map do |event_type|
        { event_type: event_type, issue_id: 1, value: 2, action: add, day: 0 }
      end)

      expect { burnchart_points(events) }.not_to raise_error
    end

    it 'raises on an unknown event type' do
      events = resource_events([{ event_type: 'unknown', issue_id: 1, value: 2, action: nil, day: 0 }])

      expect { burnchart_points(events) }
        .to raise_error(described_class::UnsupportedEventTypeError, 'unknown')
    end

    it 'stops at the snapshot limit with the same data points as full snapshots' do
      stub_const('Gitlab::Timebox::SnapshotBuilder::MAX_SNAPSHOTS', 1)

      events = resource_events([
        timebox_event(1, timebox.id, add, day: 0),
        state_event(1, closed, day: 2),
        state_event(1, ResourceStateEvent.states[:reopened], day: 4)
      ])
      builder = described_class.new(timebox, events)

      expect(builder.build).to eq(points_from_full_snapshots(events)).and have_attributes(size: 2)
      expect(builder.limit_exceeded?).to be(true)
    end

    context 'with an iteration' do
      let(:timebox) { build_stubbed(:iteration, start_date: start_date, due_date: start_date + 13.days) }

      it 'matches the points from full snapshots for random event streams' do
        random = Random.new(1)

        50.times do
          events = resource_events(random_rows(random))

          expect(burnchart_points(events)).to eq(points_from_full_snapshots(events))
        end
      end
    end
  end

  def burnchart_points(events)
    described_class.new(timebox, events).build
  end

  def points_from_full_snapshots(events)
    Gitlab::Timebox::SnapshotBuilder.new(timebox, events).build.map do |snapshot|
      items = snapshot.item_states.select { |item| item[:timebox_id] == timebox.id }
      items_by_id = snapshot.item_states.index_by { |item| item[:item_id] }
      issues, tasks = items.partition { |item| item[:parent_id].nil? }
      issue_ids = issues.to_set { |issue| issue[:item_id] }
      top_level_tasks = tasks.reject { |task| issue_ids.include?(task[:parent_id]) }

      issue_points = issues.map { |issue| reference_issue_point(issue, items_by_id) }
      task_points = top_level_tasks.map do |task|
        reference_closed?(task) ? [1, task[:weight], 1, task[:weight]] : [1, task[:weight], 0, 0]
      end

      scope_count, scope_weight, completed_count, completed_weight = (issue_points + task_points).transpose.map(&:sum)
      { date: snapshot.date, scope_count: scope_count.to_i, scope_weight: scope_weight.to_i,
        completed_count: completed_count.to_i, completed_weight: completed_weight.to_i }
    end
  end

  def reference_issue_point(issue, items_by_id)
    tasks = issue[:children_ids].filter_map do |id|
      task = items_by_id[id]
      task if task && task[:timebox_id] == issue[:timebox_id]
    end
    closed_tasks = tasks.select { |task| reference_closed?(task) }
    scope_weight, completed_weight = reference_issue_weights(issue, tasks, closed_tasks)
    completed = reference_closed?(issue) && tasks.all? { |task| reference_closed?(task) }

    [1, scope_weight, completed ? 1 : 0, completed_weight]
  end

  def reference_issue_weights(issue, tasks, closed_tasks)
    unweighted = tasks.empty? || tasks.all? { |task| task[:weight] == 0 }
    scope_weight = unweighted ? issue[:weight] : tasks.sum { |task| task[:weight] }
    closed_weight = closed_tasks.sum { |task| task[:weight] }
    completed_weight = reference_closed?(issue) && unweighted ? issue[:weight] : closed_weight

    [scope_weight, completed_weight]
  end

  def reference_closed?(item)
    item[:end_state] == ResourceStateEvent.states[:closed]
  end

  def timebox_event(item_id, timebox_id, action, day:)
    { event_type: 'timebox', issue_id: item_id, value: timebox_id, action: action, day: day }
  end

  def state_event(item_id, state, day:)
    { event_type: 'state', issue_id: item_id, value: state, action: nil, day: day }
  end

  def weight_event(item_id, weight, day:)
    { event_type: 'weight', issue_id: item_id, value: weight, action: nil, day: day }
  end

  def link_event(parent_id, child_id, action, day:)
    { event_type: 'link', issue_id: parent_id, value: child_id, action: action, day: day }
  end

  def random_rows(random)
    item_count = random.rand(1..20)
    states = ResourceStateEvent.states.values_at(:opened, :closed, :reopened)

    Array.new(random.rand(0..60)) do
      item_id = random.rand(1..item_count)
      day = random.rand(-3..30)

      case random.rand(4)
      when 0
        timebox_id = [timebox.id, timebox.id, other_timebox_id, other_timebox_id + 1].sample(random: random)
        timebox_event(item_id, timebox_id, random.rand(4) == 0 ? remove : add, day: day)
      when 1 then state_event(item_id, states.sample(random: random), day: day)
      when 2 then weight_event(item_id, random.rand(4) == 0 ? nil : random.rand(0..5), day: day)
      else
        link_event(item_id, random.rand(1..item_count), random.rand(4) == 0 ? link_remove : link_add, day: day)
      end
    end
  end

  def resource_events(rows)
    connection = ApplicationRecord.connection

    if rows.empty?
      return connection.execute(
        "SELECT 1 AS id, 'state' AS event_type, 1 AS issue_id, 1 AS value, NULL::int AS action, " \
          "now() AS created_at WHERE false"
      )
    end

    values = rows.each_with_index.map do |row, index|
      created_at = (start_date + row[:day].days).to_time(:utc) + index.minutes
      [index + 1, row[:event_type], row[:issue_id], row[:value], row[:action], created_at]
        .map { |value| connection.quote(value) }
        .join(', ')
    end

    connection.execute(<<~SQL)
      SELECT id, event_type, issue_id, value::int AS value, action::int AS action, created_at::timestamptz AS created_at
      FROM (VALUES (#{values.join('), (')})) AS events(id, event_type, issue_id, value, action, created_at)
      ORDER BY created_at, id
    SQL
  end
end
