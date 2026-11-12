# frozen_string_literal: true

RSpec.shared_examples 'when user bulk assigns parent' do
  it 'assigns parent to single work item' do
    check_work_items([child_work_item.title])
    select_parent_on_bulk_edit(parent_work_item.title)
    click_update_selected

    find_work_item_element(child_work_item.id).click
    expect(page).to have_testid('detail-wrapper')
    within_testid('work-item-parent') do
      expect(page).to have_content parent_work_item.title
    end
  end

  it 'assigns parent to multiple work items' do
    check_work_items([child_work_item.title, child_work_item_2.title])
    select_parent_on_bulk_edit(parent_work_item.title)
    click_update_selected

    find_work_item_element(child_work_item.id).click
    expect(page).to have_testid('detail-wrapper')
    within_testid('work-item-parent') do
      expect(page).to have_content parent_work_item.title
    end

    close_drawer

    find_work_item_element(child_work_item_2.id).click
    expect(page).to have_testid('detail-wrapper')
    within_testid('work-item-parent') do
      expect(page).to have_content parent_work_item.title
    end
  end
end

RSpec.shared_examples 'when user bulk unassigns parent' do
  it 'removes parent from single work item' do
    check_work_items([child_work_item.title])
    select_no_parent_on_bulk_edit
    click_update_selected

    expect(find_work_item_element(child_work_item.id)).to have_no_testid('work-item-parent-metadata-link')

    find_work_item_element(child_work_item.id).click
    expect(page).to have_testid('detail-wrapper')
    within_testid('work-item-parent') do
      expect(page).not_to have_content parent_work_item.title
    end
  end

  it 'removes parent from multiple work items' do
    check_work_items([child_work_item.title, child_work_item_2.title])
    select_no_parent_on_bulk_edit
    click_update_selected

    expect(find_work_item_element(child_work_item.id)).to have_no_testid('work-item-parent-metadata-link')
    expect(find_work_item_element(child_work_item_2.id)).to have_no_testid('work-item-parent-metadata-link')

    find_work_item_element(child_work_item.id).click
    expect(page).to have_testid('detail-wrapper')
    within_testid('work-item-parent') do
      expect(page).not_to have_content parent_work_item.title
    end

    close_drawer

    find_work_item_element(child_work_item_2.id).click
    expect(page).to have_testid('detail-wrapper')
    within_testid('work-item-parent') do
      expect(page).not_to have_content parent_work_item.title
    end
  end
end

RSpec.shared_examples 'when parent bulk edit shows no available items' do
  it 'shows no available items message for incompatible work item types' do
    check_work_items([incompatible_work_item.title])
    click_parent_bulk_edit_dropdown

    expect(page).to have_content 'No available parent for all selected items.'
  end

  it 'shows no available items message for mixed incompatible work item types' do
    check_work_items([incompatible_work_item_1.title, incompatible_work_item_2.title])
    click_parent_bulk_edit_dropdown

    expect(page).to have_content 'No available parent for all selected items.'
  end
end

RSpec.shared_examples 'when parent bulk edit fetches correct work items' do
  it 'searches across groups when issue is selected' do
    check_work_items([child_work_item.title])
    click_parent_bulk_edit_dropdown

    within_testid('bulk-edit-parent') do
      expect(page).to have_content parent_work_item.title
    end
  end

  it 'searches parent by title' do
    check_work_items([child_work_item.title])
    search_parent_on_bulk_edit(parent_work_item.title)

    within_testid('bulk-edit-parent') do
      expect(page).to have_content parent_work_item.title
    end
  end

  it 'searches parent by reference' do
    check_work_items([child_work_item.title])
    search_parent_on_bulk_edit("##{parent_work_item.iid}")

    within_testid('bulk-edit-parent') do
      expect(page).to have_content parent_work_item.title
    end
  end
end

RSpec.shared_examples 'when user selects multiple types' do
  it 'shows intersection of available parents for mixed compatible types' do
    check_work_items([compatible_work_item_type_1.title, compatible_work_item_type_2.title])
    click_parent_bulk_edit_dropdown

    within_testid('bulk-edit-parent') do
      expect(page).to have_content shared_parent_work_item.title
    end
  end

  it 'shows no available parents for mixed incompatible types' do
    check_work_items([incompatible_work_item_type_1.title, incompatible_work_item_type_2.title])
    click_parent_bulk_edit_dropdown

    within_testid('bulk-edit-parent') do
      expect(page).to have_content 'No available parent for all selected items.'
    end
  end
end
