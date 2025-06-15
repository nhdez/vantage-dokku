class ApplicationHealth < ApplicationRecord
  belongs_to :deployment
  
  validates :status, presence: true, inclusion: { in: %w[healthy unhealthy timeout error] }
  validates :checked_at, presence: true
  
  scope :recent, -> { order(checked_at: :desc) }
  scope :healthy, -> { where(status: 'healthy') }
  scope :unhealthy, -> { where(status: ['unhealthy', 'timeout', 'error']) }
  scope :last_20, -> { recent.limit(20) }
  
  def healthy?
    status == 'healthy'
  end
  
  def unhealthy?
    !healthy?
  end
  
  def status_color
    case status
    when 'healthy'
      'success'
    when 'unhealthy'
      'danger'
    when 'timeout'
      'warning'
    when 'error'
      'danger'
    else
      'secondary'
    end
  end
  
  def status_icon
    case status
    when 'healthy'
      'fas fa-check-circle'
    when 'unhealthy'
      'fas fa-times-circle'
    when 'timeout'
      'fas fa-clock'
    when 'error'
      'fas fa-exclamation-triangle'
    else
      'fas fa-question-circle'
    end
  end
end
