from odoo import models, fields, api
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

    state = fields.Selection(string="Etat",
                             default='new',
                             selection=[('cancel', 'Annulé'), ('new', 'Nouveau'),
                                        ('progress', 'En cours'), ('confirm', 'Validé')])

    counting_line_ids = fields.One2many(comodel_name="counting.sheet.line",
                                        inverse_name="sheet_id",)

    number = fields.Char(related='counting_line_ids.number', string='Numero de Série/Lot')

    def action_validate(self):
        for record in self:
            user_connected = self.env.user
            if self.user_id == user_connected or user_connected.has_group('base.group_system'):
                if not record.counting_line_ids:
                    raise ValidationError("Aucune ligne comptée")
                else:
                    record.write({'state': 'confirm'})
            else:
                raise UserError("Vous n'êtes pas autorisé à valider ce comptage.")

    def action_begin(self):
        for record in self:
            user_connected = self.env.user
            if self.user_id != user_connected:
                raise ValidationError("Vous n'êtes pas autorisé à effectuer ce Comptage.")

            sheets = self.env['counting.sheet'].search([('zone_id', '=', record.zone_id.id), ('stock_inventory_id', '=', record.stock_inventory_id.id), ('state', '=', 'progress')])
            if sheets:
                raise ValidationError("Veuillez terminer le comptage précédent sur cette zone, et réessayer.")
            record.write({'state': 'progress'})

    def write(self, vals):
        res = super(CountingSheet, self).write(vals)
        if 'user_id' in vals:
            user_connected = self.env.user
            if self.stock_inventory_id.manager_id != user_connected and not user_connected.has_group('base.group_system'):
                raise ValidationError("Vous n'êtes pas autorisé à modifier le Resp. Comptage.")

        if self.counting_line_ids:
            ids_list = [elt.lot_id for elt in self.counting_line_ids]
            for inv in ids_list:
                if ids_list.count(inv) > 1:
                    raise UserError("Le numéro '%s' ne peut être présent plus d'une fois sur la feuille de comptage." % inv.name)

        return res

    def unlink(self):
        for rec in self:
            if rec.state != 'cancel':
                raise ValidationError("Veuillez annuler l'Ajustement si vous souhaitez supprimer une feuille de comptage.")

        return super(CountingSheet, self).unlink()


class CountingSheetLine(models.Model):
    _name = "counting.sheet.line"
    _description = "Lignes de feuille de comptage"

    sheet_id = fields.Many2one(comodel_name="counting.sheet")
    number = fields.Char(string="Numéro")
    # readonly=False : en v18, un champ calculé readonly passé à create() est
    # recalculé (ici depuis `number`, vide pour les lignes créées par la
    # consolidation) ; en v11 la valeur fournie était conservée.
    lot_id = fields.Many2one(string="Numero de Série/Lot",
                             comodel_name="stock.lot", compute='_compute_lot_id', store=True, readonly=False)
    product_id = fields.Many2one(comodel_name="product.product",
                                 string="Article", compute="_compute_lot_id", store=True, readonly=False)
    counted_qty = fields.Integer(string="Quantité comptée")



    @api.depends('number')
    def _compute_lot_id(self):
        for rec in self:
            if rec.number:
                lot = self.env['stock.lot'].search([('name', '=', rec.number)])
                if lot:
                    rec.product_id = lot.product_id.id
                    rec.lot_id = lot.id
                else:
                    rec.product_id = False
                    rec.lot_id = False
                    raise ValidationError("Le numéro '%s' ne correspond à aucun article." % rec.number)
            else:
                rec.product_id = False
                rec.lot_id = False

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            product = self.env['product.product'].browse(vals['product_id'])
            if product.tracking == 'serial' and vals['counted_qty'] != 1:
                raise ValidationError(
                    "L'article '%s' est suivi par N° de série. \n La quantité comptée pour le numéro '%s' ne peut être différente de 1." % (
                        product.name, self.env['stock.lot'].browse(vals.get('lot_id')).name))
            elif vals['counted_qty'] < 1:
                raise ValidationError(
                    "La quantité comptée de l'article '%s', Numéro: '%s' doit être non nulle." % (
                        product.name, self.env['stock.lot'].browse(vals.get('lot_id')).name))

        res = super(CountingSheetLine, self).create(vals_list)

        return res

    def write(self, vals):
        res = super(CountingSheetLine, self).write(vals)
        if self.product_id:
            if self.product_id.tracking == 'serial' and self.counted_qty != 1:
                raise ValidationError(
                    "L'article '%s' est suivi par N° de série. \n La quantité comptée pour le numéro '%s' ne peut être différente de 1." % (
                        self.product_id.name, self.lot_id.name))
            elif self.counted_qty < 1:
                raise ValidationError(
                    "La quantité comptée de l'article '%s', Numéro: '%s' doit être non nulle." % (
                        self.product_id.name, self.lot_id.name))

        return res


class CountingSheetContradictoryLine(models.Model):
    _name = "counting.sheet.contradictory.line"
    _description = "Lignes contracdictoire de feuille de comptage"

    sheet_id = fields.Many2one(comodel_name="consolidation.sheet")
    lot_id = fields.Many2one(string="Numero de Série/Lot",
                             comodel_name="stock.lot",
                            required=True)
    product_id = fields.Many2one(comodel_name="product.product",
                                string="Article")
    verified_qty = fields.Integer(string="Quantité Vérifiée",
                                  default=0)

    def write(self, vals):
        res = super(CountingSheetContradictoryLine, self).write(vals)
        if self.product_id:
            if self.product_id.tracking == 'serial' and self.verified_qty != 1:
                raise ValidationError(
                    "L'article '%s' est suivi par N° de série. \n La quantité comptée pour le numéro '%s' ne peut être différente de 1." % (
                        self.product_id.name, self.lot_id.name))
            elif self.verified_qty < 1:
                raise ValidationError(
                    "La quantité comptée de l'article '%s', Numéro: '%s' doit être non nulle." % (
                        self.product_id.name, self.lot_id.name))

        return res
