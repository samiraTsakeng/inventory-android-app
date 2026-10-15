# -*- coding: utf-8 -*-
import odoo
from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase


@odoo.tests.tagged('post_install', '-at_install')
class TestCheckAvailability(TransactionCase):
    """ `stock.picking.check_availability` : blocage si un ajustement de stock
    est en cours, y compris sur plusieurs transferts à la fois. """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        warehouse = cls.env['stock.warehouse'].search([('company_id', '=', cls.env.company.id)], limit=1)
        cls.stock = warehouse.lot_stock_id
        cls.other = cls.env['stock.location'].create({
            'name': 'Autre emplacement', 'location_id': warehouse.view_location_id.id, 'usage': 'internal',
        })
        supplier = cls.env.ref('stock.stock_location_suppliers')
        picking_type = warehouse.in_type_id
        cls.pickings = cls.env['stock.picking'].create([
            {'picking_type_id': picking_type.id, 'location_id': supplier.id, 'location_dest_id': cls.stock.id},
            {'picking_type_id': picking_type.id, 'location_id': supplier.id, 'location_dest_id': cls.other.id},
        ])

    def test_several_pickings_without_inventory(self):
        # Levait "Expected singleton" avant correction.
        self.pickings.check_availability()

    def test_several_pickings_with_inventory_in_progress(self):
        inventory = self.env['stock.inventory'].create({'name': 'Inventaire test', 'location_id': self.other.id})
        inventory.state = 'in_progress'
        with self.assertRaises(ValidationError):
            self.pickings.check_availability()
