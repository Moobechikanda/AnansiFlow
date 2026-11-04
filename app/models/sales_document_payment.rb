class SalesDocumentPayment < ApplicationRecord
  belongs_to :sales_document
  belongs_to :recorded_by, class_name: 'User', optional: true

  validates :amount, numericality: { greater_than: 0 }
  validates :method, inclusion: { in: %w[mobile_money bank_transfer cash card other] }
  validates :paid_at, presence: true

  after_create :update_document_payment_status

  private

  def update_document_payment_status
    sales_document.with_lock do
      sales_document.update!(amount_paid: sales_document.amount_paid + amount)
      sales_document.refresh_payment_status!
    end
  end
end
