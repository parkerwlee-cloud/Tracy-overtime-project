CREATE TABLE IF NOT EXISTS signups (id INTEGER PRIMARY KEY,slot_id INTEGER NOT NULL REFERENCES slots(id),employee_id INTEGER NOT NULL REFERENCES employees(id),created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX IF NOT EXISTS idx_signups_slot ON signups(slot_id);
CREATE INDEX IF NOT EXISTS idx_signups_employee ON signups(employee_id);
