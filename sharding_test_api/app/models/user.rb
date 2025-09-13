class User < ApplicationRecord
  belongs_to :organization
  has_many :assigned_tasks, class_name: 'Task', foreign_key: 'assigned_user_id'

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: %w[admin member viewer] }
  validates :email, uniqueness: { scope: :organization_id }

  scope :admins, -> { where(role: 'admin') }
  scope :members, -> { where(role: 'member') }
  scope :viewers, -> { where(role: 'viewer') }

  def admin?
    role == 'admin'
  end

  def member?
    role == 'member'
  end

  def viewer?
    role == 'viewer'
  end
end