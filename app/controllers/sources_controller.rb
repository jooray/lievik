# frozen_string_literal: true

class SourcesController < ApplicationController
  before_action :set_source, only: [:show, :edit, :update, :destroy, :refresh]

  def index
    @sources = current_user.sources.where.not(source_type: :manual).order(:name)
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
      redirect_to sources_path, notice: "Source added successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @source.update(source_params)
      redirect_to sources_path, notice: "Source updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @source.destroy
    redirect_to sources_path, notice: "Source removed"
  end

  def refresh
    if @source.nostr? || @source.rss?
      SourceIngestionJob.perform_later(@source.id)
      redirect_to sources_path, notice: "Refreshing #{@source.name || 'source'} in the background. Check Activity Log for progress."
    else
      redirect_to sources_path, alert: "Cannot refresh this source type"
    end
  end

  def refresh_all
    sources = current_user.sources.where(source_type: [:nostr, :rss])
    sources.find_each do |source|
      SourceIngestionJob.perform_later(source.id)
    end

    redirect_to sources_path, notice: "Refreshing #{sources.count} sources in the background. Check Activity Log for progress."
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
