# frozen_string_literal: true

Rails.application.config.to_prepare do
  Auth::RegistrationsController.prepend(RegistrationSpamFilter::WebRegistration)
  AppSignUpService.prepend(RegistrationSpamFilter::ApiRegistration)
end
