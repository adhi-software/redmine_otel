# frozen_string_literal: true

# A metric point saved by DatabaseMetricExporter each minute. value is a histogram's sum,
# a counter's increase over that minute or a gauge's reading.
class OtMetric < ApplicationRecord
  # Totals of a set of points, in the order of summary_columns.
  Summary = Struct.new(:samples, :total, :mean, :peak, :largest, :least) do
    def average(shape) = shape == :histogram ? (total.to_f / samples.to_i if samples.to_i.positive?) : mean&.to_f

    def maximum(shape) = (shape == :histogram ? largest : peak)&.to_f

    def minimum = least&.to_f
  end

  class Histogram
    def add(bounds, counts, max)
      @bounds ||= bounds
      return unless bounds == @bounds && counts.size == bounds.size + 1

      @counts ||= Array.new(counts.size, 0)
      counts.each_with_index { |count, i| @counts[i] += count.to_i }
      @max = [@max, max].compact.max
    end

    def empty? = @counts.nil?

    def percentiles(list) = list.to_h { [_1, percentile(_1)] }

    def percentile(percent)
      return if empty?

      rank = @counts.sum * percent / 100.0
      seen = 0
      @counts.each_with_index do |count, i|
        if count.positive? && seen + count >= rank
          lower = i.zero? ? 0.0 : @bounds[i - 1]
          upper = @bounds[i] || @max || lower
          value = lower + ((upper - lower) * (rank - seen) / count)
          return @max ? [value, @max].min : value
        end
        seen += count
      end
      nil
    end
  end

  def self.summary_columns
    table = arel_table
    [table[:count].sum, table[:value].sum, table[:value].average, table[:value].maximum, table[:max].maximum, table[:value].minimum]
  end

  def self.buckets(details)
    parsed = JSON.parse(details.presence || '{}')
    bounds, counts = parsed.values_at('bounds', 'counts')
    [bounds, counts] if bounds.is_a?(Array) && counts.is_a?(Array)
  rescue JSON::ParserError
    nil
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
