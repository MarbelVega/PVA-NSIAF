class SeguroSerializer < ActiveModel::Serializer
  self.root = false
  attributes :id, :supplier, :user, :numero_contrato, :factura_numero, :factura_autorizacion, :factura_fecha, :fecha_inicio_vigencia, :fecha_fin_vigencia, :baja_logica
  has_many :assets, serializer: AssetSerializer
end
