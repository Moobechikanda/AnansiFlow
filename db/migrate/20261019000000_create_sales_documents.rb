  class CreateSalesDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_documents do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :converted_from, foreign_key: { to_table: :sales_documents }
      t.string :document_type, null: false
      t.string :number, null: false
      t.string :status, null: false, default: 'draft'
      t.string :currency, null: false, default: 'ZMW'
      t.string :customer_name, null: false
      t.string :customer_email
      t.string :customer_phone
      t.jsonb :line_items, null: false, default: []
      t.decimal :subtotal, precision: 14, scale: 2, null: false, default: 0
      t.decimal :tax_rate, precision: 7, scale: 4, null: false, default: 0
      t.decimal :tax_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :total, precision: 14, scale: 2, null: false, default: 0
      t.decimal :amount_paid, precision: 14, scale: 2, null: false, default: 0
      t.date :issue_date, null: false
      t.date :due_date
      t.date :valid_until
      t.text :notes
      t.text :terms
      t.timestamps
    end

    add_index :sales_documents, [:account_id, :number], unique: true
    add_index :sales_documents, [:account_id, :document_type, :status]

    create_table :sales_document_payments do |t|
      t.references :sales_document, null: false, foreign_key: true
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :method, null: false
      t.string :provider
      t.string :reference
      t.date :paid_at, null: false
      t.text :notes
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
