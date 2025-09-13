class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: 'active'

      t.timestamps
    end

    add_index :projects, [:organization_id, :status]
    add_index :projects, [:organization_id, :name]
  end
end