# frozen_string_literal: true

# A log line saved by DatabaseLogExporter; trace_id links it to the request that logged it.
class ObLog < ApplicationRecord
  # Level name for colouring; 'unknown' below DEBUG.
  def level
    RedmineObservability::LOG_LEVELS.reverse_each.find { |_, number| severity_number >= number }&.first || 'unknown'
  end

  # First line of the message, shown in the list.
  def summary = body.to_s.lstrip.lines.first.to_s.strip.truncate(500)

  def multiline? = body.to_s.strip.include?("\n")

  def log_attributes = parsed_details['attributes'] || {}

  private

  def parsed_details
    @parsed_details ||= JSON.parse(details.presence || '{}')
  rescue JSON::ParserError
    @parsed_details = {}
  end
end
