# Scraped by the user's own Prometheus with the token from Settings → Developer, never a session.
class Users::MetricsController < ActionController::Base
  rate_limit to: 30, within: 1.minute

  def show
    user = authenticate_with_http_token { |token, _| User.find_by_metrics_token(token) }
    return request_http_token_authentication("Sherlock") unless user

    render plain: user.metrics, content_type: "text/plain; version=0.0.4; charset=utf-8"
  end
end
