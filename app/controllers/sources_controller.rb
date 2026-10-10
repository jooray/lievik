# frozen_string_literal: true

class SourcesController < ApplicationController
  before_action :set_source, only: [:show, :edit, :update, :destroy, :refresh]
  requires_paid_access only: [:refresh, :refresh_all]

  def index
    @sources = current_user.sources.where.not(source_type: :manual).order(:name)
    @event_counts = Event.where(source_id: @sources.map(&:id)).group(:source_id).count
  end

  def show
    @events = @source.events.recent.page(params[:page])
  end

  def new
    @source = current_user.sources.build(source_type: params[:source_type] || :nostr)
  end

  def create
    @source = current_user.sources.build(source_params)

    if @source.save
      # Trial start and ingestion as in the app API (Sources::Actions).
      notice = Sources::Actions.after_create(@source, current_user).message

      redirect_to sources_path, notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @source.update(source_params)
      redirect_to sources_path, notice: t(".notice")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @source.destroy
    redirect_to sources_path, notice: t(".notice")
  end

  def refresh
    result = Sources::Actions.refresh(@source)
    redirect_to sources_path, (result.ok? ? :notice : :alert) => result.message
  end

  def refresh_all
    redirect_to sources_path, notice: Sources::Actions.refresh_all(current_user).message
  end

  private

  def set_source
    @source = current_user.sources.find(params[:id])
  end

  def source_params
    params.require(:source).permit(:identifier, :name, :description, :distance, :source_type,
      :settings_include_replies, :settings_include_reposts, :settings_import_days)
  end
end
