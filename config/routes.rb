# frozen_string_literal: true

get 'admin/opentelemetry/traces', to: 'ot_traces#index', as: 'ot_traces'
delete 'admin/opentelemetry/traces', to: 'ot_traces#destroy_all'
get 'admin/opentelemetry/traces/:id', to: 'ot_traces#show', as: 'ot_trace', id: /\h{32}/
delete 'admin/opentelemetry/traces/:id', to: 'ot_traces#destroy', id: /\h{32}/
get 'admin/opentelemetry/logs', to: 'ot_logs#index', as: 'ot_logs'
delete 'admin/opentelemetry/logs', to: 'ot_logs#destroy_all'
get 'admin/opentelemetry/metrics', to: 'ot_metrics#index', as: 'ot_metrics'
delete 'admin/opentelemetry/metrics', to: 'ot_metrics#destroy_all'
