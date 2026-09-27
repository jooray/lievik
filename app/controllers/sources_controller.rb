# frozen_string_literal: true

class SourcesController < ApplicationController
  before_action :set_source, only: [:show, :edit, :update, :destroy, :refresh]

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
      # Without this the dashboard stays empty until the user discovers the
      # small refresh icon — the first-run flow reads as broken.
      if @source.nostr? || @source.rss?
        SourceIngestionJob.perform_later(@source.id)
        notice = t(".importing")
      else
        notice = t(".notice")
      end

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
    if @source.nostr? || @source.rss?
      SourceIngestionJob.perform_later(@source.id)
      redirect_to sources_path, notice: (@source.name.present? ? t(".notice", name: @source.name) : t(".notice_unnamed"))
    else
      redirect_to sources_path, alert: t(".unsupported")
    end
  end

  def refresh_all
    sources = current_user.sources.where(source_type: [:nostr, :rss])
    sources.find_each do |source|
      SourceIngestionJob.perform_later(source.id)
    end

    redirect_to sources_path, notice: t(".notice", count: sources.count)
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
