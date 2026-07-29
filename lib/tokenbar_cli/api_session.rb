# frozen_string_literal: true

module TokenBarCLI
  class ApiSession
    Result = Struct.new(:body, :client, keyword_init: true) do
      def error
        client.last_error
      end

      def failure_message(action)
        client.failure_message(action)
      end
    end

    attr_reader :api_url

    def initialize(api_url, token_paths:, client_factory: LocalAPIClient.method(:new))
      @api_url = api_url
      @client = client_factory.call(api_url, token_paths: token_paths)
    end

    def get(path)
      Result.new(body: @client.get(path), client: @client)
    end

    def post(path, input)
      Result.new(body: @client.post(path, input), client: @client)
    end
  end
end
