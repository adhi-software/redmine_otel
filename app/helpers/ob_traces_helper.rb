# frozen_string_literal: true

module ObTracesHelper
  # Date and time to the second, in the user's time zone.
  def ob_time(time)
    time = ob_local(time)
    "#{format_date(time)} #{time.strftime('%H:%M:%S')}"
  end

  def ob_local(time)
    zone = User.current.time_zone
    zone ? time.in_time_zone(zone) : time
  end

  def ob_period_options(value)
    hours = [1, 2, 6, 12, 24].map do |count|
      [count == 1 ? l(:label_ob_last_hour) : l(:label_ob_last_hours, count: count), "#{count}h"]
    end
    days = [2, 7].map { [l(:label_ob_last_days, count: _1), "#{_1}d"] }
    options_for_select([[l(:label_ob_any_time), '']] + hours + days +
                       [[l(:label_ob_custom_range), 'custom']], value)
  end

  def ob_sort_options(value)
    options_for_select([[l(:label_ob_most_recent), 'started_at:desc'],
                        [l(:label_ob_oldest_first), 'started_at'],
                        [l(:label_ob_longest_first), 'duration:desc'],
                        [l(:label_ob_shortest_first), 'duration']], value)
  end

  # Chart.js bubbles: start time (epoch ms) across, duration (ms) up, sized by span count.
  def ob_chart_points(traces, span_counts)
    traces.map do |trace|
      spans = span_counts[trace.trace_id].to_i
      status = [trace.http_status, (l(:label_ob_error) if trace.failed?)].compact.join(' · ')
      { x: (trace.started_at.to_f * 1000).round, y: (trace.duration_us / 1000.0).round(3),
        r: (4 + Math.sqrt(spans) * 0.6).clamp(4, 12).round(1), failed: trace.failed?,
        url: ob_trace_path(trace.trace_id), duration: ob_duration(trace.duration_us),
        details: [trace.name, "#{ob_time(trace.started_at)} · #{l(:label_ob_x_spans, count: spans)}",
                  status.presence].compact }
    end
  end

  # IANA name of the user's zone, for chart times.
  def ob_zone_name
    (User.current.time_zone || Time.zone).tzinfo.name
  end

  def ob_duration(us)
    ms = us.to_i / 1000.0
    return "#{(ms / 1000).round(2)} s" if ms >= 1000

    "#{ms.round(ms < 10 ? 2 : 1)} ms"
  end

  # The SQL, template or URL behind a span, shown after its name.
  def ob_span_hint(span)
    attributes = span.span_attributes
    hint = attributes['db.statement'] || attributes['identifier'] || attributes['code.filepath']
    hint ||= span.target unless span.root?
    hint&.delete_prefix("#{Rails.root}/")&.truncate(200)
  end

  # Waterfall axis ticks as [percent, offset label].
  def ob_ticks(duration_us)
    [0, 25, 50, 75, 100].map { [_1, _1.zero? ? '0' : ob_duration(duration_us * _1 / 100)] }
  end

  # Bar position in percent; very short spans keep a visible sliver.
  def ob_bar_style(span, started_at, duration_us)
    total = [duration_us, 1].max.to_f
    left = (span.started_at - started_at) * 1_000_000 / total * 100
    width = [span.duration_us / total * 100, 0.3].max
    "left: #{left.round(2)}%; width: #{[width, 100 - left].min.round(2)}%;"
  end

  # Long or multi-line values, like SQL, keep their line breaks.
  def ob_value(value)
    text = value.is_a?(Array) ? value.join(', ') : value.to_s
    text.include?("\n") || text.length > 120 ? content_tag(:pre, text) : text
  end
end
