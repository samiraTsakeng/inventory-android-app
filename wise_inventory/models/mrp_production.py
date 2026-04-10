from odoo import models, fields, api, _
from odoo.exceptions import ValidationError

class MrpProduction(models.Model):
    _inherit = 'mrp.production'

    
    def action_assign(self):
        self.check_availability()
        return super(MrpProduction, self).action_assign()
    
    def open_produce_product(self):
        self.check_availability()
        return super(MrpProduction, self).open_produce_product()
    
    def check_availability(self):
        inventory = self.env['stock.inventory'].search([('state', '=', 'confirm')]).filtered(lambda x: x.location_id.id == self.location_src_id.id or x.location_id.id == self.location_dest_id.id)
        if inventory:
            raise ValidationError(f"Il n'est pas possible d'effectuer cette opération, car un Ajustement de Stock est en cours sur un des emplacements sélectionnés.\n Emplacement: {inventory[0].location_id.display_name}\n Veuillez le terminer, puis réessayez.")
    