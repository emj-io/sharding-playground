FactoryBot.define do
  factory :task do
    project
    organization { project.organization }
    assigned_user { build(:user, organization: organization) }
    sequence(:title) { |n| "Task #{n}" }
    description { "Test task description" }
    status { 'todo' }
    priority { 'medium' }
    due_date { 1.week.from_now }

    trait :high_priority do
      priority { 'high' }
    end

    trait :in_progress do
      status { 'in_progress' }
    end

    trait :done do
      status { 'done' }
    end

    trait :overdue do
      due_date { 1.week.ago }
    end

    trait :unassigned do
      assigned_user { nil }
    end
  end
end