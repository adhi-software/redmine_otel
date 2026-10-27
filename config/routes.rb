get 'admin/observability/traces', to: 'ob_traces#index', as: 'ob_traces'
delete 'admin/observability/traces', to: 'ob_traces#destroy_all'
get 'admin/observability/traces/:id', to: 'ob_traces#show', as: 'ob_trace', id: /\h{32}/
delete 'admin/observability/traces/:id', to: 'ob_traces#destroy', id: /\h{32}/
