module Ai
  # What the review screen shows per pipeline step, from the episode's GenerationLogs.
  class PipelineStatus
    Row = Data.define(:step, :status, :model, :cost_usd, :duration_ms, :notes, :error)
    NAMES = { "script" => "Сценарий", "images" => "Картинки", "layout" => "Пузыри", "tokens" => "Разметка",
              "audio" => "Озвучка" }.freeze

    def initialize(episode)
      @episode = episode
      @logs = episode.generation_logs.order(:id).to_a.group_by(&:step)
    end

    def rows = Pipeline::STEPS.map { |step| row(step) }

    def total_usd = @logs.values.flatten.sum(&:cost_usd)

    # "p3b1" ids of bubbles the last markup could not finish.
    def unresolved_bubbles = last("tokens")&.metadata.to_h.fetch("unresolved", {})

    # Latest image log of each panel that failed: {panel_id => error}.
    def failed_panels
      Array(@logs["images"]).group_by { |log| log.metadata["panel_id"] }.transform_values(&:last)
                            .select { |_, log| log.failed? }.transform_values(&:error)
    end

    private
      def last(step) = Array(@logs[step]).last

      def row(step)
        logs = Array(@logs[step])
        log = logs.last
        return Row.new(step:, status: nil, model: nil, cost_usd: 0, duration_ms: nil, notes: nil, error: nil) unless log

        status = step == "images" ? images_status(logs) : log.status
        Row.new(step:, status:, model: log.model, cost_usd: logs.sum(&:cost_usd), duration_ms: log.duration_ms,
                notes: notes(step, log), error: (log.error if log.failed?))
      end

      def images_status(logs)
        latest = logs.group_by { |log| log.metadata["panel_id"] }.values.map(&:last)
        return "running" if latest.any?(&:running?)

        latest.any?(&:failed?) ? "failed" : "succeeded"
      end

      def notes(step, log)
        meta = log.metadata
        case step
        when "script"
          [ "попыток: #{meta['attempts']}", *Array(meta["warnings"]) ].compact.join(" · ") if meta["attempts"]
        when "images"
          panels = @episode.panels.includes(image_attachment: :blob).to_a # fresh: steps attach in other threads
          "нарисовано #{panels.count { |panel| !panel.needs_image? }} из #{panels.size}" + (failed_panels.any? ? " · ошибок: #{failed_panels.size}" : "")
        when "layout" then "расставлено: #{meta['bubbles']}" if meta["bubbles"]
        when "tokens"
          [ ("токенов: #{meta['tokens']}" if meta["tokens"]),
            ("не размечено: #{meta['unresolved'].keys.join(', ')}" if meta["unresolved"].present?) ].compact.join(" · ")
        when "audio"
          [ ("реплик: #{meta['bubbles']}, лемм: #{meta['lemmas']}" if meta["bubbles"]),
            ("ошибок: #{meta['failed'].size}" if meta["failed"].present?) ].compact.join(" · ")
        end
      end
  end
end
