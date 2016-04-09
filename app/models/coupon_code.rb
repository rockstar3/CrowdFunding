class CouponCode < ActiveRecord::Base
  belongs_to :coupon

  validates :code, presence: true, uniqueness: true

  scope :allocated, -> { where("allocated_on is not null") }
  scope :unallocated, -> { where(allocated_on: nil) }
end
