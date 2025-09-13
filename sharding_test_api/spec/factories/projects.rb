FactoryBot.define do
  factory :project do
    organization
    sequence(:name) { |n| "Project #{n}" }
    description { "Test project description" }
    status { 'active' }

    trait :archived do
      status { 'archived' }
    end

    trait :completed do
      status { 'completed' }
    end
  end
end