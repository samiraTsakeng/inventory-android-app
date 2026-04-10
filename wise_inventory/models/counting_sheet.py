from odoo import models, fields, api, _
from odoo.exceptions import UserError, ValidationError

class CountingSheet(models.Model):
    _name = 'counting.sheet'
    _description = "Feuille de comptage"

    name = fields.Char(string='Code')
    stock_inventory_id = fields.Many2one(comodel_name='stock.inventory', 
                                         string='Ajustement lié',
                                         ondelete='cascade')
    zone_id = fields.Many2one(comodel_name='zone.rangement', 
                              string='Zone Liée')
    consolidated = fields.Selection(default='no', selection=[('no', 'Non'), ('progress', 'En cours'), ('yes', 'Oui')], help="Used to know if a counting sheet has been consolidated")
    user_id = fields.Many2one(comodel_name='res.users', string='Resp. Comptage')
    
    # linked_sheet = fields.Many2many(comodel_name='counting.sheet', string='Feuilles de comptage associées')
    state = fields.Selection(string="Etat",
                             default='new',
                             selection=[('cancel', 'Annulé'), ('new', 'Nouveau'),
                                        ('progress', 'En cours'), ('confirm', 'Validé')]) 

    counting_line_ids = fields.One2many(comodel_name="counting.sheet.line",
                                        inverse_name="sheet_id",
                                        ondelete='cascade')

    number = fields.Char(  related='counting_line_ids.number', string='Numero de Série/Lot')



    def action_validate(self):
        for record in self:
            user_connected = self.env['res.users'].browse(self.env.uid)
            if self.user_id == user_connected or user_connected.has_group('base.group_system'):
                if not record.counting_line_ids:
                    raise ValidationError("Aucune ligne comptée")
                else:
                    record.write({'state': 'confirm'})
            else: raise UserError("Vous n'êtes pas autorisé à valider ce comptage.")
    
    def action_begin(self):
        for record in self:
            user_connected = self.env['res.users'].browse(self.env.uid)
            if self.user_id != user_connected:
                raise ValidationError("Vous n'êtes pas autorisé à effectuer ce Comptage.")
            
            sheets = self.env['counting.sheet'].search([('zone_id', '=', record.zone_id.id), ('stock_inventory_id', '=', record.stock_inventory_id.id), ('state', '=', 'progress')])
            if sheets:
                raise ValidationError(f"Veuillez terminer le comptage précédent sur cette zone, et réessayer.")
            record.write({'state': 'progress'})

    @api.multi
    def write(self, vals):
        res = super(CountingSheet, self).write(vals)
        if 'user_id' in vals:
            user_connected = self.env['res.users'].browse(self.env.uid)
            if self.stock_inventory_id.manager_id != user_connected and not user_connected.has_group('base.group_system'):
                raise ValidationError("Vous n'êtes pas autorisé à modifier le Resp. Comptage.")
        
        if self.counting_line_ids:
            ids_list = [elt.lot_id for elt in self.counting_line_ids]
            for inv in ids_list:
                if ids_list.count(inv) > 1:
                    raise UserError(f"Le numéro '{inv.name}' ne peut être présent plus d'une fois sur la feuille de comptage.")
                
        return res

    @api.multi
    def unlink(self):
        for rec in self:
            if rec.state != 'cancel':
                raise ValidationError(f"Veuillez annuler l'Ajustement si vous souhaitez supprimer une feuille de comptage.")
            
        return super(CountingSheet, self).unlink()
           

class CountingSheetLine(models.Model):
    _name="counting.sheet.line"
    _description="Lignes de feuille de comptage"

    sheet_id = fields.Many2one(comodel_name="counting.sheet")
    number = fields.Char(string="Numéro")
    lot_id = fields.Many2one(string="Numero de Série/Lot",
                             comodel_name="stock.production.lot")
    product_id = fields.Many2one(comodel_name="product.product",
                                 string="Article")
    counted_qty = fields.Integer(string="Quantité comptée")

    @api.onchange('lot_id')
    def onchange_lot_id(self):
        for rec in self:
            if rec.lot_id:
                rec.product_id = rec.lot_id.product_id.id
    
    @api.onchange('number')
    def onchange_number(self):
        if self.number:
            lot = self.env['stock.production.lot'].search([('name', '=', self.number)])
            if lot:
                self.product_id = lot.product_id.id
                self.lot_id = lot.id
            else: 
                self.product_id = ''
                self.lot_id = ''
                raise ValidationError(f"Le numéro '{self.number}' ne correspond à aucun article.")

    @api.model
    def create(self, vals):
        product = self.env['product.product'].browse(vals['product_id'])
        if product.tracking == 'serial' and vals['counted_qty'] != 1:
            raise ValidationError(f"L'article '{product.name}'' est suivi par N° de série. \n La quantité comptée pour le numéro '{self.env['stock.production.lot'].search([('id', '=', vals['lot_id'])]).name}' ne peut être différente de 1.")
        elif vals['counted_qty'] < 1:
            raise ValidationError(f"La quantité comptée de l'article '{product.name}', Numéro: '{self.env['stock.production.lot'].search([('id', '=', vals['lot_id'])]).name}' doit être non nulle.")
        
        res = super(CountingSheetLine, self).create(vals)
        
        return res
    
    @api.multi
    def write(self, vals):
        res = super(CountingSheetLine, self).write(vals)
        if self.product_id:
            if self.product_id.tracking == 'serial' and self.counted_qty != 1:
                raise ValidationError(f"L'article '{self.product_id.name}' est suivi par N° de série. \n La quantité comptée pour le numéro '{self.lot_id.name}' ne peut être différente de 1.")
            elif self.counted_qty < 1:
                raise ValidationError(f"La quantité comptée de l'article '{self.product_id.name}', Numéro: '{self.lot_id.name}' doit être non nulle.")
        
        return res

    
class CountingSheetContradictoryLine(models.Model):
    _name="counting.sheet.contradictory.line"
    _description="Lignes contracdictoire de feuille de comptage"

    sheet_id = fields.Many2one(comodel_name="consolidation.sheet")
    lot_id = fields.Many2one(string="Numero de Série/Lot",
                             comodel_name="stock.production.lot",
                            required=True)
    product_id = fields.Many2one(comodel_name="product.product",
                                string="Article")
    verified_qty = fields.Integer(string="Quantité Vérifiée",
                                  default=0)

    @api.multi
    def write(self, vals):
        res = super(CountingSheetContradictoryLine, self).write(vals)
        if self.product_id:
            if self.product_id.tracking == 'serial' and self.verified_qty != 1:
                raise ValidationError(f"L'article '{self.product_id.name}' est suivi par N° de série. \n La quantité comptée pour le numéro '{self.lot_id.name}' ne peut être différente de 1.")
            elif self.verified_qty < 1:
                raise ValidationError(f"La quantité comptée de l'article '{self.product_id.name}', Numéro: '{self.lot_id.name}' doit être non nulle.")
        
        return res

    
