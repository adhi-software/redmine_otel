# frozen_string_literal: true

# Administration > Redmine Observability > Logs: log lines saved by DatabaseLogExporter.
class ObLogsController < ObBaseController
  menu_item :ob_traces
  helper :ob_logs

  FILTERS = %w[level q period from to trace_id].freeze

  def index
    sort_init 'logged_at', 'desc'
    sort_update 'logged_at' => %w[logged_at id]

    scope = filtered_logs
    @log_count = scope.count
    @log_pages = Paginator.new @log_count, per_page_option, params['page']
    @logs = scope.reorder(sort_clause).limit(@log_pages.per_page).offset(@log_pages.offset).to_a
    # Traces saved for these lines; a line's request is not stored while "Store traces" is off.
    @stored_traces = ObSpan.where(trace_id: @logs.filter_map(&:trace_id).uniq).distinct.pluck(:trace_id).to_set
  end

  # Deletes every log line matching the filters, on all pages.
  def destroy_all
    count = filtered_logs.in_batches(of: 10_000).delete_all
    flash[:notice] = l(:notice_ob_logs_deleted, count: count)
    redirect_to ob_logs_path(filter_params)
  end

  private

  def filtered_logs
    scope = ObLog.all
    lowest = RedmineObservability::LOG_LEVELS[params[:level]]
    scope = scope.where(severity_number: lowest..) if lowest
    from, to = period_range
    scope = scope.where(logged_at: from..to) if from || to
    scope = scope.where(trace_id: params[:trace_id]) if params[:trace_id].to_s.match?(TRACE_ID)
    if params[:q].present?
      pattern = "%#{ObLog.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.where(ObLog.arel_table[:body].matches(pattern))
    end
    scope
  end
end
