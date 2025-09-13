require 'rails_helper'

RSpec.describe Api::V1::UsersController, type: :controller do
  let(:organization) { create(:organization, id: 1) }
  let(:shard) { shard_for_organization(organization.id) }

  before do
    with_shard(shard) do
      organization.save!
    end
  end

  describe 'GET #index' do
    before do
      with_shard(shard) do
        create_list(:user, 3, organization: organization)
      end
    end

    it 'returns all users for the organization' do
      get :index, params: { organization_id: organization.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response).to be_an(Array)
      expect(json_response.size).to eq(3)
    end

    it 'returns 400 when organization_id is missing' do
      get :index

      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Organization required')
    end
  end

  describe 'GET #show' do
    let(:user) { create(:user, organization: organization) }

    before do
      with_shard(shard) do
        user.save!
      end
    end

    it 'returns the user when found' do
      get :show, params: { organization_id: organization.id, id: user.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['id']).to eq(user.id)
      expect(json_response['email']).to eq(user.email)
    end

    it 'returns 404 when user not found' do
      get :show, params: { organization_id: organization.id, id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        organization_id: organization.id,
        user: {
          email: 'newuser@example.com',
          name: 'New User',
          role: 'member'
        }
      }
    end

    it 'creates a new user' do
      expect {
        post :create, params: valid_params
      }.to change {
        with_shard(shard) { User.count }
      }.by(1)

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response['email']).to eq('newuser@example.com')
    end

    it 'returns validation errors for invalid data' do
      invalid_params = valid_params.deep_merge(user: { email: 'invalid-email' })

      post :create, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response['errors']).to be_present
    end

    it 'creates audit log entry' do
      expect {
        post :create, params: valid_params
      }.to change { AuditLog.count }.by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('created_user')
      expect(audit_log.organization_id).to eq(organization.id)
    end

    it 'tracks feature usage' do
      expect {
        post :create, params: valid_params
      }.to change { FeatureUsage.count }.by(1)

      feature_usage = FeatureUsage.last
      expect(feature_usage.feature_name).to eq('users_created')
      expect(feature_usage.organization_id).to eq(organization.id)
    end
  end

  describe 'PUT #update' do
    let(:user) { create(:user, organization: organization) }

    before do
      with_shard(shard) do
        user.save!
      end
    end

    it 'updates the user' do
      put :update, params: {
        organization_id: organization.id,
        id: user.id,
        user: { name: 'Updated Name' }
      }

      expect(response).to have_http_status(:ok)

      with_shard(shard) do
        user.reload
        expect(user.name).to eq('Updated Name')
      end
    end

    it 'creates audit log entry' do
      expect {
        put :update, params: {
          organization_id: organization.id,
          id: user.id,
          user: { name: 'Updated Name' }
        }
      }.to change { AuditLog.count }.by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('updated_user')
    end
  end

  describe 'DELETE #destroy' do
    let(:user) { create(:user, organization: organization) }

    before do
      with_shard(shard) do
        user.save!
      end
    end

    it 'deletes the user' do
      expect {
        delete :destroy, params: { organization_id: organization.id, id: user.id }
      }.to change {
        with_shard(shard) { User.count }
      }.by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'creates audit log entry' do
      expect {
        delete :destroy, params: { organization_id: organization.id, id: user.id }
      }.to change { AuditLog.count }.by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('deleted_user')
    end
  end
end