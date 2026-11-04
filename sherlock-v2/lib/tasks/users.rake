namespace :users do
  desc "Reset a user's password and print a temporary one. For an admin locked out of the admin page."
  task :reset_password, [ :username ] => :environment do |_task, args|
    user = User.find_by!(username: args.fetch(:username).strip.downcase)
    puts "Temporary password for #{user.username}: #{user.reset_password!}"
    puts "They must pick a new one when they sign in."
  end
end
