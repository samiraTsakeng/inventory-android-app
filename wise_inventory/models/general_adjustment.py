# -*- coding: utf-8 -*-

from datetime import datetime
from odoo import api, fields, models, _
from odoo.exceptions import ValidationError
from itertools import cycle

class GeneralAdjustment(models.TransientModel):
    _name = "general.adjustment"
    _description = "Permet de démarrer un inventaire général"

    date = fields.Date(string='Date de comptage')
    location_id =  fields.Many2one(comodel_name="stock.location",
                                  string="Emplacement Inventorié",
                                   domain=[('usage', '=', 'internal')] )
    reference = fields.Char(string="Référence de l'ajustement", compute='get_ref')
    
    def manager_domain(self):
        user_ids = self.env['res.users'].search([]).filtered(lambda x: x.has_group('wise_inventory.resp_inventory')).ids
        return [('id', 'in', user_ids)]
    
    def user_domain(self):
        user_ids = self.env['res.users'].search([]).filtered(lambda x: x.has_group('wise_inventory.counting_group')).ids
        return [('id', 'in', user_ids)]
    
    manager_id = fields.Many2one(comodel_name='res.users', string="Resp. Ajustement", required=True, domain=lambda self: self.manager_domain())
    user_ids = fields.Many2many(comodel_name='res.users', string="Resp. Equipes", domain=lambda self: self.user_domain())
    zone_ids = fields.Many2many(comodel_name='zone.rangement', string="Zones ", readonly=True)

    

    def confirm_btn(self):
        if self.env['pos.session'].search([('state', '=', 'opened')]).filtered(lambda x: x.config_id.stock_location_id.id == self.location_id.id):
            raise ValidationError('Une session de point de vente est ouverte sur cet emplacement. Veuillez la fermer, puis réessayez.')

        elif self.env['stock.inventory'].search([('state', '=', 'confirm')]).filtered(lambda x: x.location_id.id == self.location_id.id):
            raise ValidationError('Un Ajustement est en cours sur cet emplacement. Veuillez le terminer, puis réessayez.')
        elif not self.location_id.zone_ids:
            raise ValidationError('Votre emplacement ne comporte aucune zone de rangement')
        elif len(self.user_ids) > 2*len(self.location_id.zone_ids):
            raise ValidationError(f"Le nombre de Resp. Equipe doit être inférieur ou égal au nombre de feuilles de comptage.\n Nombre de feuilles: {2*len(self.location_id.zone_ids)}")
        else:
            stock_inventory_vals = {'date': self.date,
                                   'location_id': self.location_id.id,
                                   'name': self.reference,
                                   'filter': 'none',
                                   'is_general': True,
                                   'manager_id': self.manager_id.id}
            stock_inventory_id = self.env['stock.inventory'].create(stock_inventory_vals)
            sheets = []

            if stock_inventory_id:               
                for zone in self.location_id.zone_ids:
                    counting_sheet_vals = {
                                            'stock_inventory_id': stock_inventory_id.id,
                                            'zone_id': zone.id}
                    counting_sheet_vals['name']  = 'COMPTAGE 1 - ' + zone.name
                    sheet_1 = self.env['counting.sheet'].create(counting_sheet_vals) 

                    counting_sheet_vals['name']  = 'COMPTAGE 2 - ' + zone.name
                    sheet_2 = self.env['counting.sheet'].create(counting_sheet_vals)
                    
                    sheets.append(sheet_1)
                    sheets.append(sheet_2)

                cyclic_user = cycle(self.user_ids.ids)
                for sheet in sheets:
                    sheet.write({'user_id': next(cyclic_user)})
            
            stock_inventory_id.action_start()

    @api.onchange('location_id')
    def check_zone(self):
        self.zone_ids = False
        if self.location_id and self.location_id.zone_ids:
            self.zone_ids += self.location_id.zone_ids
    
    @api.depends('location_id', 'date')
    def get_ref(self):
        if self.location_id and self.date:
            self.reference = "INVENTAIRE GENERAL - " + self.location_id.display_name + " - " + datetime.strftime(datetime.strptime(self.date, '%Y-%m-%d'), '%y%m%d')
        else:
            self.reference = ''
