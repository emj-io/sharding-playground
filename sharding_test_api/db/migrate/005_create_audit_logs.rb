class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.references :organization, null: false
      t.references :user, null: true
      t.string :action, null: false
      t.string :resource_type, null: false
      t.bigint :resource_id, null: false
      t.json :metadata

      t.timestamps
    end

    add_index :audit_logs, [:organization_id, :created_at]
    add_index :audit_logs, [:action, :created_at]
    add_index :audit_logs, [:resource_type, :resource_id]
    add_index :audit_logs, :created_at
  end
end