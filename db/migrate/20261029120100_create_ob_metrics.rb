class CreateObMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :ob_metrics do |t|
      t.string   :name, null: false
      t.string   :kind, limit: 30, null: false
      t.string   :unit, limit: 30
      # JSON of the point's attributes with sorted keys, so a series always has the same text.
      t.string   :series, limit: 1024, null: false, default: '{}'
      t.datetime :recorded_at, precision: 6, null: false, index: true
      # Minutes since the epoch at recorded_at; charts group on it with plain integer SQL.
      t.integer  :minute, null: false
      t.float    :value
      t.bigint   :count
      t.float    :min
      t.float    :max
      # JSON: description, and a histogram's bucket bounds and counts.
      t.text     :details
      t.timestamps null: false
    end
    add_index :ob_metrics, [:name, :recorded_at]
  end
end
