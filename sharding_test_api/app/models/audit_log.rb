class AuditLog < ApplicationRecord
  belongs_to :organization
  belongs_to :user, optional: true

  validates :action, presence: true
  validates :resource_type, presence: true
  validates :resource_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :by_action, ->(action) { where(action: action) }


  def self.log_action(organization:, user: nil, action:, resource:, metadata: {})
    create!(
      organization: organization,
      user: user,
      action: action,
      resource_type: resource.class.name,
      resource_id: resource.id,
      metadata: metadata
    )
  end

  def resource
    resource_type.constantize.find(resource_id)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end