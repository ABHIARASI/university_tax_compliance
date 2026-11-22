// /api/meta : lists the forms need (dropdown options)
import { Router } from 'express';
import { query } from '../config/db.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

// public: the registration form needs these before anyone is logged in
router.get('/states', async (req, res) => {
  res.json(await query('SELECT State_Code, State_Name FROM indian_state ORDER BY State_Name'));
});

router.get('/registration-options', (req, res) => {
  res.json({
    institutionTypes: ['Central', 'State', 'Deemed', 'Private'],
    itExemptions: ['10(23C)(iiiab) - Govt funded', '10(23C)(iiiad) - Receipts up to 5 crore',
                   '10(23C)(vi) - Approved institution', '12AB - Registered trust', 'None'],
  });
});

// logged-in users: income sources with how each is taxed
router.get('/income-sources', requireAuth, async (req, res) => {
  res.json(await query(
    `SELECT s.Source_ID, s.Source_Name, r.Income_Type, r.GST_Category, r.Tax_Rate,
            r.TDS_Rate, r.Special_Rule, r.Conditions
     FROM income_source s JOIN tax_rule r ON r.TaxRule_ID = s.TaxRule_ID
     ORDER BY r.TaxRule_ID, s.Source_Name`
  ));
});

export default router;
