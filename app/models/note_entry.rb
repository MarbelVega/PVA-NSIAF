class NoteEntry < ActiveRecord::Base
  include Autoincremento

  default_scope {where(invalidate: false)}

  scope :del_anio_por_fecha_factura, -> (fecha) { where(invoice_date: fecha.beginning_of_year..fecha.end_of_year) }
  scope :mayor_a_fecha_factura, -> (fecha) { where('invoice_date > ?', fecha) }
  scope :menor_igual_a_fecha_factura, -> (fecha) { where('invoice_date <= ?', fecha) }
  scope :con_fecha_factura, -> { where.not('invoice_date is null') }

  belongs_to :supplier
  belongs_to :user

  has_many :entry_subarticles
  accepts_nested_attributes_for :entry_subarticles
  has_many :kardexes

  has_paper_trail

  before_save :set_note_entry_date

  def supplier_name
    supplier.present? ? supplier.name : ''
  end

  def supplier_nit
    supplier.present? ? supplier.nit : ''
  end

  def user_name
    user.present? ? user.name : ''
  end

  def user_title
    user.present? ? user.title : ''
  end

  def note_number(number)
    number.present? ? "##{number}" : ''
  end

  def note_date(date)
    date.present? ? I18n.l(date) : ''
  end

  def get_delivery_note_number
    invoice = ''
    if delivery_note_number.present?
      invoice += "#{delivery_note_number}"
    elsif delivery_note_date.present?
      invoice += "#{I18n.l delivery_note_date, format: :default}"
    end
  end

  def get_invoice_number
    invoice = ''
    if invoice_number.present?
      invoice += "#{invoice_number}"
    elsif invoice_date.present?
      invoice += "#{I18n.l invoice_date, format: :default}"
    end
    invoice.strip
  end

  def self.array_model(sort_column, sort_direction, page, per_page, sSearch, search_column, current_user = '')
    orden = "#{sort_column} #{sort_direction}"
    case sort_column
    when "note_entries.note_entry_date"
      orden += ", note_entries.nro_nota_ingreso #{sort_direction}, note_entries.incremento_alfabetico #{sort_direction}"
    when "note_entries.nro_nota_ingreso"
      orden += ", note_entries.incremento_alfabetico #{sort_direction}"
    end
    array = joins(:user, :supplier).order(orden)
    array = array.page(page).per_page(per_page) if per_page.present?
    if sSearch.present?
      if search_column.present?
        type_search = %w(users suppliers).include?(search_column) ? "#{search_column}.name" : "note_entries.#{search_column}"
        array = array.where("#{type_search} like :search", search: "%#{sSearch}%")
      else
        array = array.where("note_entries.nro_nota_ingreso LIKE ? OR suppliers.name LIKE ? OR users.name LIKE ? OR note_entries.total LIKE ?", "%#{sSearch}%", "%#{sSearch}%", "%#{sSearch}%", "%#{sSearch}%")
      end
    end
    array
  end

  def self.set_columns
    h = ApplicationController.helpers
    [h.get_column(self, 'nro_nota_ingreso'), h.get_column(self, 'suppliers'), h.get_column(self, 'users'), h.get_column(self, 'total'), h.get_column(self, 'delivery_note_date')]
  end

  def self.to_csv
    columns = %w(id suppliers users total delivery_note_date)
    CSV.generate do |csv|
      csv << columns.map { |c| self.human_attribute_name(c) }
      all.each do |note_entry|
        a = note_entry.attributes.values_at(*columns)
        a.pop(4)
        a.push(note_entry.supplier_name)
        a.push(note_entry.user_name)
        a.push(note_entry.total)
        a.push(note_entry.note_date(note_entry.delivery_note_date))
        csv << a
      end
    end
  end

  ##
  # TODO definir éste campo a nivel de tabla para las notas de entrada
  # Cuando se cree el campo eliminar éste método
  def c31_fecha
    ''
  end

  def change_date_entries
    entry_subarticles.each do |entry|
      entry.set_date_value
      entry.save
    end
  end

  def change_kardexes
    kardexes.each do |kardex|
      kardex.kardex_date = note_entry_date
      kardex.invoice_number = get_invoice_number
      kardex.delivery_note_number = get_delivery_note_number
      kardex.save
    end
  end

  # Anula una Nota de Entrada, y también los subartículos asociados al mismo.
  # Es necesario especificar el motivo de la anulación
  def invalidate_note(message="")
    transaction do
      update(invalidate: true, message: message)
      entry_subarticles.invalidate_entries
      kardexes.invalidate_kardexes
    end
  end

  def obtiene_nro_nota_ingreso
    if !incremento_alfabetico.present?
      "#{nro_nota_ingreso}"
    else
      "#{nro_nota_ingreso}-#{incremento_alfabetico}"
    end
  end

  def self.nro_nota_ingreso_anterior(fecha)
    fecha = fecha.to_date
    self.del_anio_por_fecha_factura(fecha).menor_igual_a_fecha_factura(fecha).where.not(nro_nota_ingreso: 0).maximum(:nro_nota_ingreso)
  end

  def self.nro_nota_ingreso_posterior(fecha)
    fecha = fecha.to_date
    self.del_anio_por_fecha_factura(fecha).mayor_a_fecha_factura(fecha).where.not(nro_nota_ingreso: 0).minimum(:nro_nota_ingreso)
  end

  def tiene_nro_nota_ingreso?
    nro_nota_ingreso > 0 && invoice_date.present?
  end

  def self.nro_nota_ingreso_posterior_regularizado(fecha)
    fecha = fecha.to_date
    nro_nota_ingreso = self.nro_nota_ingreso_anterior(fecha)
    self.del_anio_por_fecha_factura(fecha).mayor_a_fecha_factura(fecha).where(nro_nota_ingreso: nro_nota_ingreso).first.try(:incremento_alfabetico)
  end
  private

  def set_note_entry_date
    self.note_entry_date = get_first_date
  end

  def get_first_date
    if invoice_date
      first_date = invoice_date
    elsif delivery_note_date
      first_date = delivery_note_date
    else
      first_date = Time.now.to_date
    end
    first_date.to_date
  end
end
