class CreditBank < ActiveRecord::Base
  attr_protected :current

  belongs_to :bankable, polymorphic: true, touch: true
end
