# frozen_string_literal: true

# Provenance and raw output of whichever engine produced relevance_score:
# {"engine": "chat"|"decision", "model": ..., and for the decision engine the
# rubric probabilities, confidence and calibration version}. Keeping the
# distribution means a threshold or calibration change can be re-applied
# without paying for a re-rate.
class AddRatingDetailsToChannelEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :channel_events, :rating_details, :json
  end
end
