# Start and Stop buttons for the viewers listed under Server hosting on the
# plugin settings page. Both redirect back to that page.
class ObservabilityViewersController < ApplicationController
  before_action :require_admin
  before_action :find_viewer

  def start
    problem = RedmineObservability::Viewers.missing_requirement(@viewer)
    if problem
      flash[:error] = problem
    else
      RedmineObservability::Viewers.start_in_background(@viewer) if RedmineObservability::Viewers.status(@viewer) == :stopped
      flash[:notice] = l(:notice_observability_viewer_starting, viewer: @viewer.label)
    end
    redirect_to plugin_settings_path('redmine_observability')
  end

  def stop
    RedmineObservability::Viewers.stop(@viewer)
    flash[:notice] = l(:notice_observability_viewer_stopped, viewer: @viewer.label)
    redirect_to plugin_settings_path('redmine_observability')
  end

  private

  def find_viewer
    @viewer = RedmineObservability::Viewers::ALL[params[:id]] or render_404
  end
end
