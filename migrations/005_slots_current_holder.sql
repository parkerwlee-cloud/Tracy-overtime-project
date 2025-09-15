ALTER TABLE slots ADD COLUMN assigned_employee_id INTEGER REFERENCES employees(id);
