class IntegrationGrant < ApplicationRecord
  belongs_to :user
  belongs_to :integration
end
