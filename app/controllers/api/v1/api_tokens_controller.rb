# frozen_string_literal: true

module Api
  module V1
    # The same token list as /user/edit (app device tokens included).
    class ApiTokensController < BaseController
      def index
        tokens = current_user.api_tokens.order(created_at: :desc)
        render json: { api_tokens: tokens.map { |token| Serializers.api_token(token, current: current_api_token) } }
      end

      def create
        name = params[:name].to_s.strip
        return render_error(:unprocessable_content, "invalid", t("api_tokens.create.name_required"), details: { name: [ t("api_tokens.create.name_required") ] }) if name.blank?

        token = ApiToken.generate(current_user, name: name)
        render json: { api_token: Serializers.api_token(token, current: current_api_token), plain_token: token.plain_token }, status: :created
      end

      def destroy
        current_user.api_tokens.find(params[:id]).destroy
        render json: { notice: t("api_tokens.destroy.notice") }
      end
    end
  end
end
