class Api::V1::Accounts::SalesDocumentsController < Api::V1::Accounts::BaseController
  before_action :set_sales_document, only: [:show, :update, :destroy, :convert, :payments]

  def index
    documents = Current.account.sales_documents.includes(:contact, :payments).order(created_at: :desc)
    documents = documents.where(document_type: params[:type]) if %w[quotation invoice].include?(params[:type])
    render json: documents.as_json(include: { payments: {}, contact: { only: [:id, :name, :email, :phone_number] } }, methods: [:outstanding_amount])
  end

  def show
    render json: @sales_document.as_json(include: :payments, methods: [:outstanding_amount])
  end

  def create
    type = params.require(:sales_document).fetch(:document_type)
    raise ActionController::BadRequest unless %w[quotation invoice].include?(type)

    document = nil
    Current.account.with_lock do
      document = Current.account.sales_documents.build(document_params.merge(
        document_type: type,
        number: next_number(type),
        created_by: Current.user,
        issue_date: Date.current
      ))
      document.status = type == 'invoice' ? 'unpaid' : 'draft'
      document.save!
    end
    render json: document, status: :created
  end

  def update
    attributes = document_params
    if attributes.key?(:status)
      allowed_transitions = { 'draft' => %w[sent], 'sent' => %w[accepted declined expired] }
      unless @sales_document.document_type == 'quotation' && allowed_transitions.fetch(@sales_document.status, []).include?(attributes[:status])
        raise ActionController::BadRequest, 'Invalid document status transition'
      end
      @sales_document.update!(status: attributes[:status])
    else
      raise ActionController::BadRequest, 'Only draft documents can be edited' unless @sales_document.status == 'draft'

      @sales_document.update!(attributes.except(:document_type, :number, :amount_paid, :status))
    end
    render json: @sales_document
  end

  def destroy
    raise ActionController::BadRequest unless @sales_document.status == 'draft' && @sales_document.payments.none?

    @sales_document.destroy!
    head :no_content
  end

  def convert
    raise ActionController::BadRequest unless @sales_document.document_type == 'quotation' && @sales_document.status == 'accepted'

    invoice = nil
    created = false
    Current.account.with_lock do
      invoice = Current.account.sales_documents.find_by(converted_from: @sales_document)
      unless invoice
        invoice = Current.account.sales_documents.create!(
          @sales_document.attributes.slice('contact_id', 'conversation_id', 'customer_name', 'customer_email', 'customer_phone',
                                           'line_items', 'subtotal', 'tax_rate', 'tax_amount', 'total', 'currency', 'notes', 'terms')
                                  .merge(document_type: 'invoice', status: 'unpaid', issue_date: Date.current,
                                         due_date: Date.current + 30.days, number: next_number('invoice'),
                                         converted_from: @sales_document, created_by: Current.user)
        )
        created = true
      end
    end
    render json: invoice, status: created ? :created : :ok
  end

  def payments
    payment = nil
    @sales_document.with_lock do
      raise ActionController::BadRequest, 'Payments can only be recorded for open invoices' unless @sales_document.invoice? && !%w[draft void].include?(@sales_document.status)
      payment = @sales_document.payments.build(payment_params.merge(recorded_by: Current.user))
      raise ActiveRecord::RecordInvalid.new(payment) unless payment.valid?
      raise ActionController::BadRequest, 'Payment exceeds the outstanding balance' if payment.amount > @sales_document.outstanding_amount

      payment.save!
    end
    render json: payment, status: :created
  end

  private

  def set_sales_document
    @sales_document = Current.account.sales_documents.find(params[:id])
  end

  def next_number(type)
    prefix = type == 'quotation' ? 'QUO' : 'INV'
    sequence = Current.account.sales_documents.where(document_type: type).count + 1
    format('%<prefix>s-%<year>d-%<sequence>04d', prefix:, year: Date.current.year, sequence:)
  end

  def document_params
    params.require(:sales_document).permit(:contact_id, :conversation_id, :customer_name, :customer_email, :customer_phone,
                                           :currency, :tax_rate, :due_date, :valid_until, :notes, :terms, :status,
                                           line_items: [:description, :quantity, :unit_price])
  end

  def payment_params
    params.require(:payment).permit(:amount, :method, :provider, :reference, :paid_at, :notes)
  end
end
