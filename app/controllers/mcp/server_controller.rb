# frozen_string_literal: true

module Mcp
  class ServerController < BaseController
    PROTOCOL_VERSION = "2025-06-18"
    SERVER_NAME = "lievik"
    SERVER_VERSION = "0.1.0"

    JSONRPC_PARSE_ERROR = -32700
    JSONRPC_INVALID_REQUEST = -32600
    JSONRPC_METHOD_NOT_FOUND = -32601
    JSONRPC_INVALID_PARAMS = -32602
    JSONRPC_INTERNAL_ERROR = -32603
    APP_ERROR = -32000

    TOOL_REGISTRY = {
      "list_channels" => Mcp::Tools::ListChannels,
      "list_events" => Mcp::Tools::ListEvents,
      "list_channel_events" => Mcp::Tools::ListChannelEvents,
      "get_event" => Mcp::Tools::GetEvent,
      "search_events" => Mcp::Tools::SearchEvents,
      "mark_event_used" => Mcp::Tools::MarkEventUsed,
      "mark_event_unused" => Mcp::Tools::MarkEventUnused,
      "add_manual_event" => Mcp::Tools::AddManualEvent,
      "refresh_source" => Mcp::Tools::RefreshSource,
      "rate_channel" => Mcp::Tools::RateChannel
    }.freeze

    def handle
      payload = parse_request
      return if performed?

      if payload.is_a?(Array)
        responses = payload.map { |req| handle_request(req) }.compact
        render json: responses
      else
        response = handle_request(payload)
        if response.nil?
          head :no_content
        else
          render json: response
        end
      end
    end

    private

    def parse_request
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      render json: jsonrpc_error(nil, JSONRPC_PARSE_ERROR, "Parse error")
      nil
    end

    def handle_request(req)
      unless req.is_a?(Hash) && req["jsonrpc"] == "2.0" && req["method"].is_a?(String)
        return jsonrpc_error(req.is_a?(Hash) ? req["id"] : nil, JSONRPC_INVALID_REQUEST, "Invalid Request")
      end

      id = req["id"]
      method = req["method"]
      params = req["params"] || {}

      result =
        case method
        when "initialize" then initialize_result
        when "notifications/initialized", "notifications/cancelled" then :no_response
        when "ping" then {}
        when "tools/list" then tools_list_result
        when "tools/call" then tools_call_result(params)
        else
          return jsonrpc_error(id, JSONRPC_METHOD_NOT_FOUND, "Method not found: #{method}")
        end

      return nil if result == :no_response
      return nil if id.nil? # notification

      { jsonrpc: "2.0", id: id, result: result }
    rescue Mcp::Tools::Base::InvalidParams => e
      jsonrpc_error(id, JSONRPC_INVALID_PARAMS, e.message)
    rescue Mcp::Tools::Base::AppError => e
      jsonrpc_error(id, APP_ERROR, e.message)
    rescue ActiveRecord::RecordNotFound => e
      jsonrpc_error(id, APP_ERROR, e.message)
    rescue => e
      Rails.logger.error("[MCP] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      jsonrpc_error(id, JSONRPC_INTERNAL_ERROR, "Internal error")
    end

    def initialize_result
      {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION }
      }
    end

    def tools_list_result
      tools = TOOL_REGISTRY.map do |name, klass|
        {
          name: name,
          description: klass.description,
          inputSchema: klass.input_schema
        }
      end
      { tools: tools }
    end

    def tools_call_result(params)
      name = params["name"]
      args = params["arguments"] || {}
      klass = TOOL_REGISTRY[name]
      raise Mcp::Tools::Base::InvalidParams, "Unknown tool: #{name}" unless klass

      result = klass.new(current_user, args).call
      {
        content: [
          { type: "text", text: JSON.pretty_generate(result) }
        ],
        structuredContent: result,
        isError: false
      }
    end

    def jsonrpc_error(id, code, message, data = nil)
      err = { code: code, message: message }
      err[:data] = data if data
      { jsonrpc: "2.0", id: id, error: err }
    end
  end
end
