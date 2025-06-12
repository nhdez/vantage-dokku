class Admin::ActivityLogsController < ApplicationController
  include ActivityTrackable
  
  before_action :ensure_admin
  before_action :set_activity_log, only: [:show]

  def index
    @activity_logs = ActivityLog.includes(:user).recent
    
    # Filter by action if specified
    if params[:action_filter].present? && ActivityLog::ACTIONS.values.include?(params[:action_filter])
      @activity_logs = @activity_logs.by_action(params[:action_filter])
    end
    
    # Filter by user if specified
    if params[:user_id].present?
      @activity_logs = @activity_logs.by_user(params[:user_id])
    end
    
    # Date range filters
    case params[:date_filter]
    when 'today'
      @activity_logs = @activity_logs.today
    when 'week'
      @activity_logs = @activity_logs.this_week
    when 'custom'
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date]).beginning_of_day rescue nil
        end_date = Date.parse(params[:end_date]).end_of_day rescue nil
        @activity_logs = @activity_logs.where(occurred_at: start_date..end_date) if start_date && end_date
      end
    end
    
    @pagy, @activity_logs = pagy(@activity_logs, items: 25)
    
    # Stats for the sidebar
    @total_activities = ActivityLog.count
    @today_activities = ActivityLog.today.count
    @week_activities = ActivityLog.this_week.count
    @top_actions = ActivityLog.group(:action).count.sort_by { |k, v| -v }.first(5)
    @active_users = ActivityLog.joins(:user).where('occurred_at > ?', 7.days.ago).distinct.count(:user_id)
    
    log_admin_access(current_user, 'activity logs')
  end

  def show
    log_admin_access(current_user, "activity log ##{@activity_log.id}")
  end

  private

  def ensure_admin
    redirect_to root_path, alert: "Access denied" unless current_user&.admin?
  end

  def set_activity_log
    @activity_log = ActivityLog.find(params[:id])
  end
end
