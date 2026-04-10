from odoo import models, fields, api, _
from odoo.exceptions import ValidationError
import io
import xlsxwriter
import base64

class StockInventory(models.Model):
    _inherit = 'stock.inventory'

    location_id = fields.Many2one(comodel_name='stock.location', string='Emplacement Inventorié', readonly=True, required=True, domain=[('usage', '=', 'internal')])
    
    consolidated_sheet_ids = fields.Many2many(comodel_name="consolidation.sheet",
                                          string="Feuilles consolidées",
                                          domain=[('state', '=', 'confirm')])
    manager_id = fields.Many2one(comodel_name='res.users', string='Resp. Ajustement', readonly=True)
    is_general = fields.Boolean(string="Est Général ?", help="Permet de savoir si un ajustement est général ou pas.", default=False)
    consolidated = fields.Boolean(string="Consolidé ?", help="Permet de savoir si les feuilles de consolidation ont été intégrées ou pas.", default=False)
    display_consolid = fields.Boolean(string="Toutes les consolidations sont validées ?", default=False, compute='get_consolid',
        help="Permet de savoir si les feuilles de consolidation sont validées ou pas, afin d'afficher le bouton d'intégration de ces feuilles.")
    
    def bulk_consolidation(self):
        for adjustment in self:
            sheet_ids = adjustment.consolidated_sheet_ids
            if not sheet_ids:
                raise ValidationError("Aucune feuille de consolidation n'a été validée pour cet Ajustement.")
            
            consolidation_dict = {}
            for sheet in sheet_ids:
                for line in sheet.counting_line_ids:
                    key = (line.lot_id, line.product_id)
                    if key not in consolidation_dict:
                        consolidation_dict[key] = line
                    else:
                        if line.product_id.tracking == "lot":
                            consolidation_dict[key].counted_qty += line.counted_qty
                        elif line.product_id.tracking == "serial":
                            continue

            consolidation_sheet = list(consolidation_dict.values())
            return consolidation_sheet

    def update_adjustement(self):
        for adjustment in self:
            consolidation_sheet = adjustment.bulk_consolidation()
            consolidation_dict = {(item.lot_id, item.product_id): item for item in consolidation_sheet}
            adj_line_dict = {(line.lot_id, line.product_id): line for line in adjustment.line_ids}
            
            for line in adjustment.line_ids:
                key = (line.lot_id, line.product_id)
                if key not in consolidation_dict:
                    line.product_qty = 0
                else:
                    item = consolidation_dict[key]
                    line.product_qty = item.counted_qty if line.product_id.tracking == 'lot' else 1

            obj_inv_line = self.env['stock.inventory.line']

            for key, item in consolidation_dict.items():
                if key not in adj_line_dict:
                    obj_inv_line.create({
                        'product_id': item.product_id.id,
                        'prod_lot_id': item.lot_id.id,
                        'product_qty': item.counted_qty,
                        'location_id': self.location_id.id,
                        'inventory_id': self.id
                    })

            adjustment.consolidated = True
            adjustment.display_consolid = False
    
    def add_counting_sheet(self, sheet):
        self.consolidated_sheet_ids += sheet

    @api.depends('consolidated_sheet_ids')
    def get_consolid(self):
        self.display_consolid = False
        if not self.consolidated and self.consolidated_sheet_ids:
            if self.is_general and len(self.env['consolidation.sheet'].search([('stock_inventory_id', '=', self.id), ('state', '=', 'confirm')])) == len(self.consolidated_sheet_ids):
                self.display_consolid = True

    def action_cancel_draft(self):
        sheet_ids = self.env['counting.sheet'].search([('stock_inventory_id', '=', self.id)])
        for sheet in sheet_ids:
            sheet.write({'state': 'cancel'})
            sheet.unlink()

        return super(StockInventory, self).action_cancel_draft()
    
    @api.multi
    def generate_excel_report(self):
        output = io.BytesIO()

        # Création du fichier Excel
        workbook = xlsxwriter.Workbook(output, {'in_memory': True})
        worksheet = workbook.add_worksheet()

        # Remplissage du fichier
        worksheet.write(0, 0, 'N° Lot/Série', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(0, 1, 'Article', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(0, 2, 'Quantité Théorique', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(0, 3, 'Quantité Réelle', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(0, 4, 'Ecart', workbook.add_format({'bg_color': '#ececec', 'bold': True}))

        row = 1
        for record in self.line_ids:
            worksheet.write(row, 0, record.prod_lot_id.name)
            worksheet.write(row, 1, record.product_id.display_name)
            worksheet.write(row, 2, record.theoretical_qty)
            worksheet.write(row, 3, record.product_qty)
            gap = record.product_qty - record.theoretical_qty
            if gap > 0:
                worksheet.write(row, 4, gap, workbook.add_format({'font_color': '#4c9173'}))
            elif gap == 0:
                worksheet.write(row, 4, '')
            else:
                worksheet.write(row, 4, gap, workbook.add_format({'font_color': '#d63447'}))
                
            row += 1

        # Fermeture du fichier
        workbook.close()

        # Encodage du fichier Excel en base64 pour le retourner comme attachement
        output.seek(0)
        file_data = output.read()
        file_base64 = base64.b64encode(file_data)

        # Création d'un attachement pour le téléchargement
        attachment = self.env['ir.attachment'].create({
            'name': 'Report.xlsx',
            'datas': file_base64,
            'datas_fname': "RAPPORT " + str(self.name) + ".xlsx",
            'mimetype': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        })

        # Téléchargement
        base_url = self.env['ir.config_parameter'].get_param('web.base.url')
        download_url = '/web/content/' + str(attachment.id) + '?download=true'
        
        return {
            "type": "ir.actions.act_url",
            "url": str(base_url) + str(download_url),
            "target": "new",
        }

    def counting_sheet(self):
        self.ensure_one()
        action = self.env.ref('wise_inventory.counting_sheet_action').read()[0]
        domain = [('stock_inventory_id', '=', self.id)]
        action['domain'] = domain

        return action
    
    def consolidation_sheet(self):
        self.ensure_one()
        action = self.env.ref('wise_inventory.consolidation_sheet_action').read()[0]
        domain = [('stock_inventory_id', '=', self.id)]
        action['domain'] = domain

        return action
    
    @api.model
    def create(self, vals):
        if 'location_id' in vals and self.env['pos.session'].search([('state', '=', 'opened')]).filtered(lambda x: x.config_id.stock_location_id.id == vals['location_id']):
            raise ValidationError('Une session de point de vente est ouverte sur cet emplacement. Veuillez la fermer, puis réessayez.')
        
        res = super(StockInventory, self).create(vals)
        
        return res