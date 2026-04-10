from odoo import models, fields, api, _
from odoo.addons import decimal_precision as dp
from odoo.exceptions import ValidationError


class StockInventoryLine(models.Model):

    _inherit = 'stock.inventory.line'
    lot_id = fields.Many2one('stock.production.lot', _('Lot/Serial Number'))
    prod_lot_id = fields.Many2one('stock.production.lot', _('Lot/Serial Number'), related="lot_id")
    number = fields.Char(string="Numéro Lot/Série")

    @api.onchange('number')
    def onchange_number(self):
        if self.number:
            lot = self.env['stock.production.lot'].search([('name', '=', self.number)])
            if lot:
                self.product_id = lot.product_id.id
                self.lot_id = lot.id
                self.prod_lot_id = lot.id
            else: raise ValidationError(f"Le numéro '{self.number}' ne correspond à aucun article.")

    @api.model
    def create(self, vals):
        if 'number' not in vals:
            vals['number'] = self.env['stock.production.lot'].browse(int(vals['prod_lot_id'])).name
        else: vals['product_id'] = self.env['stock.production.lot'].browse(int(vals['prod_lot_id'])).product_id.id
        
        res = super(StockInventoryLine, self).create(vals)
        
        return res
