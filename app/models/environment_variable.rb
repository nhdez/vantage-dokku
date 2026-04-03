class EnvironmentVariable < ApplicationRecord
  belongs_to :deployment

  validates :key, presence: true,
                  format: {
                    with: /\A[A-Z][A-Z0-9_]*\z/,
                    message: "must be uppercase letters, numbers, and underscores only, starting with a letter"
                  },
                  length: { maximum: 100 }
  validates :key, uniqueness: { scope: :deployment_id, message: "already exists for this deployment" }
  validates :value, length: { maximum: 10000 }
  validates :description, length: { maximum: 500 }
  validates :source, inclusion: { in: %w[user system], message: "must be 'user' or 'system'" }

  scope :ordered, -> { order(:key) }
  scope :user_managed, -> { where(source: "user") }
  scope :system_managed, -> { where(source: "system") }

  def system_managed?
    source == "system"
  end

  def user_managed?
    source == "user"
  end

  def display_name
    key
  end

  def masked_value
    return nil if value.blank?
    return value if value.length <= 8

    # Show first 4 and last 2 characters for longer values
    "#{value[0..3]}...#{value[-2..-1]}"
  end

  def sensitive?
    key.downcase.include?("password") ||
    key.downcase.include?("secret") ||
    key.downcase.include?("token") ||
    key.downcase.include?("key")
  end
end
