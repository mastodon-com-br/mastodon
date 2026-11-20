# frozen_string_literal: true

# Instance-specific filter that silently drops sign-ups from known spam bots
# before any record is created. Hooked into the upstream sign-up code paths via
# `prepend` in config/initializers/registration_spam_filter.rb.
#
# Each rule receives the canonicalized email (lowercased, dots and +tag removed
# from the local part, see CanonicalEmail), the username and the stripped
# "reason for joining" text.
module RegistrationSpamFilter
  SPAM_REASONS = [
    'Personal account for reading timelines.',
    'I am a developer interested in tech discussions and open source communities.',
    'Join the fediverse to follow tech discussions and open-source projects.',
  ].freeze

  RULES = [
    ->(reason:, **) { SPAM_REASONS.include?(reason) },
  ].freeze

  def self.spam?(email:, username:, reason:)
    canonical_email = CanonicalEmailBlock.canonicalize_email(email.to_s.strip)

    RULES.any? { |rule| rule.call(email: canonical_email, username: username.to_s, reason: reason.to_s.strip) }
  end

  # Prepended to Auth::RegistrationsController
  module WebRegistration
    def create
      user_params = params[:user] || {}
      return super unless RegistrationSpamFilter.spam?(email: user_params[:email], username: user_params.dig(:account_attributes, :username), reason: user_params.dig(:invite_request_attributes, :text))

      Rails.logger.info("RegistrationSpamFilter: dropped web sign-up for #{user_params[:email]} from #{request.remote_ip}")
      redirect_to auth_setup_path # Same redirect as a successful sign-up
    end
  end

  # Prepended to AppSignUpService (POST /api/v1/accounts)
  module ApiRegistration
    def call(app, remote_ip, params)
      if RegistrationSpamFilter.spam?(email: params[:email], username: params[:username], reason: params[:reason])
        Rails.logger.info("RegistrationSpamFilter: dropped API sign-up for #{params[:email]} from #{remote_ip}")
        raise Mastodon::NotPermittedError
      end

      super
    end
  end
end
