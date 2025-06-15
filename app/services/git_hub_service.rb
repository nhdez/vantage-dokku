class GitHubService
  def initialize(linked_account)
    @linked_account = linked_account
    @client = Octokit::Client.new(access_token: @linked_account.access_token)
  end
  
  def test_connection
    begin
      user_info = @client.user
      
      {
        success: true,
        account_info: {
          login: user_info.login,
          name: user_info.name,
          email: user_info.email,
          company: user_info.company,
          blog: user_info.blog,
          location: user_info.location,
          bio: user_info.bio,
          public_repos: user_info.public_repos,
          public_gists: user_info.public_gists,
          followers: user_info.followers,
          following: user_info.following,
          avatar_url: user_info.avatar_url,
          html_url: user_info.html_url,
          created_at: user_info.created_at
        }
      }
    rescue Octokit::Unauthorized
      { success: false, error: "Invalid access token. Please check your GitHub personal access token." }
    rescue Octokit::Forbidden
      { success: false, error: "Access forbidden. Your token may not have the required permissions." }
    rescue Octokit::NotFound
      { success: false, error: "User not found. Please check your token." }
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      { success: false, error: "Connection failed. Please check your internet connection." }
    rescue StandardError => e
      Rails.logger.error "GitHub API error: #{e.message}"
      { success: false, error: "GitHub API error: #{e.message}" }
    end
  end
  
  def get_repositories(type: 'all', sort: 'updated', per_page: 30, page: 1)
    begin
      options = {
        type: type,        # 'all', 'owner', 'public', 'private', 'member'
        sort: sort,        # 'created', 'updated', 'pushed', 'full_name'
        direction: 'desc',
        per_page: per_page,
        page: page
      }
      
      repos = @client.repositories(nil, options)
      
      {
        success: true,
        repositories: repos.map do |repo|
          {
            id: repo.id,
            name: repo.name,
            full_name: repo.full_name,
            description: repo.description,
            private: repo.private,
            html_url: repo.html_url,
            clone_url: repo.clone_url,
            ssh_url: repo.ssh_url,
            default_branch: repo.default_branch,
            language: repo.language,
            size: repo.size,
            stargazers_count: repo.stargazers_count,
            watchers_count: repo.watchers_count,
            forks_count: repo.forks_count,
            open_issues_count: repo.open_issues_count,
            created_at: repo.created_at,
            updated_at: repo.updated_at,
            pushed_at: repo.pushed_at
          }
        end,
        total_count: repos.length,
        has_more: repos.length == per_page
      }
    rescue Octokit::Unauthorized
      { success: false, error: "Invalid access token. Please check your GitHub personal access token." }
    rescue Octokit::Forbidden
      { success: false, error: "Access forbidden. Your token may not have the required permissions." }
    rescue StandardError => e
      Rails.logger.error "GitHub repositories fetch error: #{e.message}"
      { success: false, error: "Failed to fetch repositories: #{e.message}" }
    end
  end
  
  def get_repository(owner, repo)
    begin
      repository = @client.repository("#{owner}/#{repo}")
      
      {
        success: true,
        repository: {
          id: repository.id,
          name: repository.name,
          full_name: repository.full_name,
          description: repository.description,
          private: repository.private,
          html_url: repository.html_url,
          clone_url: repository.clone_url,
          ssh_url: repository.ssh_url,
          default_branch: repository.default_branch,
          language: repository.language,
          size: repository.size,
          stargazers_count: repository.stargazers_count,
          watchers_count: repository.watchers_count,
          forks_count: repository.forks_count,
          open_issues_count: repository.open_issues_count,
          topics: repository.topics,
          created_at: repository.created_at,
          updated_at: repository.updated_at,
          pushed_at: repository.pushed_at
        }
      }
    rescue Octokit::NotFound
      { success: false, error: "Repository not found or you don't have access to it." }
    rescue Octokit::Unauthorized
      { success: false, error: "Invalid access token. Please check your GitHub personal access token." }
    rescue Octokit::Forbidden
      { success: false, error: "Access forbidden. Your token may not have the required permissions." }
    rescue StandardError => e
      Rails.logger.error "GitHub repository fetch error: #{e.message}"
      { success: false, error: "Failed to fetch repository: #{e.message}" }
    end
  end
  
  def get_branches(owner, repo)
    begin
      branches = @client.branches("#{owner}/#{repo}")
      
      {
        success: true,
        branches: branches.map do |branch|
          {
            name: branch.name,
            commit_sha: branch.commit.sha,
            protected: branch.protected
          }
        end
      }
    rescue Octokit::NotFound
      { success: false, error: "Repository not found or you don't have access to it." }
    rescue Octokit::Unauthorized
      { success: false, error: "Invalid access token. Please check your GitHub personal access token." }
    rescue Octokit::Forbidden
      { success: false, error: "Access forbidden. Your token may not have the required permissions." }
    rescue StandardError => e
      Rails.logger.error "GitHub branches fetch error: #{e.message}"
      { success: false, error: "Failed to fetch branches: #{e.message}" }
    end
  end
  
  def get_user_organizations
    begin
      orgs = @client.organizations
      
      {
        success: true,
        organizations: orgs.map do |org|
          {
            id: org.id,
            login: org.login,
            avatar_url: org.avatar_url,
            description: org.description,
            html_url: "https://github.com/#{org.login}"
          }
        end
      }
    rescue Octokit::Unauthorized
      { success: false, error: "Invalid access token. Please check your GitHub personal access token." }
    rescue Octokit::Forbidden
      { success: false, error: "Access forbidden. Your token may not have the required permissions." }
    rescue StandardError => e
      Rails.logger.error "GitHub organizations fetch error: #{e.message}"
      { success: false, error: "Failed to fetch organizations: #{e.message}" }
    end
  end
  
  def validate_webhook_url(url)
    begin
      require 'net/http'
      require 'uri'
      
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 10
      http.open_timeout = 10
      
      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.body = { test: true }.to_json
      
      response = http.request(request)
      
      # We expect either a successful response or a specific error that indicates the endpoint exists
      if response.code.to_i < 500
        { success: true, message: "Webhook URL is reachable" }
      else
        { success: false, error: "Webhook URL returned server error (#{response.code})" }
      end
    rescue StandardError => e
      { success: false, error: "Webhook URL is not reachable: #{e.message}" }
    end
  end
  
  private
  
  def handle_rate_limit
    # GitHub API has rate limits, we can handle them here if needed
    if @client.rate_limit.remaining < 10
      Rails.logger.warn "GitHub API rate limit low: #{@client.rate_limit.remaining} requests remaining"
    end
  end
end