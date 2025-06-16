class DeploymentAttempt < ApplicationRecord
  belongs_to :deployment
  
  validates :status, presence: true, inclusion: { in: %w[pending running success failed] }
  validates :attempt_number, presence: true, uniqueness: { scope: :deployment_id }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }
  scope :completed, -> { where(status: %w[success failed]) }
  
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
  
  def duration_text
    return 'Not completed' unless completed_at
    return 'Not started' unless started_at
    
    duration_seconds = duration.to_i
    if duration_seconds < 60
      "#{duration_seconds}s"
    else
      minutes = duration_seconds / 60
      seconds = duration_seconds % 60
      "#{minutes}m #{seconds}s"
    end
  end
  
  def status_badge_class
    case status
    when 'success'
      'bg-success'
    when 'failed'
      'bg-danger'
    when 'running'
      'bg-warning text-dark'
    else
      'bg-secondary'
    end
  end
  
  def status_icon
    case status
    when 'success'
      'fas fa-check-circle'
    when 'failed'
      'fas fa-times-circle'
    when 'running'
      'fas fa-spinner fa-spin'
    else
      'fas fa-clock'
    end
  end
  
  def success?
    status == 'success'
  end
  
  def failed?
    status == 'failed'
  end
  
  def running?
    status == 'running'
  end
  
  def completed?
    %w[success failed].include?(status)
  end
end
