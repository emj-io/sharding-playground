require 'rails_helper'

RSpec.describe ApplicationRecord, type: :model do
  describe 'base functionality' do
    it 'is an abstract class' do
      expect(ApplicationRecord.abstract_class?).to be true
    end

    it 'inherits from ActiveRecord::Base' do
      expect(ApplicationRecord.superclass).to eq(ActiveRecord::Base)
    end
  end
end