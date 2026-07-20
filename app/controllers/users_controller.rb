# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :set_search_index_stats, only: [:edit, :update]

  def edit
    @content_templates = current_user.content_templates_list
  end

  def update
    if current_user.update(user_params)
      redirect_to edit_user_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def add_template
    name = params[:template_name].presence || "New Template"
    template = params[:template_content].presence || User.default_content_templates.first["template"]

    current_user.add_content_template(name: name, template: template)
    redirect_to edit_user_path(anchor: "content-templates"), notice: "Template added."
  end

  def update_template
    index = params[:template_index].to_i
    name = params[:template_name]
    template = params[:template_content]

    if current_user.update_content_template(index, name: name, template: template)
      redirect_to edit_user_path(anchor: "content-templates"), notice: "Template updated."
    else
      redirect_to edit_user_path(anchor: "content-templates"), alert: "Failed to update template."
    end
  end

  def delete_template
    index = params[:template_index].to_i

    if current_user.delete_content_template(index)
      redirect_to edit_user_path(anchor: "content-templates"), notice: "Template deleted."
    else
      redirect_to edit_user_path(anchor: "content-templates"), alert: "Failed to delete template."
    end
  end

  def reindex
    ReindexEmbeddingsJob.perform_later(current_user.id)
    redirect_to edit_user_path, notice: "Reindexing started in background. This may take a few minutes."
  end

  private

  def set_search_index_stats
    @content_templates = current_user.content_templates_list

    user_events = Event.joins(:source).where(sources: { user_id: current_user.id })
    @total_event_count = user_events.count
    @embedded_event_count = user_events.where.not(embedding: nil).count
  end

  def user_params
    params.require(:user).permit(:system_prompt, :event_link_template, :naddr_link_template, :profile_link_template, :default_content_style)
  end
end
