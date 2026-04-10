from ast import literal_eval
from odoo import models, fields, api
from odoo.exceptions import ValidationError


class ZoneRangement(models.Model):

    _name = 'zone.rangement'
    _rec_name = 'name'

    name = fields.Char(string='Nom', required=True)
    location_id = fields.Many2one(string='Emplacement', comodel_name="stock.location", required=True, domain=[('usage', '=', 'internal')])
    warehouse_id = fields.Many2one(comodel_name='stock.warehouse', string="Entrepôt", compute='get_warehouse')
    
    @api.depends('location_id')
    def get_warehouse(self):
        for rec in self:
            if rec.location_id:
                rec.warehouse_id = rec.location_id.warehouse_id.id

    @api.onchange('location_id')
    def onchange_location(self):
        for rec in self:
            if rec.location_id:
                location = self.env['stock.location'].search([('id', '=', rec.location_id.id)])[0]
                if location.usage == "internal":
                    location.zone_ids += rec
                else:
                    raise ValidationError("Cet emplacament n\'est pas un emplacement interne")
    
    @api.model
    def create(self, vals):
        location = self.env['stock.location'].browse(vals['location_id'])
        res = super(ZoneRangement, self).create(vals)
        location.write({
            'zone_ids': [(4, res.id)]
        })
        return res
    
    @api.multi
    def write(self, vals):
        if 'location_id' in vals and vals['location_id']!= self.location_id.id:
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
    _inherit="stock.location"

    zone_ids = fields.Many2many(string="Zones rattachées", comodel_name="zone.rangement", readonly=True)
   