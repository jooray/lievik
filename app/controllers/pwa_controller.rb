# frozen_string_literal: true

# Serves the PWA plumbing: the service worker and the version endpoint the
# client polls to notice a new deploy.
class PwaController < ApplicationController
  skip_before_action :authenticate_user!

  # Rails blocks cross-origin <script> embedding of JS responses. The worker
  # holds no user data and the browser fetches it outside the normal request
  # flow, so the check only gets in the way here.
  skip_forgery_protection

  # The service worker must be served from the app root to have "/" scope.
  def service_worker
    expires_in 0, public: false, must_revalidate: true
    render template: "pwa/service_worker",
           formats: :js,
           layout: false,
           content_type: "text/javascript"
  end

  def version
    expires_in 0, public: false, must_revalidate: true
    render json: { version: Lievik::BUILD_VERSION }
  end
end
