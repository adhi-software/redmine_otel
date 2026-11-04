# frozen_string_literal: true

# Metrics tab: points saved by DatabaseMetricExporter, charted in buckets of time and broken down by series.
class OtMetricsController < OtBaseController
  menu_item :ot_traces
  helper :ot_metrics

  FILTERS = %w[name q period from to].freeze

  DEFAULT_METRIC = 'http.server.request.duration'
  DEFAULT_PERIOD = '6h'
  # Bucket sizes in minutes; the chart uses the smallest that gives at most MAX_BUCKETS points.
  BUCKET_SIZES = [1, 5, 10, 15, 30, 60, 120, 240, 360, 720, 1440, 10_080].freeze
  MAX_BUCKETS = 120
  MAX_SERIES = 100

  def index
    @names = OtMetric.distinct.order(:name).pluck(:name)
    @name = [params[:name], DEFAULT_METRIC, @names.first].find { @names.include?(_1) }
    @period = params.fetch(:period, DEFAULT_PERIOD)
    return unless @name

    @latest = OtMetric.where(name: @name).order(recorded_at: :desc).first
    @shape = @latest.shape
    scope = filtered_points(@name)
    return unless scope.exists?

    @from, @to = chart_range(scope)
    @bucket_size = BUCKET_SIZES.find { (@to - @from) / 60 / _1 <= MAX_BUCKETS } || BUCKET_SIZES.last
    @summary = OtMetric::Summary.new(*scope.pick(*OtMetric.summary_columns))
    @points = chart_points(scope)
    series = scope.group(:series).pluck(:series, *OtMetric.summary_columns).map { [_1.first, OtMetric::Summary.new(*_1.drop(1))] }
    @series_count = series.size
    @series = series.sort_by { |_, summary| -rank(summary) }.first(MAX_SERIES)
  end

  def destroy_all
    scope = filtered_points(params[:name].to_s)
    scope = scope.where(series: Array(params[:ids])) if params.key?(:ids)
    count = scope.in_batches(of: 10_000).delete_all
    flash[:notice] = l(:notice_ot_metrics_deleted, count: count)
    redirect_to ot_metrics_path(filter_params)
  end

  private

  # Keeps the metric and a blank period, which a missing one would turn into DEFAULT_PERIOD.
  def filter_params
    super.merge('name' => @name || params[:name], 'period' => params.fetch(:period, DEFAULT_PERIOD)).compact
  end

  def filtered_points(name)
    scope = OtMetric.where(name: name)
    params[:q].to_s.split.each do |word|
      scope = scope.where(OtMetric.arel_table[:series].matches("%#{OtMetric.sanitize_sql_like(word)}%"))
    end
    from, to = period_range(params.fetch(:period, DEFAULT_PERIOD))
    scope = scope.where(recorded_at: from..to) if from || to
    scope
  end

  def chart_range(scope)
    from, to = period_range(@period)
    now = Time.current
    [from || scope.minimum(:recorded_at), [to || now, now].min]
  end

  def chart_points(scope)
    bucket = OtMetric.bucket_column(@bucket_size)
    rows = scope.group(bucket).pluck(bucket, *OtMetric.summary_columns)
                .to_h { [_1.first.to_i, OtMetric::Summary.new(*_1.drop(1))] }
    first = @from.to_i / 60 / @bucket_size * @bucket_size
    last = @to.to_i / 60 / @bucket_size * @bucket_size
    (first..last).step(@bucket_size).map do |minute|
      summary = rows[minute] || OtMetric::Summary.new
      { x: minute * 60_000, count: summary.samples.to_i, total: summary.total.to_f,
        average: summary.average(@shape), max: summary.maximum(@shape) }
    end
  end

  def rank(summary)
    case @shape
    when :histogram then summary.samples.to_i
    when :sum then summary.total.to_f.abs
    else summary.peak.to_f
    end
  end
end
