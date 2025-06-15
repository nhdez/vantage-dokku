class LinkedAccountPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present? && (record.user == user || user.admin?)
  end

  def create?
    user.present?
  end

  def new?
    create?
  end

  def update?
    user.present? && (record.user == user || user.admin?)
  end

  def edit?
    update?
  end

  def destroy?
    user.present? && (record.user == user || user.admin?)
  end

  def test_connection?
    user.present? && (record.user == user || user.admin?)
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end
end