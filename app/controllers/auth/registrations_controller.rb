# frozen_string_literal: true

class Auth::RegistrationsController < Devise::RegistrationsController
  layout "authentication", except: :edit

  include CheckLDAP
  include SessionFlash

  before_action :check_signup, only: %i[new create]
  before_action :check_admin, only: %i[new create]
  before_action :configure_sign_up_params, only: [:create]

  # rubocop:disable Rails/LexicallyScopedActionFilter
  before_action :authenticate_user!, only: [:disable]
  # rubocop:enable Rails/LexicallyScopedActionFilter

  # Re-implemented so the template has the auxiliary variables regarding if
  # there are more users on the system or this is the first user to be created.
  def new
    @have_users = User.not_portus.any?
    super
  end

  def create
    build_resource(sign_up_params)

    resource.save
    yield resource if block_given?
    if resource.persisted?
      resource_persisted_response!
    else
      clean_up_passwords resource
      set_minimum_password_length
      redirect_to new_user_registration_path, alert: resource.errors.full_messages
    end
  end

  def edit
    @admin_count = User.admins.count
    super
  end

  def update
    success =
      if password_update?
        succ = current_user.update_with_password(user_params)
        bypass_sign_in(current_user) if succ
        succ
      else
        current_user.update_without_password(params.require(:user).permit(:email, :display_name))
      end

    if success
      redirect_to edit_user_registration_path,
                  notice: "Profile updated successfully!", float: true
    else
      redirect_to edit_user_registration_path,
                  alert: resource.errors.full_messages, float: true
    end
  end

  # Enable/Disable a user.
  def toggle_enabled
    user = User.find(params[:id])

    if current_user.toggle_enabled!(user)
      sign_out user if current_user == user && !user.enabled?
      render template: "auth/registrations/toggle_enabled",
             locals:   { user: user, path: request.fullpath }
    else
      render nothing: true, status: 403
    end
  end

  # Devise does not allow to disable routes on purpose. Ideally, though we
  # could still be able to disable the `destroy` method through the
  # `routes.rb` file as described in the wiki (by disabling all the routes and
  # calling `devise_scope` manually). However, this solution has the caveat
  # that it would ignore some calls (e.g. the `layout` call above). Therefore,
  # the best solution is to just implement a `destroy` method that just returns
  # a 404.
  def destroy
    render nothing: true, status: 404
  end

  def check_admin
    @admin = User.admins.any?
    @first_user_admin = APP_CONFIG.enabled?("first_user_admin")
  end

  # Redirect to the login page if users cannot access the signup page.
  def check_signup
    redirect_to new_user_session_path unless APP_CONFIG.enabled?("signup")
  end

  def configure_sign_up_params
    keys = User.admins.any? ? %i[email] : %i[email admin]
    devise_parameter_sanitizer.permit(:sign_up, keys: keys)
  end

  protected

  # Performs the response in the case of a registration success.
  def resource_persisted_response!
    if resource.active_for_authentication?
      session_flash(resource, :signed_up)
      sign_up(resource_name, resource)
      respond_with resource, location: after_sign_up_path_for(resource), float: true
    else
      # :nocov:
      session_flash(resource, :"signed_up_but_#{resource.inactive_message}")
      expire_data_after_sign_in!
      respond_with resource, location: after_inactive_sign_up_path_for(resource), float: true
      # :nocov:
    end
  end

  # Returns true if the contents of the `params` hash contains the needed keys
  # to update the password of the user.
  def password_update?
    user = params[:user]
    user[:current_password].present? || user[:password].present? ||
      user[:password_confirmation].present?
  end

  # Returns the required parameters and the permitted ones for updating a user.
  def user_params
    params.require(:user)
          .permit(:password, :password_confirmation, :current_password)
  end

  # Prevents redirect loops
  def after_sign_up_path_for(resource)
    signed_in_root_path(resource)
  end
end
