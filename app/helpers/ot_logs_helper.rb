# frozen_string_literal: true

module OtLogsHelper
  def ot_level_options(value)
    levels = %w[info warn error].map { [l(:label_ot_level_at_least, level: l(:"label_ot_level_#{_1}")), _1] }
    options_for_select([[l(:label_ot_all_levels), '']] + levels, value)
  end

  def ot_log_sort_options(value)
    options_for_select([[l(:label_ot_most_recent), 'logged_at:desc'],
                        [l(:label_ot_oldest_first), 'logged_at']], value)
  end

  def ot_log_time(time)
    time = ot_local(time)
    clock = time.strftime('%H:%M:%S.%L')
    time.to_date == User.current.today ? clock : "#{format_date(time)} #{clock}"
  end
end
