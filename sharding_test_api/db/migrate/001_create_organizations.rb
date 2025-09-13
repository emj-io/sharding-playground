class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :plan_type, null: false, default: 'free'

      t.timestamps
    end

    add_index :organizations, :name
    add_index :organizations, :plan_type
  end
end