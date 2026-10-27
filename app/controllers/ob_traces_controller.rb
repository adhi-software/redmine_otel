# Administration > Traces: spans saved by DatabaseExporter.
class ObTracesController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :ob_traces

  before_action :require_admin

  helper :sort
  include SortHelper
  helper :ob_traces

  # Period filter lookbacks; 'custom' uses the From and To dates.
  PERIODS = {
    '1h' => 1.hour, '2h' => 2.hours, '6h' => 6.hours, '12h' => 12.hours,
    '24h' => 24.hours, '2d' => 2.days, '7d' => 7.days
  }.freeze

  # Microseconds per duration unit, as in 1.2s or 100ms; a bare number is ms.
  DURATION_UNITS = { 'us' => 1, 'µs' => 1, 'ms' => 1000, 's' => 1_000_000, 'm' => 60_000_000 }.freeze

  # Query parameters of the filter form, kept when deleting the listed traces.
  FILTERS = %w[type q period from to min_duration max_duration errors].freeze

  helper_method :filter_params

  def index
    sort_init 'started_at', 'desc'
    sort_update 'started_at' => 'started_at', 'name' => 'name', 'status' => 'http_status', 'duration' => 'duration_us'

    scope = filtered_roots
    @trace_count = scope.count
    @trace_pages = Paginator.new @trace_count, per_page_option, params['page']
    @traces = scope.reorder(sort_clause).limit(@trace_pages.per_page).offset(@trace_pages.offset).to_a
    spans = ObSpan.where(trace_id: @traces.map(&:trace_id))
    @span_counts = spans.group(:trace_id).count
    @error_counts = spans.where(error: true).or(spans.where(http_status: 500..)).group(:trace_id).count
  end

  def show
    spans = ObSpan.where(trace_id: params[:id]).order(:started_at, :id).to_a
    return render_404 if spans.empty?

    @rows = ObSpan.waterfall(spans)
    @root = spans.find(&:root?) || @rows.first.first
    @started_at = spans.map(&:started_at).min
    @duration_us = ((spans.map(&:ended_at).max - @started_at) * 1_000_000).round
  end

  # Deletes every trace matching the filters, on all pages, with all of its spans.
  def destroy_all
    trace_ids = filtered_roots.pluck(:trace_id)
    # Plucked first: MySQL cannot delete from ob_spans with a subquery on ob_spans.
    trace_ids.each_slice(1000) { ObSpan.where(trace_id: _1).delete_all }
    flash[:notice] = l(:notice_ob_traces_deleted, count: trace_ids.size)
    redirect_to ob_traces_path(filter_params)
  end

  def destroy
    ObSpan.where(trace_id: params[:id]).delete_all
    flash[:notice] = l(:notice_successful_delete)
    redirect_to ob_traces_path
  end

  private

  def filter_params
    request.query_parameters.slice(*FILTERS).compact_blank
  end

  def filtered_roots
    scope = ObSpan.roots
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
      table = ObSpan.arel_table
      pattern = "%#{ObSpan.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.where(table[:name].matches(pattern).or(table[:target].matches(pattern)))
    end
    scope
  end

  # [from, to] of the period filter, either may be nil; custom dates are whole days in the user's zone.
  def period_range
    return [PERIODS[params[:period]]&.ago, nil] unless params[:period] == 'custom'

    zone = User.current.time_zone || Time.zone
    from = date_param(:from)&.in_time_zone(zone)
    to = date_param(:to)&.in_time_zone(zone)&.end_of_day
    from, to = to.beginning_of_day, from.end_of_day if from && to && from > to
    [from, to]
  end

  def date_param(name)
    Date.iso8601(params[name].to_s)
  rescue ArgumentError
    nil
  end

  def duration_param(name)
    match = params[name].to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*(us|µs|ms|s|m)?\z/i)
    return unless match

    (match[1].to_f * DURATION_UNITS[(match[2] || 'ms').downcase]).round
  end
end
