require 'rails_helper'

RSpec.describe Api::V1::Admin::OrganizationsController, type: :controller do
  describe 'GET #index' do
    before do
      # Create organizations on different shards
      [1, 2, 3].each do |org_id|
        shard = shard_for_organization(org_id)
        with_shard(shard) do
          org = create(:organization, id: org_id, name: "Org #{org_id}")
          create_list(:user, org_id, organization: org)
          create_list(:project, org_id, organization: org)
          create_list(:task, org_id * 2, organization: org)
        end
      end
    end

    it 'returns all organizations from all shards' do
      get :index

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response['organizations']).to be_an(Array)
      expect(json_response['organizations'].size).to eq(3)

      # Check that statistics are included
      expect(json_response['statistics']).to be_present
      expect(json_response['statistics']['total_organizations']).to eq(3)
      expect(json_response['statistics']['total_users']).to eq(6) # 1+2+3
      expect(json_response['statistics']['total_projects']).to eq(6) # 1+2+3
      expect(json_response['statistics']['total_tasks']).to eq(12) # 2+4+6
    end

    it 'includes shard information for each organization' do
      get :index

      json_response = JSON.parse(response.body)
      organizations = json_response['organizations']

      organizations.each do |org|
        expect(org['shard']).to be_present
        expected_shard = "shard_#{org['id'] % Rails.application.config.sharding.shard_count}"
        expect(org['shard']).to eq(expected_shard)
      end
    end

    it 'includes usage statistics for each organization' do
      get :index

      json_response = JSON.parse(response.body)
      organizations = json_response['organizations']

      organizations.each do |org|
        expect(org['user_count']).to be_present
        expect(org['project_count']).to be_present
        expect(org['task_count']).to be_present
      end
    end
  end

  describe 'GET #show' do
    let(:organization_id) { 5 }
    let(:shard) { shard_for_organization(organization_id) }

    before do
      with_shard(shard) do
        @organization = create(:organization, id: organization_id, name: "Test Org")
        create_list(:user, 2, :admin, organization: @organization)
        create_list(:user, 3, :member, organization: @organization)
        create_list(:project, 2, :active, organization: @organization)
        create_list(:project, 1, :completed, organization: @organization)
        create_list(:task, 5, :todo, organization: @organization)
        create_list(:task, 3, :done, organization: @organization)
      end

      # Create some audit logs
      create_list(:audit_log, 3, organization_id: organization_id)
    end

    it 'returns detailed organization information' do
      get :show, params: { id: organization_id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response['id']).to eq(organization_id)
      expect(json_response['name']).to eq("Test Org")
      expect(json_response['shard']).to eq(shard.to_s)
    end

    it 'includes detailed statistics' do
      get :show, params: { id: organization_id }

      json_response = JSON.parse(response.body)
      detailed_stats = json_response['detailed_stats']

      expect(detailed_stats['users']).to eq({ 'admin' => 2, 'member' => 3 })
      expect(detailed_stats['projects']).to eq({ 'active' => 2, 'completed' => 1 })
      expect(detailed_stats['tasks']).to eq({ 'todo' => 5, 'done' => 3 })
    end

    it 'includes recent activity' do
      get :show, params: { id: organization_id }

      json_response = JSON.parse(response.body)
      recent_activity = json_response['detailed_stats']['recent_activity']

      expect(recent_activity).to be_an(Array)
      expect(recent_activity.size).to eq(3)
    end

    it 'returns 404 for non-existent organization' do
      get :show, params: { id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  # Helper to create audit logs
  def create_audit_log(organization_id:, action: 'test_action')
    AuditLog.create!(
      organization_id: organization_id,
      action: action,
      resource_type: 'TestResource',
      resource_id: 1
    )
  end

  private

  def create_list(factory_name, count, *traits, **attributes)
    count.times.map { create(factory_name, *traits, **attributes) }
  end

  def create(factory_name, *traits, **attributes)
    FactoryBot.create(factory_name, *traits, **attributes)
  end
end