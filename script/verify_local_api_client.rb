#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "socket"
require "tempfile"
require "timeout"
require_relative "../lib/tokenbar_cli/local_api_client"

responses = [
  [401, { "error" => "unauthorized" }],
  [200, { "status" => "ok" }],
  [200, { "accepted" => true }],
  [403, { "error" => "forbidden" }],
  [200, :invalid_json]
]
requests = []
server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]

server_thread = Thread.new do
  responses.each do |status, payload|
    socket = server.accept
    request_line = socket.gets.to_s.strip
    headers = {}
    while (line = socket.gets)
      line = line.strip
      break if line.empty?

      key, value = line.split(":", 2)
      headers[key.downcase] = value.to_s.strip
    end
    body = socket.read(headers.fetch("content-length", "0").to_i)
    requests << { "requestLine" => request_line, "headers" => headers, "body" => body }

    response_body = payload == :invalid_json ? "<html>not TokenBar</html>" : JSON.generate(payload)
    reason = status == 200 ? "OK" : status == 401 ? "Unauthorized" : "Forbidden"
    socket.write(
      "HTTP/1.1 #{status} #{reason}\r\n" \
      "Content-Type: application/json\r\n" \
      "Content-Length: #{response_body.bytesize}\r\n" \
      "Connection: close\r\n\r\n" \
      "#{response_body}"
    )
    socket.close
  end
ensure
  server.close
end

Tempfile.create("tokenbar-api-token") do |token_file|
  token_file.write("good-token\n")
  token_file.flush
  get_client = TokenBarCLI::LocalAPIClient.new(
    "http://127.0.0.1:#{port}/ignored?stale=true",
    token_paths: [Pathname.new(token_file.path)],
    env: { "TOKENBAR_API_TOKEN" => "bad-token" }
  )
  health = get_client.get("/health")
  unless health == { "status" => "ok" } && get_client.last_error.nil?
    warn "Local API GET/auth retry regression: response=#{health.inspect} error=#{get_client.last_error.inspect}"
    exit 1
  end
end

post_client = TokenBarCLI::LocalAPIClient.new(
  "http://127.0.0.1:#{port}",
  token_paths: [],
  env: { "TOKENBAR_API_TOKEN" => "good-token" }
)
posted = post_client.post("/policy/evaluate", { "workspaceID" => "client-smoke" })
unless posted == { "accepted" => true } && post_client.last_error.nil?
  warn "Local API POST regression: response=#{posted.inspect} error=#{post_client.last_error.inspect}"
  exit 1
end

forbidden_client = TokenBarCLI::LocalAPIClient.new(
  "http://127.0.0.1:#{port}",
  token_paths: [],
  env: { "TOKENBAR_API_TOKEN" => "good-token" }
)
forbidden = forbidden_client.get("/policy")
unless forbidden.nil? && forbidden_client.last_error == "http_403" &&
       forbidden_client.failure_message("policy checks require the app API").include?("request origin or authorization")
  warn "Local API failure mapping regression: response=#{forbidden.inspect} error=#{forbidden_client.last_error.inspect}"
  exit 1
end

invalid_json_client = TokenBarCLI::LocalAPIClient.new(
  "http://127.0.0.1:#{port}",
  token_paths: [],
  env: {}
)
invalid_json = invalid_json_client.get("/health")
unless invalid_json.nil? && invalid_json_client.last_error == "invalid_json" &&
       invalid_json_client.failure_message("check the configured endpoint").include?("returned invalid JSON")
  warn "Local API invalid JSON regression: response=#{invalid_json.inspect} error=#{invalid_json_client.last_error.inspect}"
  exit 1
end

begin
  TokenBarCLI::LocalAPIClient.new("127.0.0.1:3847", token_paths: [], env: {})
  warn "Local API URL validation regression: URL without scheme was accepted"
  exit 1
rescue ArgumentError => e
  raise unless e.message.include?("absolute http:// or https://")
end

Timeout.timeout(5) { server_thread.join }

unless requests[0].dig("headers", "authorization") == "Bearer bad-token" &&
       requests[1].dig("headers", "authorization") == "Bearer good-token" &&
       requests[1]["requestLine"] == "GET /ignored/health HTTP/1.1" &&
       requests[2].dig("headers", "content-type") == "application/json" &&
       JSON.parse(requests[2]["body"]) == { "workspaceID" => "client-smoke" }
  warn "Local API request contract regression: #{requests.inspect}"
  exit 1
end

puts "Verified Local API JSON transport, token retry, endpoint framing, and failure mapping."
