# -*- coding: utf-8 -*-
import odoo
from odoo.tests.common import TransactionCase


@odoo.tests.tagged('post_install', '-at_install')
class TestConsolidation(TransactionCase):
    """ Intégration des feuilles de consolidation dans l'ajustement : les
    lignes de consolidation (créées avec lot/article, sans `number`) doivent
    garder leur article. """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        warehouse = cls.env['stock.warehouse'].search([('company_id', '=', cls.env.company.id)], limit=1)
        cls.stock = warehouse.lot_stock_id
        cls.product = cls.env['product.product'].create({
            'name': 'Article suivi par lot', 'is_storable': True, 'tracking': 'lot',
        })
        cls.lot = cls.env['stock.lot'].create({'name': 'LOT-CONSO-1', 'product_id': cls.product.id})
        cls.env['stock.quant']._update_available_quantity(cls.product, cls.stock, 5, lot_id=cls.lot)

    def test_location_id_drives_location_ids(self):
        other = self.env['stock.location'].create({
            'name': 'Autre emplacement', 'usage': 'internal',
            'location_id': self.stock.location_id.id,
        })
        self.env['stock.quant']._update_available_quantity(self.product, other, 2, lot_id=self.lot)
        inventory = self.env['stock.inventory'].create({
            'name': 'Inventaire emplacement', 'location_id': other.id,
            'prefill_counted_quantity': 'counted',
        })
        self.assertEqual(inventory.location_ids, other)
        inventory.action_start()
        self.assertEqual(inventory.line_ids.location_id, other)
        self.assertEqual(inventory.line_ids.theoretical_qty, 2)
        inventory.action_state_to_draft()
        inventory.location_id = self.stock
        self.assertEqual(inventory.location_ids, self.stock)

    def test_update_adjustement_from_consolidation(self):
        inventory = self.env['stock.inventory'].create({
            'name': 'Inventaire général test',
            'location_id': self.stock.id,
            'location_ids': [(6, 0, self.stock.ids)],
            'start_empty': True,
            'is_general': True,
        })
        inventory.action_start()
        inventory.action_state_to_in_progress()
        sheet = self.env['consolidation.sheet'].create({
            'name': 'COMPIL TEST', 'stock_inventory_id': inventory.id, 'state': 'confirm',
        })
        sheet.counting_line_ids = [(0, 0, {
            'lot_id': self.lot.id, 'product_id': self.product.id, 'counted_qty': 3,
        })]
        self.assertEqual(sheet.counting_line_ids.product_id, self.product)
        self.assertEqual(sheet.counting_line_ids.lot_id, self.lot)

        inventory.add_counting_sheet(sheet)
        inventory.update_adjustement()

        line = inventory.line_ids
        self.assertEqual(line.product_id, self.product)
        self.assertEqual(line.prod_lot_id, self.lot)
        self.assertEqual(line.product_qty, 3)
        self.assertEqual(line.theoretical_qty, 5)
