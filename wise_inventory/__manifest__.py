{
    'name': 'Wise inventory',
    'version': '18.0.1.0.0',
    'author': 'Christian FOMEKONG',
    'category': 'Wise',
    'license': 'LGPL-3',
    'summary': "Inventaire à l'aveugle",
    'description': "Gestion de l'inventaire à l'aveugle",
    'depends': ['stock', 'stock_inventory_ajustement', 'mrp', 'point_of_sale'],
    'data': [
        'security/security.xml',
        'security/ir.model.access.csv',
        'views/view_inventory_form.xml',
        'views/menus.xml',
        'views/zone_rangement_view.xml',
        'views/sequences.xml',
        'views/general_adjustment_view.xml',
        'views/consolidation_adjustement_view.xml',
        'views/counting_sheet_view.xml',
        'views/consolidation_sheet.xml'
    ],
    'installable': True,
}
