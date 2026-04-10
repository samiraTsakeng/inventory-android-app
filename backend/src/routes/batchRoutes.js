const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/batchController');
const { protect } = require('../middleware/authMiddleware');

router.post('/create', protect, ctrl.createBatch);
router.post('/join', protect, ctrl.joinBatch);
router.post('/:batchId/scan', protect, ctrl.scanItem);
router.get('/:batchId/items', protect, ctrl.getBatchItems);
router.put('/:batchId/item/:itemId', protect, ctrl.updateItem);
router.delete('/:batchId/item/:itemId', protect, ctrl.deleteItem);
router.post('/:batchId/submit', protect, ctrl.submitBatch);
router.get('/archive', protect, ctrl.getArchive);

module.exports = router;

/*const express = require('express');
const router = express.Router();
const { createBatch } = require('../controllers/batchController');
const authMiddleware = require('../middleware/authMiddleware');

router.post('/', authMiddleware, createBatch);

module.exports = router;*/
