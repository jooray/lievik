# frozen_string_literal: true

class ManualEventsController < ApplicationController
  def new
    @event = Event.new
  end

  def create
    result = ManualEvents::Creator.new(current_user, content: params[:event][:content]).call
    @event = result.event

    if result.success?
      redirect_to dashboard_path, notice: "Event added successfully. Rating in background."
    else
      @event ||= Event.new(content: params[:event][:content])
      render :new, status: :unprocessable_entity
    end
  end
end
