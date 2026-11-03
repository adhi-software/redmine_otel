class CreateOtLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ot_logs do |t|
      t.datetime :logged_at, precision: 6, null: false, index: true
      t.integer  :severity_number, null: false, default: 0
      t.string   :severity_text, limit: 10
      t.text     :body, limit: (16.megabytes if Redmine::Database.mysql?)
      t.string   :trace_id, limit: 32, index: true
      t.string   :span_id, limit: 16
      t.text     :details
      t.timestamps null: false
    end
  end
end
