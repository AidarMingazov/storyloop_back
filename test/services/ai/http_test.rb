require "test_helper"
require_relative "../../test_helpers/ai_test_helper"

class Ai::HttpTest < ActiveSupport::TestCase
  include AiTestHelper

  test "posts JSON with headers and parses the answer" do
    transport = FakeTransport.new(json_response({ "ok" => true }))
    body = ai_http(transport).post_json("https://api.test/v1/x", { a: 1 }, headers: { "Authorization" => "Bearer k" }, timeout: 9)

    assert_equal({ "ok" => true }, body)
    request = transport.requests.last
    assert_equal :post, request.method
    assert_equal "application/json", request.headers["Content-Type"]
    assert_equal "Bearer k", request.headers["Authorization"]
    assert_equal 9, request.timeout
    assert_equal({ "a" => 1 }, transport.json_body)
  end

  test "retries 429 using Retry-After, then succeeds" do
    transport = FakeTransport.new(raw_response("busy", status: 429, headers: { "retry-after" => [ "3" ] }),
                                  json_response({ "ok" => true }))

    assert_equal({ "ok" => true }, ai_http(transport).post_json("https://api.test", {}))
    assert_equal [ 3 ], sleeps
    assert_equal 2, transport.requests.size
  end

  test "retries 5xx with exponential backoff and gives up with ProviderError" do
    transport = FakeTransport.new(*Array.new(3) { raw_response("oops", status: 503) })

    error = assert_raises(Ai::ProviderError) { ai_http(transport, provider: "deepseek").post_json("https://api.test", {}) }
    assert_equal [ 1, 2 ], sleeps
    assert_equal 503, error.status
    assert_equal "deepseek", error.provider
    assert_match "HTTP 503", error.message
  end

  test "retries network errors" do
    transport = FakeTransport.new(Net::ReadTimeout.new, json_response({ "ok" => 1 }))

    assert_equal({ "ok" => 1 }, ai_http(transport).post_json("https://api.test", {}))
    assert_equal [ 1 ], sleeps
  end

  test "maps statuses to error classes without retrying and never leaks the key" do
    { 401 => Ai::Unauthorized, 402 => Ai::InsufficientBalance, 400 => Ai::ProviderError }.each do |status, klass|
      transport = FakeTransport.new(raw_response('{"error":"nope"}', status:))
      error = assert_raises(klass) do
        ai_http(transport).post_json("https://api.test", {}, headers: { "Authorization" => "Bearer secret-key" })
      end
      assert_equal 1, transport.requests.size
      assert_no_match "secret-key", error.message
    end
  end

  test "rate limit after all retries is RateLimited" do
    transport = FakeTransport.new(*Array.new(2) { raw_response("slow down", status: 429) })

    assert_raises(Ai::RateLimited) { ai_http(transport, retries: 1).post_json("https://api.test", {}) }
  end

  test "non-JSON body is InvalidResponse" do
    transport = FakeTransport.new(raw_response("<html>gateway</html>"))

    assert_raises(Ai::InvalidResponse) { ai_http(transport).post_json("https://api.test", {}) }
  end

  test "get returns raw bytes" do
    transport = FakeTransport.new(raw_response("\xFF\xD8bytes".b))

    assert_equal "\xFF\xD8bytes".b, ai_http(transport).get("https://cdn.test/a.jpg")
    assert_equal :get, transport.requests.last.method
  end
end
