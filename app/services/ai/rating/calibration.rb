# frozen_string_literal: true

module Ai
  module Rating
    # Maps the decision engine's raw rubric position onto the 0-100 scale the
    # chat engine writes, so a channel's relevance_threshold means the same
    # thing whichever engine rated the event.
    #
    # The raw value is the probability-weighted index on the 4-level rubric in
    # Ai::DecisionRatingService (0 = not relevant … 3 = highly relevant). Jev
    # sits systematically lower than deepseek-v4-flash-0731 on a linear
    # mapping (bias −13 points, recall 0.63 at threshold 50), so the knots are
    # a quantile match fitted on 512 channel/event pairs (2026-09-19): after
    # mapping, bias is 0 and threshold-50 agreement with the chat model is 86%
    # (κ 0.70), against the chat model's own run-to-run 91% (κ 0.80).
    #
    # Re-fit if the rubric text, the model, or the chat baseline changes; bump
    # VERSION so stored rating_details say which mapping produced the score.
    module Calibration
      VERSION = "jev4-v1"

      KNOTS = [
        [ 0.0, 5 ],
        [ 0.5, 25 ],
        [ 1.0, 45 ],
        [ 1.5, 76 ],
        [ 2.0, 88 ],
        [ 2.5, 91 ],
        [ 3.0, 100 ]
      ].freeze

      module_function

      def to_score(raw)
        raw = raw.to_f.clamp(KNOTS.first[0], KNOTS.last[0])

        KNOTS.each_cons(2) do |(x0, y0), (x1, y1)|
          next if raw > x1

          return (y0 + (y1 - y0) * (raw - x0) / (x1 - x0)).round.clamp(0, 100)
        end

        KNOTS.last[1]
      end
    end
  end
end
