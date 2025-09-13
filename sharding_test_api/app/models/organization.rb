class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tasks, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :plan_type, presence: true, inclusion: { in: %w[free pro enterprise] }

  scope :by_plan, ->(plan) { where(plan_type: plan) }

  def shard_key
    id
  end

  def user_count
    users.count
  end

  def project_count
    projects.count
  end

  def task_count
    tasks.count
  end
end