require "net/http"

module Ai
  # JSON over HTTPS with timeouts and retries (429 / 5xx / network errors, exponential backoff or Retry-After).
  # The transport is injectable so adapter tests run without network:
  #   Ai::Http.new(provider: "deepseek", transport: ->(request) { Ai::Http::Response.new(...) })
  class Http
    Request = Data.define(:method, :url, :headers, :body, :timeout)
    Response = Data.define(:status, :body, :headers)

    RETRY_STATUSES = [ 408, 409, 425, 429, 500, 502, 503, 504, 529 ].freeze
    NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
                       Errno::EPIPE, EOFError, IOError, OpenSSL::SSL::SSLError, SocketError ].freeze
    MAX_BACKOFF = 30

    NET_HTTP = lambda do |request|
      uri = URI(request.url)
      klass = request.method == :post ? Net::HTTP::Post : Net::HTTP::Get
      http_request = klass.new(uri, request.headers)
      http_request.body = request.body if request.body
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 15, read_timeout: request.timeout, write_timeout: 60) do |http|
        response = http.request(http_request)
        Response.new(status: response.code.to_i, body: response.body.to_s, headers: response.to_hash)
      end
    end

    attr_reader :provider

    def initialize(provider:, transport: NET_HTTP, retries: 2, sleeper: ->(seconds) { sleep(seconds) })
      @provider = provider
      @transport = transport
      @retries = retries
      @sleeper = sleeper
    end

    def post_json(url, payload, headers: {}, timeout: 120)
      headers = { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
      parse(perform(Request.new(method: :post, url:, headers:, body: JSON.generate(payload), timeout:)))
    end

    # Raw bytes (generated images and audio are downloaded right away: provider URLs expire).
    # For adapters whose provider reports rate limits inside a 200 response (MiniMax).
    def pause(seconds) = @sleeper.call(seconds)

    def get(url, timeout: 120)
      perform(Request.new(method: :get, url:, headers: {}, body: nil, timeout:)).body
    end

    private

    def perform(request)
      (0..@retries).each do |attempt|
        last_attempt = attempt == @retries
        begin
          response = @transport.call(request)
        rescue *NETWORK_ERRORS => e
          raise ProviderError.new("#{provider}: #{e.class}: #{e.message}", provider:) if last_attempt

          @sleeper.call(2**attempt)
          next
        end

        return response if (200..299).cover?(response.status)
        raise error_for(response) if last_attempt || !RETRY_STATUSES.include?(response.status)

        @sleeper.call(backoff(attempt, response))
      end
    end

    def backoff(attempt, response)
      retry_after = Array(response.headers&.fetch("retry-after", nil)).first.to_i
      retry_after.positive? ? [ retry_after, MAX_BACKOFF ].min : 2**attempt
    end

    def error_for(response)
      klass = case response.status
      when 401, 403 then Unauthorized
      when 402 then InsufficientBalance
      when 429 then RateLimited
      else ProviderError
      end
      klass.new("#{provider}: HTTP #{response.status}: #{response.body.to_s[0, 500]}",
                provider:, status: response.status, body: response.body.to_s[0, 2000])
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise InvalidResponse.new("#{provider}: response is not JSON: #{response.body.to_s[0, 200]}",
                                provider:, status: response.status, body: response.body.to_s[0, 2000])
    end
  end
end
