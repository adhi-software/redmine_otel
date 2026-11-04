# frozen_string_literal: true

module OtMetricsHelper
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

  # [label, value] pairs summing up +summary+ for its +shape+.
  def ot_metric_stats(summary, shape, unit)
    case shape
    when :histogram
      [[l(:label_ot_count), number_with_delimiter(summary.samples.to_i)],
       [l(:label_ot_average), ot_metric_value(summary.average(shape), unit)],
       [l(:label_ot_max), ot_metric_value(summary.maximum(shape), unit)]]
    when :sum
      [[l(:label_ot_total), ot_metric_value(summary.total.to_f, unit)]]
    else
      [[l(:label_ot_average), ot_metric_value(summary.average(shape), unit)],
       [l(:label_ot_max), ot_metric_value(summary.maximum(shape), unit)]]
    end
  end

  def ot_chart_labels
    { count: l(:label_ot_count), average: l(:label_ot_average), max: l(:label_ot_max), total: l(:label_ot_total) }
  end

  def ot_series_labels(series)
    labels = OtMetric.labels(series)
    if labels.empty?
      return content_tag(:span, series == '{}' ? l(:label_ot_no_attributes) : series, class: 'ot-label-key')
    end

    safe_join(labels.map do |key, value|
      css = key == 'http.response.status_code' ? "ot-label ot-status-#{value.to_i / 100}xx" : 'ot-label'
      content_tag(:span, safe_join([content_tag(:span, key, class: 'ot-label-key'), value.to_s], ' '), class: css)
    end, ' ')
  end

  def ot_series_query(series)
    OtMetric.labels(series).values.join(' ')
  end

  def ot_bucket_label(minutes)
    key, count = if (minutes % 1440).zero? then ['x_days', minutes / 1440]
                 elsif (minutes % 60).zero? then ['x_hours', minutes / 60]
                 else ['x_minutes', minutes]
                 end
    l("datetime.distance_in_words.#{key}", count: count)
  end
end
