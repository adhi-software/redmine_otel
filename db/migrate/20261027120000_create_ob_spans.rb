class CreateObSpans < ActiveRecord::Migration[8.1]
  def change
    create_table :ob_spans do |t|
      t.string   :trace_id, limit: 32, null: false, index: true
      t.string   :span_id, limit: 16, null: false
      t.string   :parent_span_id, limit: 16
      t.boolean  :root, null: false, default: false
      t.string   :kind, limit: 10
      t.string   :name, null: false
      t.string   :target
      t.integer  :http_status
      t.boolean  :error, null: false, default: false
      t.datetime :started_at, precision: 6, null: false, index: true
      t.bigint   :duration_us, null: false
      # JSON: attributes, events and the status message. MySQL's plain text stops at 64 KB.
      t.text     :details, limit: (16.megabytes if Redmine::Database.mysql?)
      t.timestamps null: false
    end
    add_index :ob_spans, [:root, :started_at]
  end
end
