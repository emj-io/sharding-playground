class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.references :project, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :assigned_user, null: true, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: 'todo'
      t.string :priority, null: false, default: 'medium'
      t.date :due_date

      t.timestamps
    end

    add_index :tasks, [:organization_id, :status]
    add_index :tasks, [:organization_id, :priority]
    add_index :tasks, [:project_id, :status]
    add_index :tasks, [:assigned_user_id, :status]
    add_index :tasks, :due_date
  end
end