from odoo import models, fields, api
from odoo.exceptions import ValidationError


class StockInventoryLine(models.Model):
    _inherit = 'stock.inventory.line'

    # `prod_lot_id` existe déjà nativement sur stock_inventory_ajustement
    # (Many2one direct vers stock.lot) : on ne le redéfinit pas en related,
    # contrairement au v11 d'origine qui devait le créer de toutes pièces.
    number = fields.Char(string="Numéro Lot/Série")

    @api.onchange('number')
    def onchange_number(self):
        if self.number:
            lot = self.env['stock.lot'].search([('name', '=', self.number)])
            if lot:
                self.product_id = lot.product_id.id
                self.prod_lot_id = lot.id
            else:
                raise ValidationError(
                    "Le numéro '%s' ne correspond à aucun article." % self.number)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('prod_lot_id'):
                lot = self.env['stock.lot'].browse(int(vals['prod_lot_id']))
                if 'number' not in vals:
                    vals['number'] = lot.name
                else:
                    vals['product_id'] = lot.product_id.id
        return super().create(vals_list)
