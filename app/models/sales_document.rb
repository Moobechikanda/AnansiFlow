class SalesDocument < ApplicationRecord
  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :converted_from, class_name: 'SalesDocument', optional: true
  has_many :payments, class_name: 'SalesDocumentPayment', dependent: :destroy

  validates :document_type, inclusion: { in: %w[quotation invoice] }
  validates :status, inclusion: { in: %w[draft sent accepted declined expired unpaid partially_paid paid void] }
  validates :number, :customer_name, :issue_date, :currency, presence: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :line_items, presence: true
  validates :number, uniqueness: { scope: :account_id }
  validate :line_items_are_valid
  validate :associations_belong_to_account

  before_validation :calculate_totals

  scope :for_account, ->(account) { where(account:) }

  def outstanding_amount
    [total - amount_paid, 0].max
  end

  def refresh_payment_status!
    return unless invoice? && !%w[draft void].include?(status)

    update!(status: amount_paid.zero? ? 'unpaid' : (amount_paid >= total ? 'paid' : 'partially_paid'))
  end

  def invoice?
    document_type == 'invoice'
  end

  private

  def calculate_totals
    return unless line_items.is_a?(Array) && line_items.all? do |item|
      item.is_a?(Hash) && decimal_value?(item['quantity']) && decimal_value?(item['unit_price'])
    end
    return if tax_rate.blank?

    self.subtotal = line_items.sum { |item| BigDecimal(item.fetch('quantity', 0).to_s) * BigDecimal(item.fetch('unit_price', 0).to_s) }.round(2)
    self.tax_amount = (subtotal * BigDecimal(tax_rate.to_s) / 100).round(2)
    self.total = subtotal + tax_amount
  rescue ArgumentError, KeyError
    errors.add(:line_items, 'must contain valid quantities and prices')
  end

  def line_items_are_valid
    return errors.add(:line_items, 'must be a non-empty list') unless line_items.is_a?(Array) && line_items.any?

    line_items.each do |item|
      unless item.is_a?(Hash) && item['description'].present? &&
             decimal_value?(item['quantity']) && decimal_value?(item['unit_price']) &&
             BigDecimal(item['quantity'].to_s).positive? && BigDecimal(item['unit_price'].to_s) >= 0
        errors.add(:line_items, 'must have a description, positive quantity, and non-negative unit price')
        break
      end
    end
  end

  def associations_belong_to_account
    errors.add(:contact, 'must belong to this account') if contact && contact.account_id != account_id
    errors.add(:conversation, 'must belong to this account') if conversation && conversation.account_id != account_id
    return unless conversation && contact && conversation.contact_id != contact_id

    errors.add(:conversation, 'must belong to the selected customer')
  end

  def decimal_value?(value)
    BigDecimal(value.to_s)
    true
  rescue ArgumentError
    false
  end
end
