class Project < ApplicationRecord
  belongs_to :organization
  has_many :tasks, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: %w[active archived completed] }
  validates :name, uniqueness: { scope: :organization_id }

  scope :active, -> { where(status: 'active') }
  scope :archived, -> { where(status: 'archived') }
  scope :completed, -> { where(status: 'completed') }

  def task_count
    tasks.count
  end

  def completed_task_count
    tasks.where(status: 'done').count
  end

  def pending_task_count
    tasks.where(status: ['todo', 'in_progress']).count
  end

  def progress_percentage
    return 0 if task_count.zero?
    (completed_task_count.to_f / task_count * 100).round(2)
  end
end