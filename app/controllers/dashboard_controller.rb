class DashboardController < ApplicationController
  def index
    @recent_projects = mock_recent_projects
    @analytics_data = mock_analytics_data
    @notifications = mock_notifications
  end

  def projects
    @projects = mock_projects_list
  end

  def analytics
    @analytics = mock_detailed_analytics
  end

  def settings
    # Settings will be handled by Devise user registration controller
    redirect_to edit_user_registration_path
  end

  private

  def mock_recent_projects
    [
      { name: "E-commerce Platform", status: "Active", progress: 85, updated: "2 hours ago" },
      { name: "Mobile App Backend", status: "In Progress", progress: 60, updated: "1 day ago" },
      { name: "Analytics Dashboard", status: "Review", progress: 95, updated: "3 days ago" }
    ]
  end

  def mock_projects_list
    [
      { name: "E-commerce Platform", description: "Full-stack web application", team_size: 4, deadline: "Dec 15, 2024" },
      { name: "Mobile App Backend", description: "REST API for mobile application", team_size: 2, deadline: "Jan 30, 2025" },
      { name: "Analytics Dashboard", description: "Real-time data visualization", team_size: 3, deadline: "Nov 20, 2024" },
      { name: "Customer Portal", description: "Self-service customer platform", team_size: 5, deadline: "Feb 14, 2025" }
    ]
  end

  def mock_analytics_data
    {
      total_projects: 12,
      active_projects: 4,
      completed_projects: 8,
      team_members: 15
    }
  end

  def mock_detailed_analytics
    {
      monthly_progress: [65, 75, 80, 85, 90],
      project_distribution: { "Active" => 4, "Review" => 2, "Completed" => 8 },
      team_performance: 92
    }
  end

  def mock_notifications
    [
      { message: "Project deadline approaching", type: "warning", time: "1 hour ago" },
      { message: "New team member added", type: "info", time: "3 hours ago" },
      { message: "Milestone completed", type: "success", time: "1 day ago" }
    ]
  end
end
