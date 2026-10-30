# frozen_string_literal: true

get 'admin/observability/traces', to: 'ob_traces#index', as: 'ob_traces'
delete 'admin/observability/traces', to: 'ob_traces#destroy_all'
get 'admin/observability/traces/:id', to: 'ob_traces#show', as: 'ob_trace', id: /\h{32}/
delete 'admin/observability/traces/:id', to: 'ob_traces#destroy', id: /\h{32}/
get 'admin/observability/logs', to: 'ob_logs#index', as: 'ob_logs'
delete 'admin/observability/logs', to: 'ob_logs#destroy_all'
get 'admin/observability/metrics', to: 'ob_metrics#index', as: 'ob_metrics'
delete 'admin/observability/metrics', to: 'ob_metrics#destroy_all'
