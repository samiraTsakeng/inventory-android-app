from odoo import models
from odoo.exceptions import ValidationError


class StockPicking(models.Model):
    _inherit = 'stock.picking'

    def action_assign(self):
        self.check_availability()
        return super(StockPicking, self).action_assign()

    def button_validate(self):
        self.check_availability()
        return super(StockPicking, self).button_validate()

    def check_availability(self):
        # Boucle par transfert : `self` peut contenir plusieurs transferts
        # (validation/réservation groupée depuis la vue liste) - l'accès
        # direct à `self.location_id` levait alors "Expected singleton".
        inventories = self.env['stock.inventory'].search([
            ('state', '=', 'in_progress'),
            ('location_id', 'in', (self.location_id | self.location_dest_id).ids),
        ])
        for picking in self:
            inventory = inventories.filtered(
                lambda x: x.location_id in (picking.location_id | picking.location_dest_id))
            if inventory:
                raise ValidationError(
                    "Il n'est pas possible d'effectuer cette opération, car un Ajustement de Stock est en cours sur un des emplacements sélectionnés.\n Emplacement: %s\n Veuillez le terminer, puis réessayez." % inventory[0].location_id.display_name)
