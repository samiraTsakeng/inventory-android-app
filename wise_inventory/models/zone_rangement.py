from odoo import models, fields, api
from odoo.exceptions import ValidationError


class ZoneRangement(models.Model):

    _name = 'zone.rangement'
    _description = 'Zone de rangement'
    _rec_name = 'name'

    name = fields.Char(string='Nom', required=True)
    location_id = fields.Many2one(string='Emplacement', comodel_name="stock.location", required=True, domain=[('usage', '=', 'internal')])
    warehouse_id = fields.Many2one(comodel_name='stock.warehouse', string="Entrepôt", compute='get_warehouse')

    @api.depends('location_id')
    def get_warehouse(self):
        for rec in self:
            if rec.location_id:
                rec.warehouse_id = rec.location_id.warehouse_id.id
            else:
                rec.warehouse_id = False


    @api.onchange('location_id')
    def onchange_location(self):
        # Le rattachement à `location.zone_ids` n'est plus fait ici : dans un
        # onchange `rec` est un enregistrement virtuel (NewId), l'ajouter à
        # `zone_ids` provoquait la création d'une zone en base avant même
        # l'enregistrement du formulaire. `create()`/`write()` ci-dessous
        # assurent déjà ce rattachement à l'enregistrement.
        for rec in self:
            if rec.location_id and rec.location_id.usage != "internal":
                raise ValidationError("Cet emplacament n\'est pas un emplacement interne")

    @api.model_create_multi
    def create(self, vals_list):
        records = super(ZoneRangement, self).create(vals_list)
        for rec in records:
            rec.location_id.write({
                'zone_ids': [(4, rec.id)]
            })
        return records

    def write(self, vals):
        if 'location_id' in vals and vals['location_id'] != self.location_id.id:
            location_new = self.env['stock.location'].browse(vals['location_id'])
            location_old = self.env['stock.location'].browse(self.location_id.id)
            location_old.write({
                'zone_ids': [(3, self.id)]
            })

            location_new.write({
                'zone_ids': [(4, self.id)]
            })

        res = super(ZoneRangement, self).write(vals)

        return res


class StockLocation(models.Model):
    _inherit = "stock.location"

    zone_ids = fields.Many2many(string="Zones rattachées", comodel_name="zone.rangement", readonly=True)
