# Sherlock loads nothing from other hosts: fonts, icons and scripts are vendored. So the browser may only
# run scripts from this host, and only send forms and requests here.
#
# Styles allow 'unsafe-inline': views use style attributes, and Carbon Charts and Turbo's progress bar
# add inline styles. That's why style-src gets no nonce, since a nonce would switch 'unsafe-inline' off.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data
    policy.font_src :self, :data
    policy.connect_src :self # Covers Action Cable's wss:// to this host too.
    policy.manifest_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # Inline scripts that Rails or a gem writes, like Mission Control's importmap, carry this nonce.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
