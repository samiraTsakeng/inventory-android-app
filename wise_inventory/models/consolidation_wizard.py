# -*- coding: utf-8 -*-

from bdb import set_trace
from odoo import api, fields, models, _
from odoo.exceptions import ValidationError

class AjustmentConsolidation(models.TransientModel):
    _name = "adjustment.consolidation"
    _description = "Permet de de consolider deux feuilles de comptage"
    
    stock_inventory_id = fields.Many2one(comodel_name='stock.inventory', 
            string='Ajustement en cours', domain=[('state', '=', 'confirm'), ('is_general', '=', True)])
    location_id = fields.Many2one(comodel_name='stock.location', string='Emplacement Inventorié',
            related='stock_inventory_id.location_id')
    
    zone_v_ids = fields.Many2many(comodel_name='zone.rangement', compute='_compute_zone_ids')
    
    @api.depends('stock_inventory_id')
    def _compute_zone_ids(self):
        zones = self.location_id.zone_ids
        for zone in zones:
            sheets = self.env['counting.sheet'].search([('state', '=', 'confirm')]).filtered(lambda x: x.zone_id.id == zone.id and x.stock_inventory_id.id == self.stock_inventory_id.id and x.consolidated == 'no')
            if len(sheets) == 2:
                self.zone_v_ids += zone
    
    zone_id =  fields.Many2one(comodel_name="zone.rangement", string="Zone consolidée",
        domain="[('id', 'in', zone_v_ids)]")    
    
    def zone_domain(self):
        zone_ids = self.env['counting.sheet'].search([('state', '=', 'confirm')]).filtered(lambda x: x.stock_inventory_id.id == self.stock_inventory_id.id and x.stock_inventory_id.state == 'confirm' and x.consolidated == 'no').mapped('zone_id').ids        
        return [('id', 'in', zone_ids)]

    def confirm_btn(self):
        sheet_ids = self.env['counting.sheet'].search([('zone_id', '=', self.zone_id.id), ('state', '=', 'confirm'), ('stock_inventory_id', '=', self.stock_inventory_id.id), ('consolidated', '=', 'no')])
        consolidating_sheet = self.env['consolidation.sheet'].create({
            'name': 'COMPIL COMPTAGES 1 & 2 - %s' % (sheet_ids[0].zone_id.name),
            'stock_inventory_id': sheet_ids[0].stock_inventory_id.id,
            'zone_id': sheet_ids[0].zone_id.id,
            'user_id': sheet_ids[0].stock_inventory_id.manager_id.id
        })       
        contradictory_lines = []
        correspondant_lines = []
        sheet_one = [(item.lot_id.id, item.product_id.id, item.counted_qty) for item in sheet_ids[0].counting_line_ids]
        sheet_two = [(line.lot_id.id, line.product_id.id, line.counted_qty) for line in sheet_ids[1].counting_line_ids]
        
        correspondant_lines += [{'lot_id': node[0], 'product_id': node[1], 'counted_qty': node[2]} for node in sheet_one if node in sheet_two]
        contradictory_lines += [{'lot_id': node[0], 'product_id': node[1]} for node in sheet_one if node not in sheet_two]
        contradictory_lines += [{'lot_id': node[0], 'product_id': node[1]} for node in sheet_two if node not in sheet_one if (node[0], node[1]) not in [(x[0], x[1]) for x in sheet_one]]
        sheet_ids[0].write({'consolidated': 'progress'})
        sheet_ids[1].write({'consolidated': 'progress'})
    
        if correspondant_lines:
            consolidating_sheet.counting_line_ids = [(0, 0, x) for x in correspondant_lines]

        if contradictory_lines:
            consolidating_sheet.write({'lines_to_consolidate': True})
            consolidating_sheet.counting_contradictory_line_ids = [(0, 0, x) for x in contradictory_lines]
        else:
            consolidating_sheet.action_validate_contradictory()