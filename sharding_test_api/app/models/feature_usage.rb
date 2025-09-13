class FeatureUsage < ApplicationRecord
  belongs_to :organization

  validates :feature_name, presence: true
  validates :usage_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :date, presence: true
  validates :feature_name, uniqueness: { scope: [:organization_id, :date] }

  scope :for_date, ->(date) { where(date: date) }
  scope :for_feature, ->(feature) { where(feature_name: feature) }
  scope :recent, -> { where('date >= ?', 30.days.ago) }


  def self.increment_usage(organization:, feature_name:, date: Date.current)
    find_or_initialize_by(
      organization: organization,
      feature_name: feature_name,
      date: date
    ).tap do |usage|
      usage.usage_count = (usage.usage_count || 0) + 1
      usage.save!
    end
  end

  def self.usage_summary(organization: nil, start_date: 30.days.ago, end_date: Date.current)
    scope = where(date: start_date..end_date)
    scope = scope.where(organization: organization) if organization

    scope.group(:feature_name).sum(:usage_count)
  end
end