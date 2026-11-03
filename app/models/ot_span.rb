# frozen_string_literal: true

# A span saved by DatabaseExporter.
class OtSpan < ApplicationRecord
  scope :roots, -> { where(root: true) }
  scope :requests, -> { where(kind: 'server') }

  # [span, depth] pairs, each after its parent; orphans start at depth 0.
  def self.waterfall(spans)
    ids = spans.index_by(&:span_id)
    children = spans.group_by { ids.key?(_1.parent_span_id) ? _1.parent_span_id : nil }
    rows = []
    walk = lambda do |parent_id, depth|
      Array(children[parent_id]).each do |span|
        rows << [span, depth]
        walk.call(span.span_id, depth + 1)
      end
    end
    walk.call(nil, 0)
    rows
  end

  def span_attributes = parsed_details['attributes'] || {}

  def events = parsed_details['events'] || []

  def status_message = parsed_details['status']

  def failed? = error? || http_status.to_i >= 500

  def category
    return 'request' if kind == 'server'
    return 'sql' if span_attributes.key?('db.system') || span_attributes.key?('db.system.name')
    return 'http' if kind == 'client'

    'internal'
  end

  def ended_at = started_at + duration_us / 1_000_000r

  private

  def parsed_details
    @parsed_details ||= JSON.parse(details.presence || '{}')
  rescue JSON::ParserError
    @parsed_details = {}
  end
end
