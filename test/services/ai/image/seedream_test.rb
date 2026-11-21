require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"

class Ai::Image::SeedreamTest < ActiveSupport::TestCase
  include AiTestHelper

  JPEG = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00".b + ("\x00".b * 64)

  def adapter(transport, model: "seedream-4-5-251128")
    Ai::Image::Seedream.new(provider: "seedream", model:, settings: Ai.config.provider("seedream"),
                            api_key: "ark-test", http: ai_http(transport, provider: "seedream"))
  end

  def generated(url: "https://ark-cdn.test/1.jpeg")
    json_response({ "model" => "seedream-4-5-251128", "data" => [ { "url" => url } ],
                    "usage" => { "generated_images" => 1, "output_tokens" => 14_580 } })
  end

  test "text-to-image: request shape, download, usage and price" do
    transport = FakeTransport.new(generated, raw_response(JPEG))
    result = adapter(transport).generate(prompt: "Seoul street, no text", size: "1728x2160")

    body = transport.json_body(0)
    assert_equal "https://ark.ap-southeast.bytepluses.com/api/v3/images/generations", transport.requests[0].url
    assert_equal({ "model" => "seedream-4-5-251128", "prompt" => "Seoul street, no text", "size" => "1728x2160",
                   "response_format" => "url", "watermark" => false }, body)
    assert_equal "https://ark-cdn.test/1.jpeg", transport.requests[1].url

    image = result.image
    assert_equal "image/jpeg", image.content_type
    assert_equal "image-1.jpg", image.filename
    assert_equal JPEG, image.io.read
    assert_equal 1, result.usage.images
    assert_in_delta 0.04, result.cost_usd
  end

  test "one reference is a string, several are an array; paid references are priced" do
    sheet = StringIO.new(JPEG)
    transport = FakeTransport.new(generated, raw_response(JPEG), generated, raw_response(JPEG))

    adapter(transport).generate(prompt: "x", references: [ sheet ])
    assert_kind_of String, transport.json_body(0)["image"]
    assert_match %r{\Adata:image/jpeg;base64,}, transport.json_body(0)["image"]

    result = adapter(transport, model: "dola-seedream-5-0-pro-260628")
      .generate(prompt: "x", references: [ sheet, "https://cdn.test/place.jpg", StringIO.new(JPEG) ])
    assert_equal 3, transport.json_body(2)["image"].size
    assert_equal "https://cdn.test/place.jpg", transport.json_body(2)["image"][1]
    assert_in_delta 0.045 + (2 * 0.003), result.cost_usd # first reference is free on 5.0-pro
  end

  test "base64 answers need no download" do
    transport = FakeTransport.new(json_response({ "data" => [ { "b64_json" => Base64.strict_encode64(JPEG) } ] }))

    assert_equal JPEG, adapter(transport).generate(prompt: "x").image.io.read
    assert_equal 1, transport.requests.size
  end

  test "safety filter rejection is ContentRejected" do
    body = { "error" => { "code" => "InputImageSensitiveContentDetected", "message" => "The request failed because the input image may contain sensitive information." } }
    transport = FakeTransport.new(json_response(body, status: 400))

    error = assert_raises(Ai::ContentRejected) { adapter(transport).generate(prompt: "x", references: [ StringIO.new(JPEG) ]) }
    assert_equal 400, error.status
  end

  test "other errors stay ProviderError; empty data is InvalidResponse" do
    transport = FakeTransport.new(json_response({ "error" => { "code" => "InvalidParameter" } }, status: 400),
                                  json_response({ "data" => [] }))

    error = assert_raises(Ai::ProviderError) { adapter(transport).generate(prompt: "x") }
    assert_not_kind_of Ai::ContentRejected, error
    assert_raises(Ai::InvalidResponse) { adapter(transport).generate(prompt: "x") }
  end
end
