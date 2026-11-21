module Ai
  # Turns an image source into something a provider accepts in JSON: http(s) and data: URLs pass through,
  # files / IO / Active Storage blobs and attachments become data URIs.
  module DataUri
    module_function

    def call(source)
      case source
      when String
        return source if source.start_with?("http://", "https://", "data:")

        from_bytes(File.binread(source), name: source)
      when Pathname then from_bytes(source.binread, name: source.to_s)
      when ActiveStorage::Attachment, ActiveStorage::Attached::One then call(source.blob)
      when ActiveStorage::Blob then from_bytes(source.download, type: source.content_type)
      else
        raise ArgumentError, "unsupported image source #{source.class}" unless source.respond_to?(:read)

        source.rewind if source.respond_to?(:rewind)
        from_bytes(source.read, name: source.try(:original_filename) || source.try(:path))
      end
    end

    def from_bytes(bytes, type: nil, name: nil)
      type ||= Marcel::MimeType.for(StringIO.new(bytes), name: name && File.basename(name.to_s))
      "data:#{type};base64,#{Base64.strict_encode64(bytes)}"
    end
  end
end
