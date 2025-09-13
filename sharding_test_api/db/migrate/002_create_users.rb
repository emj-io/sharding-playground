class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :name, null: false
      t.string :role, null: false, default: 'member'

      t.timestamps
    end

    add_index :users, :email
    add_index :users, [:organization_id, :email], unique: true
    add_index :users, [:organization_id, :role]
  end
end