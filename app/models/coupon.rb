class Coupon < ActiveRecord::Base
  belongs_to :project_source
  has_many :coupon_codes

  validates :campaign_name, presence: true, uniqueness: true

  def display_name
    "Campaign: #{campaign_name}"
  end

  def allocate_code!(metadata = nil)
    coupon_code = coupon_codes.unallocated.first
    coupon_code.metadata = metadata
    coupon_code.allocated_on = DateTime.current
    coupon_code.save!
    coupon_code.code
  end
end
