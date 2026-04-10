from odoo import models, fields, api, _
from odoo.exceptions import UserError, ValidationError
import io
import xlsxwriter
import base64

class CountingSheet(models.Model):
    _name = 'consolidation.sheet'
    _description = "Feuille de Consolidation"

    name = fields.Char(string='Code')
    stock_inventory_id = fields.Many2one(comodel_name='stock.inventory', 
                                         string='Ajustement lié',
                                         ondelete='cascade')
    zone_id = fields.Many2one(comodel_name='zone.rangement', 
                              string='Zone Liée')
    consolidated = fields.Selection(default='no', selection=[('no', 'Non'), ('progress', 'En cours'), ('yes', 'Oui')], help="Used to know if a counting sheet has been consolidated")
    lines_to_consolidate = fields.Boolean(default=False)
    user_id = fields.Many2one(comodel_name='res.users', string='Resp. Comptage')
    
    # linked_sheet = fields.Many2many(comodel_name='counting.sheet', string='Feuilles de comptage associées')
    state = fields.Selection(string="Etat",
                             default='new',
                             selection=[('cancel', 'Annulé'), ('new', 'Nouveau'),
                                        ('progress', 'En cours'), ('confirm', 'Validé')]) 

    counting_contradictory_line_ids = fields.One2many(comodel_name="counting.sheet.contradictory.line",
                                        inverse_name="sheet_id",
                                        ondelete='cascade') 
    counting_line_ids = fields.One2many(comodel_name="counting.sheet.line",
                                        inverse_name="consolidation_sheet_id",
                                        ondelete='cascade')

    number = fields.Many2one('stock.production.lot', related='counting_contradictory_line_ids.lot_id', string='Numero de Série/Lot')

    def action_validate_contradictory(self):
        for record in self:
            user_connected = self.env['res.users'].browse(self.env.uid)
            obj_sheet_line = self.env['counting.sheet.line']
            if self.user_id == user_connected or user_connected.has_group('base.group_system'):
                for x in record.counting_contradictory_line_ids:
                    if x.verified_qty != 0:
                        obj_sheet_line.create({
                            'consolidation_sheet_id': record.id,
                            'lot_id': x.lot_id.id,
                            'product_id': x.product_id.id, 
                            'counted_qty': x.verified_qty
                        })
                
                record.write({'lines_to_consolidate': False, 'state': 'confirm'})
                
                record.stock_inventory_id.add_counting_sheet(record)
                sheets = self.env['counting.sheet'].search([('state', '=', 'confirm')]).filtered(lambda x: x.stock_inventory_id.id == record.stock_inventory_id.id and x.zone_id.id == record.zone_id.id and x.consolidated == 'progress')
                sheets[0].write({'consolidated': 'yes'})
                sheets[1].write({'consolidated': 'yes'})
            else: raise UserError("Vous n'êtes pas autorisé à valider cette Feuille.")


    @api.multi
    def unlink(self):
        for rec in self:
            if rec.state != 'cancel':
                raise ValidationError(f"Veuillez annuler l'Ajustement si vous souhaitez supprimer une feuille de comptage.")
            
        return super(CountingSheet, self).unlink()
    
    @api.multi
    def generate_excel_report(self):
        output = io.BytesIO()

        # Création du fichier Excel
        workbook = xlsxwriter.Workbook(output, {'in_memory': True})
        worksheet = workbook.add_worksheet()

        # Remplissage du fichier
        worksheet.write(0, 0, "REF: " + str(self.stock_inventory_id.name), workbook.add_format({'bold': True}))
        worksheet.write(0, 4, "ZONE: " + str(self.zone_id.name), workbook.add_format({'bold': True}))

        worksheet.write(3, 0, 'N° Lot/Série', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(3, 1, 'Article', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(3, 2, 'Comptage 1', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(3, 3, 'Comptage 2', workbook.add_format({'bg_color': '#ececec', 'bold': True}))
        worksheet.write(3, 4, 'Comptage 3', workbook.add_format({'bg_color': '#ececec', 'bold': True}))

        row = 4
        sheets = self.env['counting.sheet'].search([('state', '=', 'confirm')]).filtered(lambda x: x.stock_inventory_id.id == self.stock_inventory_id.id and x.zone_id.id == self.zone_id.id and x.consolidated == 'yes')
        worksheet.write(1, 0, 'Compteur 1: ' + str(sheets[0].user_id.name), workbook.add_format({'bold': True}))
        worksheet.write(1, 1, 'Compteur 2: ' + str(sheets[1].user_id.name), workbook.add_format({'bold': True}))
        worksheet.write(1, 2, 'Compteur 3: ' + str(self.user_id.name), workbook.add_format({'bold': True}))

        for record in self.counting_line_ids:
            worksheet.write(row, 0, record.lot_id.name)
            worksheet.write(row, 1, record.product_id.display_name)
            c1, c2 = False, False

            if record.lot_id.id in sheets[0].counting_line_ids.mapped('lot_id').ids:
                c1 = sheets[0].counting_line_ids.filtered(lambda x: x.lot_id.id == record.lot_id.id).counted_qty
                worksheet.write(row, 2, c1)
            else:
                worksheet.write(row, 2, '', workbook.add_format({'bg_color': '#ececec'}))
            
            if record.lot_id.id in sheets[1].counting_line_ids.mapped('lot_id').ids:
                c2 = sheets[1].counting_line_ids.filtered(lambda x: x.lot_id.id == record.lot_id.id).counted_qty
                worksheet.write(row, 3, c2)
            else:
                worksheet.write(row, 3, '', workbook.add_format({'bg_color': '#ececec'}))

            if c2 and c1:
                if c2 == c1:
                    worksheet.write(row, 4, '', workbook.add_format({'bg_color': '#ececec'}))
                else:
                    worksheet.write(row, 4, record.counted_qty)
            else:
                worksheet.write(row, 4, record.counted_qty)

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
            'datas_fname': "RAPPORT COMPTAGES " + self.zone_id.name + ".xlsx",
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
        

class CountingSheetLine(models.Model):
    _inherit = "counting.sheet.line" 

    consolidation_sheet_id = fields.Many2one(comodel_name="consolidation.sheet") # Ajout d'un champ pour le lien avec le model des feuilles de consolidation
    

    
