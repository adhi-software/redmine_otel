# frozen_string_literal: true

# Administration > Redmine Observability > Metrics: points saved by DatabaseMetricExporter,
# charted in buckets of time and broken down by series.
class ObMetricsController < ObBaseController
  menu_item :ob_traces
  helper :ob_metrics

  FILTERS = %w[name series period from to].freeze

  DEFAULT_METRIC = 'http.server.request.duration'
  DEFAULT_PERIOD = '6h'
  # Bucket sizes in minutes; the chart uses the smallest that gives at most MAX_BUCKETS points.
  BUCKET_SIZES = [1, 5, 10, 15, 30, 60, 120, 240, 360, 720, 1440, 10_080].freeze
  MAX_BUCKETS = 120
  # Most series listed under the chart, largest first.
  MAX_SERIES = 100

  def index
    @names = ObMetric.distinct.order(:name).pluck(:name)
    @name = [params[:name], DEFAULT_METRIC, @names.first].find { @names.include?(_1) }
    @period = params.fetch(:period, DEFAULT_PERIOD)
    return unless @name

    @latest = ObMetric.where(name: @name).order(recorded_at: :desc).first
    @shape = @latest.shape
    scope = filtered_points(@name)
    return unless scope.exists?

    @from, @to = chart_range(scope)
    @bucket_size = BUCKET_SIZES.find { (@to - @from) / 60 / _1 <= MAX_BUCKETS } || BUCKET_SIZES.last
    @summary = ObMetric::Summary.new(*scope.pick(*ObMetric.summary_columns))
    @points = chart_points(scope)
    series = scope.group(:series).pluck(:series, *ObMetric.summary_columns).map { [_1.first, ObMetric::Summary.new(*_1.drop(1))] }
    @series_count = series.size
    @series = series.sort_by { |_, summary| -rank(summary) }.first(MAX_SERIES)
  end

  # Deletes the selected metric's points matching the filters.
  def destroy_all
    count = filtered_points(params[:name].to_s).in_batches(of: 10_000).delete_all
    flash[:notice] = l(:notice_ob_metrics_deleted, count: count)
    redirect_to ob_metrics_path(filter_params)
  end

  private

  # Keeps the metric and a blank period, which a missing one would turn into DEFAULT_PERIOD.
  def filter_params
    super.merge('name' => @name || params[:name], 'period' => params.fetch(:period, DEFAULT_PERIOD)).compact
  end

  def filtered_points(name)
    scope = ObMetric.where(name: name)
    scope = scope.where(series: params[:series]) if params[:series].present?
    from, to = period_range(params.fetch(:period, DEFAULT_PERIOD))
    scope = scope.where(recorded_at: from..to) if from || to
    scope
  end

  # [from, to] of the chart: the period, from the first point for any time, ending by now.
  def chart_range(scope)
    from, to = period_range(@period)
    now = Time.current
    [from || scope.minimum(:recorded_at), [to || now, now].min]
  end

  # One point per bucket from the start of the range to now; empty buckets have no average.
  def chart_points(scope)
    bucket = ObMetric.bucket_column(@bucket_size)
    rows = scope.group(bucket).pluck(bucket, *ObMetric.summary_columns)
                .to_h { [_1.first.to_i, ObMetric::Summary.new(*_1.drop(1))] }
    first = @from.to_i / 60 / @bucket_size * @bucket_size
    last = @to.to_i / 60 / @bucket_size * @bucket_size
    (first..last).step(@bucket_size).map do |minute|
      summary = rows[minute] || ObMetric::Summary.new
      { x: minute * 60_000, count: summary.samples.to_i, total: summary.total.to_f,
        average: summary.average(@shape), max: summary.maximum(@shape) }
    end
  end

  # Orders the series: most measurements, largest total or highest reading first.
  def rank(summary)
    case @shape
    when :histogram then summary.samples.to_i
    when :sum then summary.total.to_f.abs
    else summary.peak.to_f
    end
  end
end
