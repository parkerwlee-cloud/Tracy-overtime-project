CREATE TABLE IF NOT EXISTS weeks (id INTEGER PRIMARY KEY,start_date DATE NOT NULL,end_date DATE NOT NULL,status TEXT NOT NULL CHECK(status IN ('draft','published','closed')) DEFAULT 'draft',created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE UNIQUE INDEX IF NOT EXISTS idx_weeks_start_date ON weeks(start_date);
