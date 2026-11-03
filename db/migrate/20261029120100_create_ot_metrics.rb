class CreateOtMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :ot_metrics do |t|
      t.string   :name, null: false
      t.string   :kind, limit: 30, null: false
      t.string   :unit, limit: 30
      t.string   :series, limit: 1024, null: false, default: '{}'
      t.datetime :recorded_at, precision: 6, null: false, index: true
      t.integer  :minute, null: false
      t.float    :value
      t.bigint   :count
      t.float    :min
      t.float    :max
      t.text     :details
      t.timestamps null: false
    end
    add_index :ot_metrics, [:name, :recorded_at]
  end
end
