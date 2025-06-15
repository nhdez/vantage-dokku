class User < ApplicationRecord
  rolify
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :omniauthable,
         omniauth_providers: [:google_oauth2]

  # Profile picture attachment
  has_one_attached :profile_picture
  
  # Activity tracking
  has_many :activity_logs, dependent: :destroy
  
  # Server management
  has_many :servers, dependent: :destroy
  
  # SSH key management
  has_many :ssh_keys, dependent: :destroy
  
  # Deployment management
  has_many :deployments, dependent: :destroy
  
  # Linked accounts management
  has_many :linked_accounts, dependent: :destroy

  # Validations
  validates :first_name, :last_name, length: { maximum: 50 }, allow_blank: true
  validates :theme, inclusion: { in: %w[light dark auto] }
  validate :profile_picture_validation

  private

  def profile_picture_validation
    return unless profile_picture.attached?

    unless profile_picture.content_type.in?(%w[image/jpeg image/jpg image/png image/gif])
      errors.add(:profile_picture, 'must be a valid image format')
    end

    if profile_picture.byte_size > 5.megabytes
      errors.add(:profile_picture, 'should be less than 5MB')
    end
  end

  public

  # Methods
  def full_name
    [first_name, last_name].compact.join(' ').presence || email.split('@').first.titleize
  end

  def initials
    if first_name.present? && last_name.present?
      "#{first_name.first}#{last_name.first}".upcase
    else
      email.first(2).upcase
    end
  end

  def admin?
    has_role?(:admin)
  end

  def moderator?
    has_role?(:mod)
  end

  # Theme methods
  def prefers_dark_mode?
    theme == 'dark'
  end

  def prefers_light_mode?
    theme == 'light'
  end

  def uses_auto_theme?
    theme == 'auto'
  end

  def effective_theme
    theme || 'auto'
  end
  
  # OAuth methods
  def self.from_omniauth(auth)
    user = where(email: auth.info.email).first
    
    if user
      # Update existing user with OAuth info
      user.update(
        provider: auth.provider,
        uid: auth.uid,
        google_avatar_url: auth.info.image
      )
    else
      # Create new user
      user = create!(
        email: auth.info.email,
        password: Devise.friendly_token[0, 20],
        first_name: auth.info.first_name,
        last_name: auth.info.last_name,
        provider: auth.provider,
        uid: auth.uid,
        google_avatar_url: auth.info.image
      )
    end
    
    user
  end
  
  def google_user?
    provider == 'google_oauth2'
  end
  
  def has_google_avatar?
    google_avatar_url.present?
  end
  
  # Linked accounts helper methods
  def github_account
    linked_accounts.github.active.first
  end
  
  def has_github_account?
    github_account.present?
  end
  
  def linked_account_for(provider)
    linked_accounts.for_provider(provider).active.first
  end
  
  def has_linked_account?(provider)
    linked_account_for(provider).present?
  end
end
