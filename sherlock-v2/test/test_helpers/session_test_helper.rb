module SessionTestHelper
  def sign_in_as(user)
    post session_path, params: { username: user.username, password: "correct-horse-battery" }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
