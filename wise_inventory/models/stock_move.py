# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

from odoo import models


class StockMove(models.Model):
    _inherit = "stock.move"

    def _action_done(self, cancel_backorder=False):
        context = self.env.context
        number = context.get('number', None)
        if number:
            self = self[:number]
        return super(StockMove, self)._action_done(cancel_backorder=cancel_backorder)
