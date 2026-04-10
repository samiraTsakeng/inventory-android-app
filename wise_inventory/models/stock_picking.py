from odoo import models, fields, api, _
from odoo.exceptions import ValidationError

class StockPickng(models.Model):
    _inherit = 'stock.picking'

    
    def button_preparation(self):
        self.check_availability()
        return super(StockPickng, self).button_preparation()
    
    def action_assign(self):
        self.check_availability()
        return super(StockPickng, self).action_assign()
    
    def button_validate(self):
        self.check_availability()
        return super(StockPickng, self).button_validate()
    
    def check_availability(self):
        inventory = self.env['stock.inventory'].search([('state', '=', 'confirm')]).filtered(lambda x: x.location_id.id == self.location_id.id or x.location_id.id == self.location_dest_id.id)
        if inventory:
            raise ValidationError(f"Il n'est pas possible d'effectuer cette opération, car un Ajustement de Stock est en cours sur un des emplacements sélectionnés.\n Emplacement: {inventory[0].location_id.display_name}\n Veuillez le terminer, puis réessayez.")
        