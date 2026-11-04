# frozen_string_literal: true

module OtMetricsHelper
  def ot_metric_options(names, selected)
    grouped_options_for_select(names.group_by { _1.split('.').first }, selected)
  end

  def ot_metric_value(value, unit)
    return '-' if value.nil?

    case unit
    when 's' then ot_duration((value * 1_000_000).round)
    when 'ms' then ot_duration((value * 1000).round)
    when 'By' then number_to_human_size(value)
    else
      value = value.round(2)
      number_with_delimiter(value == value.to_i ? value.to_i : value)
    end
  end

  # [label, value, raw] triples summing up +summary+ for its +shape+.
  def ot_metric_stats(summary, shape, unit, percentiles = nil)
    case shape
    when :histogram
      middle = percentiles&.map { |percent, value| ot_stat("p#{percent}", value, unit) } || [ot_stat(l(:label_ot_average), summary.average(shape), unit)]
      [[l(:label_ot_count), number_with_delimiter(summary.samples.to_i), summary.samples.to_i],
       *middle, ot_stat(l(:label_ot_max), summary.maximum(shape), unit)]
    when :sum
      [ot_stat(l(:label_ot_total), summary.total.to_f, unit)]
    else
      [ot_stat(l(:label_ot_average), summary.average(shape), unit), ot_stat(l(:label_ot_min), summary.minimum, unit),
       ot_stat(l(:label_ot_max), summary.maximum(shape), unit)]
    end
  end

  def ot_metric_tiles(summary, shape, unit, percentiles, error_rate)
    return ot_metric_stats(summary, shape, unit).map { _1.first(2) } unless shape == :histogram

    tiles = [[l(:label_ot_count), number_with_delimiter(summary.samples.to_i)]]
    tiles << [l(:label_ot_errors), number_to_percentage(error_rate * 100, precision: 1)] if error_rate
    latency = if percentiles
                percentiles.slice(95, 99).map { |percent, value| ["p#{percent}", value] }
              else
                [[l(:label_ot_average), summary.average(shape)], [l(:label_ot_max), summary.maximum(shape)]]
              end
    tiles + latency.map { |label, value| [label, ot_metric_value(value, unit)] }
  end

  def ot_sort_value(value)
    value.is_a?(Float) ? format('%.9f', value) : value.to_s
  end

  def ot_series_value(key, value)
    return value.to_s unless key == OtMetricsController::STATUS

    content_tag(:span, value, class: "ot-label ot-status-#{value.to_i / 100}xx")
  end

  def ot_chart_labels
    { average: l(:label_ot_average), max: l(:label_ot_max), min: l(:label_ot_min), range: l(:label_ot_range),
      rate: l(:label_ot_per_minute), ok: l(:label_ot_ok), errors: l(:label_ot_error),
      p50: 'p50', p95: 'p95', p99: 'p99' }
  end

  def ot_bucket_label(minutes)
    key, count = if (minutes % 1440).zero? then ['x_days', minutes / 1440]
                 elsif (minutes % 60).zero? then ['x_hours', minutes / 60]
                 else ['x_minutes', minutes]
                 end
    l("datetime.distance_in_words.#{key}", count: count)
  end

  private

  def ot_stat(label, value, unit)
    [label, ot_metric_value(value, unit), value]
  end
end
