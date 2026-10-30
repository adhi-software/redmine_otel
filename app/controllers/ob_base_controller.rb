# frozen_string_literal: true

# Shared by the Traces, Logs and Metrics tabs of Administration > Redmine Observability;
# each subclass lists its filter form's parameters in FILTERS.
class ObBaseController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin

  helper :sort
  include SortHelper
  helper :ob_traces

  # Period filter lookbacks; 'custom' uses the From and To dates.
  PERIODS = {
    '1h' => 1.hour, '2h' => 2.hours, '6h' => 6.hours, '12h' => 12.hours,
    '24h' => 24.hours, '2d' => 2.days, '7d' => 7.days
  }.freeze

  TRACE_ID = /\A\h{32}\z/

  helper_method :filter_params

  private

  # Query parameters of the filter form, kept when deleting the listed rows.
  def filter_params
    request.query_parameters.slice(*self.class::FILTERS).compact_blank
  end

  # [from, to] of the period filter, either may be nil; custom dates are whole days in the user's zone.
  def period_range(period = params[:period])
    return [PERIODS[period]&.ago, nil] unless period == 'custom'

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
end
