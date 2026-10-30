# frozen_string_literal: true

module ObLogsHelper
  def ob_level_options(value)
    levels = %w[info warn error].map { [l(:label_ob_level_at_least, level: l(:"label_ob_level_#{_1}")), _1] }
    options_for_select([[l(:label_ob_all_levels), '']] + levels, value)
  end

  def ob_log_sort_options(value)
    options_for_select([[l(:label_ob_most_recent), 'logged_at:desc'],
                        [l(:label_ob_oldest_first), 'logged_at']], value)
  end

  # Time to the millisecond in the user's zone, with the date unless it is today.
  def ob_log_time(time)
    time = ob_local(time)
    clock = time.strftime('%H:%M:%S.%L')
    time.to_date == User.current.today ? clock : "#{format_date(time)} #{clock}"
  end
end
