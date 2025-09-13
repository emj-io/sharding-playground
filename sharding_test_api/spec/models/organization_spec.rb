require 'rails_helper'

RSpec.describe Organization, type: :model do
  subject { build(:organization) }

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:plan_type) }
    it { should validate_inclusion_of(:plan_type).in_array(%w[free pro enterprise]) }
  end

  describe 'associations' do
    it { should have_many(:users).dependent(:destroy) }
    it { should have_many(:projects).dependent(:destroy) }
    it { should have_many(:tasks).dependent(:destroy) }
  end

  describe 'scopes' do
    let!(:free_org) { create(:organization, :free_plan) }
    let!(:pro_org) { create(:organization, :pro_plan) }
    let!(:enterprise_org) { create(:organization, :enterprise_plan) }

    it 'filters by plan type' do
      expect(Organization.by_plan('free')).to include(free_org)
      expect(Organization.by_plan('free')).not_to include(pro_org)
    end
  end


  describe 'statistics methods' do
    let(:organization) { create(:organization) }

    before do
      create_list(:user, 3, organization: organization)
      create_list(:project, 2, organization: organization)
      create_list(:task, 5, organization: organization)
    end

    it 'returns correct user count' do
      expect(organization.user_count).to eq(3)
    end

    it 'returns correct project count' do
      expect(organization.project_count).to eq(2)
    end

    it 'returns correct task count' do
      expect(organization.task_count).to eq(5)
    end
  end
end