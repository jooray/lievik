class CreateDevLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :dev_logs do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :log_type, null: false
      t.text :message
      t.json :details, default: {}
      t.string :parent_type
      t.bigint :parent_id
      t.index [:user_id, :created_at]
      t.index [:parent_type, :parent_id]

      t.timestamps
    end
  end
end
