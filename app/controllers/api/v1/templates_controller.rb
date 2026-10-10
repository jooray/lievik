# frozen_string_literal: true

module Api
  module V1
    # Content format templates (User#content_templates), addressed by index
    # like the web settings page.
    class TemplatesController < BaseController
      def index
        render json: {
          templates: current_user.content_templates_list.each_with_index.map do |t, i|
            { index: i, name: t["name"], template: t["template"] }
          end,
          defaults: User.default_content_templates.map { |t| { name: t["name"], template: t["template"] } }
        }
      end

      def create
        name = params[:name].presence || t("users.add_template.default_name")
        template = params[:template].presence || User.default_content_templates.first["template"]
        current_user.add_content_template(name: name, template: template)
        render json: { template: template_json(current_user.content_templates_list.size - 1), notice: t("users.add_template.notice") },
               status: :created
      end

      def update
        index = Integer(params[:index], exception: false)
        existing = index && current_user.content_templates_list[index]
        return render_error(:not_found, "not_found", t("users.update_template.alert")) unless existing && index >= 0

        ok = current_user.update_content_template(index, name: params.fetch(:name, existing["name"]),
                                                         template: params.fetch(:template, existing["template"]))
        return render_error(:not_found, "not_found", t("users.update_template.alert")) unless ok

        render json: { template: template_json(index), notice: t("users.update_template.notice") }
      end

      def destroy
        index = Integer(params[:index], exception: false)
        unless index && current_user.delete_content_template(index)
          return render_error(:not_found, "not_found", t("users.delete_template.alert"))
        end

        render json: { notice: t("users.delete_template.notice") }
      end

      private

      def template_json(index)
        t = current_user.content_templates_list[index]
        { index: index, name: t["name"], template: t["template"] }
      end
    end
  end
end
