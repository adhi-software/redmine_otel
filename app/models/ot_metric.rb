# frozen_string_literal: true

# A metric point saved by DatabaseMetricExporter each minute. value is a histogram's sum,
# a counter's increase over that minute or a gauge's reading.
class OtMetric < ApplicationRecord
  # Totals of a set of points, in the order of summary_columns.
  Summary = Struct.new(:samples, :total, :mean, :peak, :largest) do
    def average(shape) = shape == :histogram ? (total.to_f / samples.to_i if samples.to_i.positive?) : mean&.to_f

    def maximum(shape) = (shape == :histogram ? largest : peak)&.to_f
  end

  def self.summary_columns
    table = arel_table
    [table[:count].sum, table[:value].sum, table[:value].average, table[:value].maximum, table[:max].maximum]
  end

  # Start minute of the bucket of +size+ minutes that a point falls in.
  def self.bucket_column(size)
    minute = arel_table[:minute]
    Arel::Nodes::Subtraction.new(minute, Arel::Nodes::InfixOperation.new('%', minute, Arel::Nodes.build_quoted(size.to_i)))
  end

  def self.shape(kind)
    case kind.to_s
    when 'histogram' then :histogram
    when /gauge/ then :gauge
    else :sum
    end
  end

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
