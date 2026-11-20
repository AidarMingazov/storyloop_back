class GenerationLog < ApplicationRecord
  STEPS = %w[script images layout tokens audio].freeze

  belongs_to :episode, optional: true

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, default: :running, validate: true

  validates :step, inclusion: { in: STEPS }
end
