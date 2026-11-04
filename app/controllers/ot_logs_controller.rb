# frozen_string_literal: true

# Logs tab: log lines saved by DatabaseLogExporter.
class OtLogsController < OtBaseController
  menu_item :ot_traces
  helper :ot_logs

  FILTERS = %w[level q period from to].freeze

  def index
    sort_init 'logged_at', 'desc'
    sort_update 'logged_at' => %w[logged_at id]

    scope = filtered_logs
    @log_count = scope.count
    @log_pages = Paginator.new @log_count, per_page_option, params['page']
    @logs = scope.reorder(sort_clause).limit(@log_pages.per_page).offset(@log_pages.offset).to_a
    @stored_traces = OtSpan.where(trace_id: @logs.filter_map(&:trace_id).uniq).distinct.pluck(:trace_id).to_set
  end

  def destroy_all
    count = filtered_logs.in_batches(of: 10_000).delete_all
    flash[:notice] = l(:notice_ot_logs_deleted, count: count)
    redirect_to ot_logs_path(filter_params)
  end

  private

  def filtered_logs
    scope = OtLog.all
    lowest = RedmineOpentelemetry::LOG_LEVELS[params[:level]]
    scope = scope.where(severity_number: lowest..) if lowest
    from, to = period_range
    scope = scope.where(logged_at: from..to) if from || to
    q = params[:q].to_s.strip
    if q.match?(TRACE_ID)
      scope = scope.where(trace_id: q.downcase)
    elsif q.present?
      pattern = "%#{OtLog.sanitize_sql_like(q)}%"
      scope = scope.where(OtLog.arel_table[:body].matches(pattern))
    end
    scope
  end
end
