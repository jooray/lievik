# frozen_string_literal: true

# Where BTCPay sends a payer who paid from the Android app (the API's charges
# use this as their redirect_url). The checkout runs in a Custom Tab on top of
# the app, and the browser has no Lievik session, so the web's /billing would
# only ask them to sign in. This page hands them back through lievik://billing:
# the app's activity is singleTask, so returning to it closes the tab, and the
# app confirms the charge itself (Api::V1::BillingController#charge).
#
# BTCPay redirects automatically after payment, without a tap, and Chrome may
# refuse to open an app from a navigation nobody tapped. So the page tries at
# once and also shows the button.
class BillingReturnsController < ApplicationController
  APP_URL = "lievik://billing"

  skip_before_action :authenticate_user!

  def show
    render layout: false
  end
end
