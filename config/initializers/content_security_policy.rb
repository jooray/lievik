# Be sure to restart your server when you modify this file.

# Application-wide Content Security Policy.
#
# This is the defence-in-depth layer behind output escaping: untrusted Nostr
# notes, RSS items and AI output are rendered throughout the app, so if any
# escaping bug ever slips through, CSP is what stops it from becoming script
# execution in a logged-in session.
#
# See https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    # Profile pictures come from arbitrary hosts named in Nostr kind:0 metadata,
    # so images (and only images) may load from any https origin.
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    # Inline style *attributes* (progress-bar widths, QR sizing) are unavoidable
    # in server-rendered markup. Attribute styles cannot execute script, and
    # `style-src` above still blocks injected <style> elements.
    policy.style_src_attr :unsafe_inline
    policy.connect_src :self
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # Inline <script>/<style> blocks must carry this nonce to run. Content an
  # attacker injects cannot know it.
  config.content_security_policy_nonce_generator = lambda do |request|
    request.session.id&.to_s.presence || SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # Add the nonce to javascript_tag / javascript_include_tag / stylesheet_link_tag.
  config.content_security_policy_nonce_auto = true
end
