class CreateFeatureUsage < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_usage do |t|
      t.references :organization, null: false
      t.string :feature_name, null: false
      t.integer :usage_count, null: false, default: 0
      t.date :date, null: false

      t.timestamps
    end

    add_index :feature_usage, [:organization_id, :date]
    add_index :feature_usage, [:feature_name, :date]
    add_index :feature_usage, [:organization_id, :feature_name, :date], unique: true, name: 'idx_feature_usage_unique'
  end
end