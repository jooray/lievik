# frozen_string_literal: true

Rails.application.config.solid_queue.connects_to = { database: { writing: :queue } }
