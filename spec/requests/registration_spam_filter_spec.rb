# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RegistrationSpamFilter do
  let(:spam_reasons) do
    [
      'Personal account for reading timelines.',
      'I am a developer interested in tech discussions and open source communities.',
      'Join the fediverse to follow tech discussions and open-source projects.',
    ]
  end

  let(:spam_reason) { spam_reasons.first }

  before { Setting.registrations_mode = 'approved' }

  describe '.spam?' do
    it 'matches each known reason regardless of email, ignoring surrounding whitespace' do
      spam_reasons.each do |reason|
        expect(described_class.spam?(email: 'anyone@example.com', username: 'uki2zuyqjq', reason: "  #{reason}\r\n")).to be(true), reason
      end
    end

    it 'does not match other reasons' do
      expect(described_class.spam?(email: 'anyone@example.com', username: 'x', reason: 'I would like to join')).to be false
      expect(described_class.spam?(email: nil, username: nil, reason: nil)).to be false
    end
  end

  describe 'POST /auth' do
    subject do
      post '/auth', params: { user: { account_attributes: { username: 'uki2zuyqjq' }, email: 'someone@example.com', password: '12345678', password_confirmation: '12345678', agreement: 'true', invite_request_attributes: { text: reason } } }
    end

    context 'when the sign-up matches a rule' do
      let(:reason) { spam_reason }

      it 'pretends success without creating a user or sending mail' do
        expect { subject }
          .to not_change(User, :count)
          .and not_change(Account, :count)
          .and not_have_enqueued_mail

        expect(response).to redirect_to(auth_setup_path)
      end
    end

    context 'when the sign-up does not match a rule' do
      let(:reason) { 'I would like to join' }

      it 'creates a pending user as usual' do
        expect { subject }.to change(User, :count).by(1)

        expect(User.find_by(email: 'someone@example.com')).to be_pending
      end
    end
  end

  describe 'POST /api/v1/accounts' do
    subject do
      post '/api/v1/accounts', headers: { 'Authorization' => "Bearer #{token.token}" }, params: { username: 'uki2zuyqjq', password: '12345678', email: 'someone@example.com', agreement: 'true', reason: reason }
    end

    let(:token) { Fabricate(:client_credentials_token, application: Fabricate(:application), scopes: 'read write') }

    context 'when the sign-up matches a rule' do
      let(:reason) { spam_reason }

      it 'rejects without creating a user' do
        expect { subject }
          .to not_change(User, :count)
          .and not_have_enqueued_mail

        expect(response).to have_http_status(403)
      end
    end

    context 'when the sign-up does not match a rule' do
      let(:reason) { 'I would like to join' }

      it 'creates a pending user as usual' do
        expect { subject }.to change(User, :count).by(1)

        expect(response).to have_http_status(200)
      end
    end
  end
end
