FactoryBot.define do
  factory :user do
    organization
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    role { 'member' }

    trait :admin do
      role { 'admin' }
    end

    trait :viewer do
      role { 'viewer' }
    end
  end
end