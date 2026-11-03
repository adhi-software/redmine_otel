# frozen_string_literal: true

# Traces tab: spans saved by DatabaseExporter.
class OtTracesController < OtBaseController
  menu_item :ot_traces

  # Microseconds per duration unit; a bare number is ms.
  DURATION_UNITS = { 'us' => 1, 'µs' => 1, 'ms' => 1000, 's' => 1_000_000, 'm' => 60_000_000 }.freeze

  FILTERS = %w[type q period from to min_duration max_duration errors].freeze

  def index
    sort_init 'started_at', 'desc'
    sort_update 'started_at' => 'started_at', 'name' => 'name', 'status' => 'http_status', 'duration' => 'duration_us'

    scope = filtered_roots
    @trace_count = scope.count
    @trace_pages = Paginator.new @trace_count, per_page_option, params['page']
    @traces = scope.reorder(sort_clause).limit(@trace_pages.per_page).offset(@trace_pages.offset).to_a
    spans = OtSpan.where(trace_id: @traces.map(&:trace_id))
    @span_counts = spans.group(:trace_id).count
    @error_counts = spans.where(error: true).or(spans.where(http_status: 500..)).group(:trace_id).count
  end

  def show
    spans = OtSpan.where(trace_id: params[:id]).order(:started_at, :id).to_a
    return render_404 if spans.empty?

    @rows = OtSpan.waterfall(spans)
    @root = spans.find(&:root?) || @rows.first.first
    @started_at = spans.map(&:started_at).min
    @duration_us = ((spans.map(&:ended_at).max - @started_at) * 1_000_000).round
    @log_count = OtLog.where(trace_id: params[:id]).count
  end

  # Deletes the checked traces (ids[]), or without ids every trace matching the filters.
  def destroy_all
    scope = params.key?(:ids) ? OtSpan.roots.where(trace_id: Array(params[:ids]).grep(TRACE_ID)) : filtered_roots
    # Plucked first: MySQL cannot delete from ot_spans with a subquery on ot_spans.
    trace_ids = scope.pluck(:trace_id)
    trace_ids.each_slice(1000) { OtSpan.where(trace_id: _1).delete_all }
    flash[:notice] = l(:notice_ot_traces_deleted, count: trace_ids.size)
    redirect_to ot_traces_path(filter_params)
  end

  def destroy
    OtSpan.where(trace_id: params[:id]).delete_all
    flash[:notice] = l(:notice_successful_delete)
    redirect_to ot_traces_path
  end

  private

  def filtered_roots
    scope = OtSpan.roots
    scope = case params[:type]
            when 'other' then scope.where.not(kind: 'server')
            when 'all' then scope
            else scope.requests
            end
    from, to = period_range
    scope = scope.where(started_at: from..to) if from || to
    min_us = duration_param(:min_duration)
    max_us = duration_param(:max_duration)
    scope = scope.where(duration_us: min_us..) if min_us
    scope = scope.where(duration_us: ..max_us) if max_us
    scope = scope.where(error: true).or(scope.where(http_status: 500..)) if params[:errors] == '1'
    if params[:q].present?
      table = OtSpan.arel_table
      pattern = "%#{OtSpan.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.where(table[:name].matches(pattern).or(table[:target].matches(pattern)))
    end
    scope
  end

  def duration_param(name)
    match = params[name].to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*(us|µs|ms|s|m)?\z/i)
    return unless match

    (match[1].to_f * DURATION_UNITS[(match[2] || 'ms').downcase]).round
  end
end
