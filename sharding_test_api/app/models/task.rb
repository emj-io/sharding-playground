class Task < ApplicationRecord
  belongs_to :project
  belongs_to :organization
  belongs_to :assigned_user, class_name: 'User', optional: true

  validates :title, presence: true
  validates :status, presence: true, inclusion: { in: %w[todo in_progress done] }
  validates :priority, presence: true, inclusion: { in: %w[low medium high] }

  scope :todo, -> { where(status: 'todo') }
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :done, -> { where(status: 'done') }
  scope :high_priority, -> { where(priority: 'high') }
  scope :due_today, -> { where(due_date: Date.current) }
  scope :overdue, -> { where('due_date < ?', Date.current) }

  def completed?
    status == 'done'
  end

  def overdue?
    due_date && due_date < Date.current && !completed?
  end

  def assigned?
    assigned_user.present?
  end
end