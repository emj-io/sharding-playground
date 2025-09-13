FactoryBot.define do
  factory :organization do
    sequence(:id) { |n| n }
    sequence(:name) { |n| "Organization #{n}" }
    plan_type { %w[free pro enterprise].sample }

    trait :free_plan do
      plan_type { 'free' }
    end

    trait :pro_plan do
      plan_type { 'pro' }
    end

    trait :enterprise_plan do
      plan_type { 'enterprise' }
    end
  end
end