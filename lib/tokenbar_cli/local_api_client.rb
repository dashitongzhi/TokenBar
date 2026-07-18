# frozen_string_literal: true

require "json"
require "net/http"
require "pathname"
require "uri"

module TokenBarCLI
  class LocalAPIClient
    attr_reader :last_error

    def initialize(api_url, token_paths:, env: ENV)
      @api_url = api_url
      @token_paths = token_paths
      @env = env
      @last_error = nil
    end

    def get(path)
      uri = endpoint(path)
      response = with_api_token do |token|
        http_request = Net::HTTP::Get.new(uri)
        apply_auth_token(http_request, token)
        perform_request(uri, http_request)
      end
      parse_success(response)
    end

    def post(path, input)
      uri = endpoint(path)
      body = JSON.generate(input)
      response = with_api_token do |token|
        http_request = Net::HTTP::Post.new(uri)
        http_request["Content-Type"] = "application/json"
        apply_auth_token(http_request, token)
        http_request.body = body
        perform_request(uri, http_request)
      end
      parse_success(response)
    end

    def failure_message(action)
      case last_error
      when "http_401"
        "TokenBar local API rejected the request; set TOKENBAR_API_TOKEN or TOKENBAR_API_TOKEN_PATH, or start TokenBar so one of these token paths is available: #{@token_paths.join(", ")}"
      when "http_403"
        "TokenBar local API rejected the request origin or authorization; #{action}"
      when "http_400"
        "TokenBar local API rejected the payload; #{action}"
      when "http_404", "http_405"
        "TokenBar local API route or method is not supported by the running app; #{action}"
      when /\Ahttp_(\d{3})\z/
        "TokenBar local API returned HTTP #{Regexp.last_match(1)}; #{action}"
      else
        "TokenBar app is not running; #{action}"
      end
    end

    private

    def parse_success(response)
      return nil unless response&.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      nil
    end

    def perform_request(uri, http_request)
      @last_error = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 0.5, read_timeout: 1.5) do |http|
        response = http.request(http_request)
        @last_error = "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)
        response
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout
      @last_error = "connection_failed"
      nil
    end

    def with_api_token
      response = nil
      api_tokens.each do |token|
        response = yield(token)
        return response unless response&.code == "401"
      end
      response
    end

    def apply_auth_token(request, token)
      request["Authorization"] = "Bearer #{token}" unless blank?(token)
    end

    def api_tokens
      tokens = []
      env_token = @env["TOKENBAR_API_TOKEN"]
      tokens << env_token.strip unless blank?(env_token)
      api_token_paths.each do |path|
        next unless path.file?

        token = path.read.strip
        tokens << token unless blank?(token)
      rescue SystemCallError
        next
      end
      tokens = tokens.uniq
      tokens.empty? ? [nil] : tokens
    end

    def api_token_paths
      explicit = @env["TOKENBAR_API_TOKEN_PATH"]
      paths = []
      paths << Pathname.new(explicit).expand_path unless blank?(explicit)
      (paths + @token_paths).uniq
    end

    def endpoint(path)
      base = URI(@api_url)
      base.path = path
      base.query = nil
      base
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
