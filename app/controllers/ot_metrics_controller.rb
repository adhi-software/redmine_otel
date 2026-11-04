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
  PERCENTILES = [50, 95, 99].freeze
  MAX_PERCENTILE_POINTS = 100_000
  STATUS = 'http.response.status_code'

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
    series = scope.group(:series).pluck(:series, *OtMetric.summary_columns).map { [_1.first, OtMetric::Summary.new(*_1.drop(1))] }
    @series_count = series.size
    @series = series.sort_by { |_, summary| -rank(summary) }.first(MAX_SERIES)
    if @shape == :histogram
      @percentiles_skipped = scope.count > MAX_PERCENTILE_POINTS
      histograms = histograms(scope) unless @percentiles_skipped
      errors = errors(scope, series.map(&:first))
    end
    @points = chart_points(scope, histograms, errors)
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

  def histograms(scope)
    bucket = OtMetric.bucket_column(@bucket_size)
    all = OtMetric::Histogram.new
    by_minute = Hash.new { |hash, minute| hash[minute] = OtMetric::Histogram.new }
    by_series = Hash.new { |hash, series| hash[series] = OtMetric::Histogram.new }
    scope.pluck(bucket, :series, :max, :details).each do |minute, series, max, details|
      bounds, counts = OtMetric.buckets(details)
      next unless bounds

      [all, by_minute[minute.to_i], by_series[series]].each { _1.add(bounds, counts, max) }
    end
    return if all.empty?

    @percentiles = all.percentiles(PERCENTILES)
    @series_percentiles = Hash.new(PERCENTILES.index_with(nil))
    by_series.each { |series, histogram| @series_percentiles[series] = histogram.percentiles(PERCENTILES) }
    by_minute
  end

  def errors(scope, series)
    return unless series.any? { OtMetric.labels(_1).key?(STATUS) }

    failed = series.select { OtMetric.labels(_1)[STATUS].to_i >= 500 }
    bucket = OtMetric.bucket_column(@bucket_size)
    by_minute = failed.empty? ? {} : scope.where(series: failed).group(bucket).sum(:count).to_h { [_1.to_i, _2.to_i] }
    @error_rate = by_minute.values.sum.to_f / @summary.samples.to_i if @summary.samples.to_i.positive?
    by_minute
  end

  def chart_points(scope, histograms, errors)
    bucket = OtMetric.bucket_column(@bucket_size)
    rows = scope.group(bucket).pluck(bucket, *OtMetric.summary_columns)
                .to_h { [_1.first.to_i, OtMetric::Summary.new(*_1.drop(1))] }
    first = @from.to_i / 60 / @bucket_size * @bucket_size
    last = @to.to_i / 60 / @bucket_size * @bucket_size
    (first..last).step(@bucket_size).map do |minute|
      summary = rows[minute] || OtMetric::Summary.new
      point = { x: minute * 60_000, average: summary.average(@shape), max: summary.maximum(@shape) }
      case @shape
      when :histogram then point[:rate] = summary.samples.to_f / @bucket_size
      when :sum then point[:rate] = summary.total.to_f / @bucket_size
      else point[:min] = summary.minimum
      end
      point[:errors] = errors[minute].to_f / @bucket_size if errors
      histogram = histograms&.fetch(minute, nil)
      PERCENTILES.each { point[:"p#{_1}"] = histogram&.percentile(_1) } if @percentiles
      point
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
