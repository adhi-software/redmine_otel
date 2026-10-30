# frozen_string_literal: true

# One data point of a metric, saved by DatabaseMetricExporter each minute. A histogram or
# counter point holds only that minute, so points add up across minutes and processes;
# a gauge point is a reading. value is a histogram's sum, a counter's increase or a gauge's reading.
class ObMetric < ApplicationRecord
  # Totals of a set of points, from the columns of ObMetric.summary_columns in order:
  # histogram measurements, sum of value, mean and largest value, largest measurement.
  Summary = Struct.new(:samples, :total, :mean, :peak, :largest) do
    # Mean of a histogram's measurements, or of a gauge's readings.
    def average(shape) = shape == :histogram ? (total.to_f / samples.to_i if samples.to_i.positive?) : mean&.to_f

    # Largest measurement of a histogram, or largest reading of a gauge.
    def maximum(shape) = (shape == :histogram ? largest : peak)&.to_f
  end

  def self.summary_columns
    table = arel_table
    [table[:count].sum, table[:value].sum, table[:value].average, table[:value].maximum, table[:max].maximum]
  end

  # Start of the bucket of +size+ minutes that a point falls in, in minutes since the epoch.
  def self.bucket_column(size)
    minute = arel_table[:minute]
    Arel::Nodes::Subtraction.new(minute, Arel::Nodes::InfixOperation.new('%', minute, Arel::Nodes.build_quoted(size.to_i)))
  end

  # How an instrument kind is charted: :histogram, :gauge, or :sum for counters.
  def self.shape(kind)
    case kind.to_s
    when 'histogram' then :histogram
    when /gauge/ then :gauge
    else :sum
    end
  end

  # Attribute name => value of a series, such as http.route; empty when cut short.
  def self.labels(series)
    JSON.parse(series.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def shape = self.class.shape(kind)

  def description = parsed_details['description']

  private

  def parsed_details
    @parsed_details ||= JSON.parse(details.presence || '{}')
  rescue JSON::ParserError
    @parsed_details = {}
  end
end
