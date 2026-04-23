# frozen_string_literal: true

class AppSignUpService < BaseService
  include RegistrationHelper

  def call(app, remote_ip, params)
    @app       = app
    @remote_ip = remote_ip
    @params    = params

    raise Mastodon::NotPermittedError unless allowed_registration?(remote_ip, invite)

    ApplicationRecord.transaction do
      create_user!
      create_access_token!
    end

    @access_token
  end

  private

  def create_user!
    @user = User.new(
      user_params.merge(
        created_by_application: @app,
        sign_up_ip: @remote_ip,
        password_confirmation: user_params[:password],
        account_attributes: account_params,
        invite_request_attributes: invite_request_params
      )
    )

    prepare_invite_request_for_url_validation if invite_request_url_required?(invite)
    @user.save!
  end

  def create_access_token!
    @access_token = Doorkeeper::AccessToken.create!(
      application: @app,
      resource_owner_id: @user.id,
      scopes: @app.scopes,
      expires_in: Doorkeeper.configuration.access_token_expires_in,
      use_refresh_token: Doorkeeper.configuration.refresh_token_enabled?
    )
  end

  def invite
    Invite.find_by(code: @params[:invite_code]) if @params[:invite_code].present?
  end

  def user_params
    @params.slice(:email, :password, :agreement, :locale, :time_zone, :invite_code, :date_of_birth)
  end

  def account_params
    @params.slice(:username)
  end

  def invite_request_params
    { text: @params[:reason] }
  end

  def prepare_invite_request_for_url_validation
    invite_request = @user.invite_request || @user.build_invite_request
    invite_request.text = @params[:reason]
    invite_request.require_url = true
  end
end
