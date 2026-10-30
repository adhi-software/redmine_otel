# frozen_string_literal: true

module ObMetricsHelper
  # A measurement in its unit: seconds as a duration, bytes as KB or MB, anything else as a number.
  def ob_metric_value(value, unit)
    return '-' if value.nil?

    case unit
    when 's' then ob_duration((value * 1_000_000).round)
    when 'ms' then ob_duration((value * 1000).round)
    when 'By' then number_to_human_size(value)
    else
      value = value.round(2)
      number_with_delimiter(value == value.to_i ? value.to_i : value)
    end
  end

  # [label, value] pairs that sum up +summary+: count, average and max of a histogram,
  # total of a counter, average and max of a gauge.
  def ob_metric_stats(summary, shape, unit)
    case shape
    when :histogram
      [[l(:label_ob_count), number_with_delimiter(summary.samples.to_i)],
       [l(:label_ob_average), ob_metric_value(summary.average(shape), unit)],
       [l(:label_ob_max), ob_metric_value(summary.maximum(shape), unit)]]
    when :sum
      [[l(:label_ob_total), ob_metric_value(summary.total.to_f, unit)]]
    else
      [[l(:label_ob_average), ob_metric_value(summary.average(shape), unit)],
       [l(:label_ob_max), ob_metric_value(summary.maximum(shape), unit)]]
    end
  end

  # Dataset names for the chart script.
  def ob_chart_labels
    { count: l(:label_ob_count), average: l(:label_ob_average), max: l(:label_ob_max), total: l(:label_ob_total) }
  end

  # Each attribute of a series as its name and value; status codes coloured as on the Traces tab.
  def ob_series_labels(series)
    labels = ObMetric.labels(series)
    if labels.empty?
      return content_tag(:span, series == '{}' ? l(:label_ob_no_attributes) : series, class: 'ob-label-key')
    end

    safe_join(labels.map do |key, value|
      css = key == 'http.response.status_code' ? "ob-label ob-status-#{value.to_i / 100}xx" : 'ob-label'
      content_tag(:span, safe_join([content_tag(:span, key, class: 'ob-label-key'), value.to_s], ' '), class: css)
    end, ' ')
  end

  # Time covered by one chart point, such as "5 minutes" or "1 hour".
  def ob_bucket_label(minutes)
    key, count = if (minutes % 1440).zero? then ['x_days', minutes / 1440]
                 elsif (minutes % 60).zero? then ['x_hours', minutes / 60]
                 else ['x_minutes', minutes]
                 end
    l("datetime.distance_in_words.#{key}", count: count)
  end
end
