# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :set_search_index_stats, only: [:edit, :update]

  def edit
    @content_templates = current_user.content_templates_list
  end

  def update
    if current_user.update(user_params)
      cookies[LOCALE_COOKIE] = { value: current_user.locale, expires: 1.year, same_site: :lax } if current_user.locale
      I18n.locale = current_user.locale || I18n.locale
      redirect_to edit_user_path, notice: t(".notice")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def add_template
    name = params[:template_name].presence || t(".default_name")
    template = params[:template_content].presence || User.default_content_templates.first["template"]

    current_user.add_content_template(name: name, template: template)
    redirect_to edit_user_path(anchor: "content-templates"), notice: t(".notice")
  end

  def update_template
    index = params[:template_index].to_i
    name = params[:template_name]
    template = params[:template_content]

    if current_user.update_content_template(index, name: name, template: template)
      redirect_to edit_user_path(anchor: "content-templates"), notice: t(".notice")
    else
      redirect_to edit_user_path(anchor: "content-templates"), alert: t(".alert")
    end
  end

  def delete_template
    index = params[:template_index].to_i

    if current_user.delete_content_template(index)
      redirect_to edit_user_path(anchor: "content-templates"), notice: t(".notice")
    else
      redirect_to edit_user_path(anchor: "content-templates"), alert: t(".alert")
    end
  end

  def reindex
    ReindexEmbeddingsJob.perform_later(current_user.id)
    redirect_to edit_user_path, notice: t(".notice")
  end

  private

  def set_search_index_stats
    @content_templates = current_user.content_templates_list

    user_events = Event.joins(:source).where(sources: { user_id: current_user.id })
    @total_event_count = user_events.count
    @embedded_event_count = user_events.where.not(embedding: nil).count
  end

  def user_params
    params.require(:user).permit(:system_prompt, :event_link_template, :naddr_link_template, :profile_link_template, :default_content_style, :rating_engine, :locale)
  end
end
