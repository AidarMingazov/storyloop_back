module Ai
  module Image
    # One generated picture, already downloaded: attach with record.image.attach(io:, filename:, content_type:).
    Generated = Data.define(:io, :content_type, :filename) do
      def to_attachable = { io:, filename:, content_type: }
    end

    Result = Data.define(:images, :usage, :cost_usd, :duration_ms, :provider, :model) do
      def image = images.first
    end
  end
end
